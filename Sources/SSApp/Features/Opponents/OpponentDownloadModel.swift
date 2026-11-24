import Foundation
import Observation
import SSCore

/// State and logic of "Scarica tutti gli avversari…": read the league teams of every active team, review
/// what was found, write the ticked rows in one transaction, then download the logos still missing.
/// Nothing is written before "Salva"; nothing runs until the user starts it.
@MainActor @Observable
final class OpponentDownloadModel: Identifiable {
  enum Phase: Equatable {
    case idle
    case reading
    case review
    case saving
    case done
    case failed(String)
  }

  /// "Lettura di Juniores… 3 di 9".
  struct Progress: Equatable {
    var team: String
    var current: Int
    var total: Int
  }

  /// What "Salva" did, for the report.
  struct Summary: Equatable {
    var created = 0
    var renamed = 0
    var aliases = 0
    var logos = 0
  }

  /// Reads the bytes of one CSI logo; `nil` = no direct download is allowed or it failed.
  typealias CSILogoReader = @MainActor @Sendable (CSILogoRequest) async -> Data?

  /// The CSI logos are downloaded this many at a time.
  static let csiLogoConcurrency = 4

  let services: AppServices

  private(set) var phase: Phase = .idle
  private(set) var progress: Progress?
  /// What went wrong while reading (shown at the top of the review).
  private(set) var readingIssues: [ImportIssue] = []
  private(set) var candidates: [OpponentCandidate] = []
  private(set) var pairs: [OpponentDuplicatePair] = []
  /// The opponents the rows were matched against, as they were when the reading ended.
  private(set) var existing: [Opponent] = []
  private(set) var summary: Summary?
  /// Reading and logo issues after "Salva", errors first.
  private(set) var reportIssues: [ImportIssue] = []

  var ticked: Set<String> = []
  var choices: [String: OpponentMergeChoice] = [:]
  /// Shown in a standard alert (the transaction failed).
  var errorMessage: String?

  /// Called when the sheet closes, so the screen can reload.
  @ObservationIgnored var onClose: @MainActor () -> Void = {}

  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var teamNames: [EntityID: String] = [:]
  @ObservationIgnored private var csiReadAt: [EntityID: Date] = [:]
  @ObservationIgnored private let csiLogoReader: CSILogoReader?

  /// - Parameter csiLogoReader: how a CSI logo is downloaded; `nil` = never (the logos are reported as not
  ///   available). The default is the T4.8c direct download, when it is allowed.
  init(services: AppServices, csiLogoReader: CSILogoReader? = OpponentDownloadModel.directCSIReader()) {
    self.services = services
    self.csiLogoReader = csiLogoReader
  }

  /// The T4.8c `CSILogoDownloader`, only when `CSIBrowserController.allowsDirectLogoDownload` is on.
  static func directCSIReader() -> CSILogoReader? {
    guard CSIBrowserController.allowsDirectLogoDownload else { return nil }
    let downloader = CSILogoDownloader()
    return { request in try? await downloader.download(request.logoURL) }
  }

  // MARK: Teams with a source

  /// The active teams that have a Tuttocampo widget or a CSI page, in sheet order.
  static func sourceTeams(_ teams: [Team]) -> [Team] {
    teams.filter { $0.isActive && (hasWidget($0) || hasCSIPage($0)) }.sorted { $0.sortOrder < $1.sortOrder }
  }

  static func hasWidget(_ team: Team) -> Bool { !(team.tuttocampoWidgetID ?? "").isEmpty }
  static func hasCSIPage(_ team: Team) -> Bool { !(team.csiPageURL ?? "").isEmpty }

  // MARK: Reading

  /// Starts reading in a task the model can cancel.
  func start() {
    task?.cancel()
    task = Task { await read() }
  }

  /// Reads every source, one team at a time, then builds the review rows. Awaitable, so tests can run it to
  /// the end. One failing team never stops the others. When the task is cancelled nothing is kept and the
  /// phase goes back to `.idle`.
  func read() async {
    phase = .reading
    progress = nil
    readingIssues = []
    candidates = []
    pairs = []
    ticked = []
    choices = [:]
    summary = nil
    reportIssues = []
    let settings: ClubSettings
    let teams: [Team]
    let opponents: [Opponent]
    do {
      settings = try services.settings.load()
      teams = Self.sourceTeams(try services.teams.list())
      opponents = try services.opponents.list()
    } catch {
      phase = .failed((error as? AppError)?.localizedDescription ?? OpponentsStrings.downloadLoadFailed)
      return
    }
    teamNames = Dictionary(teams.map { ($0.id, $0.name) }) { first, _ in first }
    csiReadAt = [:]

    var found: [SourceTeam] = []
    var issues: [ImportIssue] = []
    for (index, team) in teams.enumerated() {
      if Task.isCancelled { return cancelled() }
      progress = Progress(team: team.name, current: index + 1, total: teams.count)
      if Self.hasWidget(team) {
        do {
          switch try await services.fixtureSource.fetchLeagueTeams(for: team, settings: settings) {
          case .teams(let listed): found += listed
          case .structureChanged: issues.append(.standingsChanged(team: team.name))
          }
        } catch is CancellationError {
          return cancelled()
        } catch let reason as FixtureFetchError {
          issues.append(.standingsReadFailed(team: team.name, reason: reason))
        } catch {
          issues.append(.standingsReadFailed(team: team.name, reason: .network))
        }
      }
      if Self.hasCSIPage(team) {
        if let list = try? services.sourceTeamLists.latest(teamID: team.id, source: .csi) {
          found += list.teams
          csiReadAt[team.id] = list.readAt
        } else {
          issues.append(.csiTeamListMissing(team: team.name))
        }
      }
    }
    if Task.isCancelled { return cancelled() }

    existing = opponents
    readingIssues = issues
    candidates = OpponentCandidate.make(found: found, existing: opponents, clubShortName: settings.clubShortName)
    pairs = OpponentCandidate.possibleDuplicatePairs(in: candidates, existing: opponents)
    ticked = Set(candidates.filter(\.isTickedByDefault).map(\.id))
    progress = nil
    phase = .review
  }

  private func cancelled() {
    progress = nil
    phase = .idle
  }

  /// "Annulla" while reading: stops the task, keeps nothing and closes the sheet.
  func cancelReading() {
    task?.cancel()
    close()
  }

  /// Closes the sheet. A running task is cancelled.
  func close() {
    task?.cancel()
    task = nil
    onClose()
  }

  // MARK: Review

  func isTickable(_ candidate: OpponentCandidate) -> Bool { candidate.state != .present }

  func isTicked(_ candidate: OpponentCandidate) -> Bool {
    isTickable(candidate) && ticked.contains(candidate.id)
  }

  func setTicked(_ candidate: OpponentCandidate, _ on: Bool) {
    guard isTickable(candidate) else { return }
    if on { ticked.insert(candidate.id) } else { ticked.remove(candidate.id) }
  }

  var tickedCount: Int { candidates.filter(isTicked).count }

  /// A pair needs a choice only while its new row(s) are ticked.
  func needsChoice(_ pair: OpponentDuplicatePair) -> Bool {
    guard ticked.contains(pair.firstCandidateID) else { return false }
    return pair.second.candidateID.map { ticked.contains($0) } ?? true
  }

  func choice(for pair: OpponentDuplicatePair) -> OpponentMergeChoice? { choices[pair.id] }

  func setChoice(_ choice: OpponentMergeChoice?, for pair: OpponentDuplicatePair) {
    choices[pair.id] = choice
  }

  /// The writes of "Salva" for the current ticks and choices, or why they cannot be built yet.
  var plan: Result<OpponentImportPlan, OpponentPlanError> {
    do throws(OpponentPlanError) {
      return .success(
        try OpponentImportPlan.make(candidates: candidates, ticked: ticked, pairs: pairs, choices: choices))
    } catch {
      return .failure(error)
    }
  }

  var canSave: Bool {
    guard phase == .review, case .success(let plan) = plan else { return false }
    return !plan.items.isEmpty
  }

  /// The line above the buttons: why "Salva" is disabled.
  var planMessage: String? {
    switch plan {
    case .failure(let error): error.message
    case .success(let plan): plan.items.isEmpty ? OpponentsStrings.downloadNothingSaved : nil
    }
  }

  /// One line per place the name was seen, without repeats.
  func sightingLines(_ candidate: OpponentCandidate) -> [String] {
    var lines: [String] = []
    for sighting in candidate.sightings {
      let team = teamNames[sighting.teamID] ?? ""
      let line: String
      switch sighting.source {
      case .tuttocampo:
        line = OpponentsStrings.seenTuttocampo(team)
      case .csi:
        let date = csiReadAt[sighting.teamID].map(Self.dayText) ?? ""
        line = OpponentsStrings.seenCSI(team, date: date)
      }
      if !lines.contains(line) { lines.append(line) }
    }
    return lines
  }

  /// "22 novembre".
  static func dayText(_ date: Date) -> String {
    date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "it_IT")))
  }

  static func stateTitle(_ state: OpponentCandidate.State) -> String {
    switch state {
    case .new: OpponentsStrings.stateNew
    case .missingLogo: OpponentsStrings.stateMissingLogo
    case .present: OpponentsStrings.statePresent
    case .possibleDuplicate: OpponentsStrings.statePossibleDuplicate
    }
  }

  /// What the logo column shows: the existing opponent's own logo, a symbol for a logo that can be
  /// downloaded, or nothing. No image is downloaded before "Salva".
  enum RowLogo: Equatable {
    case local(URL)
    case available
    case none
  }

  func rowLogo(_ candidate: OpponentCandidate) -> RowLogo {
    if let file = candidate.existing?.logoFile { return .local(services.logos.url(for: file)) }
    return candidate.logo != nil ? .available : .none
  }

  // MARK: Save

  /// Writes the plan in one transaction, then downloads the logos still missing. A failed transaction shows
  /// an alert and leaves the review as it was. Awaitable, so tests can run it to the end.
  func save() async {
    guard canSave, case .success(let plan) = plan else { return }
    phase = .saving
    let stored: [Opponent]
    do {
      stored = try services.opponents.applyImport(plan)
    } catch {
      errorMessage = (error as? AppError)?.localizedDescription ?? OpponentsStrings.saveFailed
      phase = .review
      return
    }
    var result = Summary()
    for item in plan.items {
      switch item.action {
      case .create(_, let aliases):
        result.created += 1
        result.aliases += aliases.count
      case .update(_, let rename, let addAliases):
        if rename != nil {
          result.renamed += 1
          result.aliases += 1
        }
        result.aliases += addAliases.count
      }
    }
    var issues = readingIssues
    var writer = LogoWriter(services: services)
    await downloadLogos(plan: plan, stored: stored, writer: &writer, issues: &issues)
    result.logos = writer.stored
    issues += writer.issues
    summary = result
    reportIssues = issues.enumerated().sorted { lhs, rhs in
      lhs.element.isError != rhs.element.isError ? lhs.element.isError : lhs.offset < rhs.offset
    }.map(\.element)
    phase = .done
  }

  private func downloadLogos(
    plan: OpponentImportPlan, stored: [Opponent], writer: inout LogoWriter, issues: inout [ImportIssue]
  ) async {
    var tuttocampo: [LogoRequest] = []
    var csi: [CSILogoRequest] = []
    for (item, opponent) in zip(plan.items, stored) where opponent.logoFile == nil {
      guard let logo = item.logo else { continue }
      switch logo.source {
      case .tuttocampo:
        if let request = LogoRequest(opponent: opponent, sourceTeam: logo) {
          tuttocampo.append(request)
        } else {
          writer.issues.append(.logoNotRecognised(opponent: opponent.name))
        }
      case .csi:
        if let request = CSILogoRequest(opponent: opponent, sourceTeam: logo) {
          csi.append(request)
        } else {
          writer.issues.append(.csiLogoUnavailable(opponent: opponent.name))
        }
      }
    }
    if !tuttocampo.isEmpty {
      for result in await services.fixtureSource.downloadLogos(tuttocampo) {
        if let issue = result.issue { writer.issues.append(issue) }
        if let file = result.fileName { writer.attach(file, to: result.request.opponentID) }
      }
    }
    if !csi.isEmpty {
      let reader = csiLogoReader
      let answers: [Data??] =
        if let reader {
          await CSIConcurrentMap.run(csi, limit: Self.csiLogoConcurrency) { await reader($0) }
        } else {
          []
        }
      let items = csi.enumerated().map { index, request in
        CSILogoData(request: request, data: index < answers.count ? (answers[index] ?? nil) : nil)
      }
      for result in await storeCSILogos(items, in: services.logos) {
        if let issue = result.issue { writer.issues.append(issue) }
        if let file = result.fileName { writer.attach(file, to: result.request.opponentID) }
      }
    }
  }
}

/// Gives each downloaded file to its opponent, unless the opponent got a logo meanwhile.
@MainActor
private struct LogoWriter {
  let services: AppServices
  var stored = 0
  var issues: [ImportIssue] = []

  init(services: AppServices) { self.services = services }

  mutating func attach(_ file: String, to opponentID: EntityID) {
    guard let current = try? services.opponents.get(id: opponentID) else {
      removeIfUnused(file)
      return
    }
    guard current.logoFile == nil else {
      removeIfUnused(file)
      return
    }
    var draft = OpponentDraft(current)
    draft.logoFile = file
    do {
      _ = try services.opponents.update(id: opponentID, with: draft)
      stored += 1
    } catch {
      issues.append(.logoFailed(opponent: current.name))
      removeIfUnused(file)
    }
  }

  /// Removes a downloaded file no opponent uses.
  private func removeIfUnused(_ file: String) {
    guard let all = try? services.opponents.list(), !all.contains(where: { $0.logoFile == file }) else { return }
    try? services.logos.remove(fileName: file)
  }
}
