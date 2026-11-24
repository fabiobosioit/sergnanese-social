import Foundation
import Observation
import OSLog
import SSCore

/// One weekend of the staging list.
struct ImportSection: Identifiable, Equatable {
  var weekend: Weekend
  var title: String
  var candidates: [ImportCandidate]
  var id: String { weekend.saturday.value }
}

/// State and logic of the "Importa da Tuttocampo" sheet: fetch every active team that has a widget id,
/// stage the rows for review, write the ticked ones, then download the missing logos.
/// Nothing runs until the user starts it, and nothing runs in the background.
@MainActor @Observable
final class ImportModel {
  enum Phase: Equatable {
    case idle
    case fetching
    case review
    case committing
    case done
    case failed(String)
  }

  /// "Lettura di Juniores… 3 di 9".
  struct Progress: Equatable {
    var team: String
    var current: Int
    var total: Int
  }

  /// Where the rows come from: the Tuttocampo widgets (fetched), or the CSI Live page open in a browser window.
  enum Source {
    case tuttocampo
    case csi(team: Team, page: any CSIPageProvider)
  }

  let services: AppServices
  let source: Source
  /// Set while the "this is not the team's page, import anyway?" question is shown (CSI).
  var confirmsOtherPage = false
  /// Called after matches or opponents changed, so the other screens reload.
  var onDataChanged: @MainActor () -> Void = {}

  private(set) var phase: Phase = .idle
  private(set) var progress: Progress?
  private(set) var wasCancelled = false
  private(set) var issues: [ImportIssue] = []
  private(set) var candidates: [ImportCandidate] = []
  private(set) var summary: ImportSummary?
  private(set) var opponents: [Opponent] = []
  private(set) var canStart = false

  var isPresented = false
  /// Candidate ids that will be imported.
  var ticked: Set<String> = []
  /// Opponent ids whose existing logo is downloaded again.
  var replaceLogo: Set<EntityID> = []
  /// What the user typed as the venue of a candidate (candidate id → venue).
  var venueEdits: [String: String] = [:]
  /// Shown in a standard alert: failed saves.
  var errorMessage: String?

  @ObservationIgnored private let today: @MainActor () -> DayDate
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var settings: ClubSettings?

  init(
    services: AppServices, source: Source = .tuttocampo, today: @escaping @MainActor () -> DayDate = { DayDate.today() }
  ) {
    self.services = services
    self.source = source
    self.today = today
  }

  var isCSI: Bool {
    if case .csi = source { return true }
    return false
  }

  var title: String { isCSI ? ImportStrings.titleCSI : ImportStrings.title }
  var emptyDescription: String { isCSI ? ImportStrings.emptyDescriptionCSI : ImportStrings.emptyDescription }
  var linkMessage: String { isCSI ? ImportStrings.linkMessageCSI : ImportStrings.linkMessage }

  // MARK: Availability

  /// The reason the command is disabled, for the help text; `nil` when it can start.
  var unavailableReason: String? { canStart ? nil : ImportStrings.noWidgetReason }

  /// Re-reads the teams: the command is enabled only when an active team has a widget id.
  func refreshAvailability() {
    let teams = (try? services.teams.list()) ?? []
    canStart = teams.contains { $0.isActive && $0.tuttocampoWidgetID != nil }
  }

  // MARK: Fetch

  /// Opens the sheet and starts reading.
  func present() {
    refreshAvailability()
    guard canStart, !isPresented else { return }
    isPresented = true
    start()
  }

  func start() {
    task?.cancel()
    task = Task { await isCSI ? readCSIPage() : fetch() }
  }

  // MARK: CSI

  /// "Importa questa pagina": asks first when the open page is not the team's saved one.
  func beginCSIImport() {
    guard case .csi(_, let page) = source, !isPresented else { return }
    if page.isOnTeamPage { startCSI() } else { confirmsOtherPage = true }
  }

  /// "Importa" in the confirmation.
  func confirmOtherPage() {
    confirmsOtherPage = false
    startCSI()
  }

  private func startCSI() {
    isPresented = true
    start()
  }

  /// Reads the page on screen, parses it off the main actor and stages the rows. Awaitable, so tests can run
  /// it to the end. A page that gave no rows leaves only the report.
  func readCSIPage() async {
    guard case .csi(let team, let page) = source else { return }
    resetStaging()
    phase = .fetching
    let settings: ClubSettings
    do {
      settings = try services.settings.load()
      opponents = try services.opponents.list()
    } catch {
      phase = .failed((error as? AppError)?.localizedDescription ?? ImportStrings.loadErrorTitle)
      return
    }
    self.settings = settings
    switch await page.readPage() {
    case .failure(let reason):
      issues = [.csiPageReadFailed(team: team.name, reason: reason)]
    case .success(let snapshot):
      let parser = services.csiPageParser
      let outcome = await Task.detached {
        parser.parse(html: snapshot.html, pageURL: snapshot.pageURL, settings: settings)
      }
      .value
      if let issue = ImportIssue.csiPage(team: team.name, outcome: outcome, clubShortName: settings.clubShortName) {
        issues = [issue]
      } else if case .fixtures(let fixtures) = outcome {
        await storeTeamList(snapshot: snapshot, team: team, settings: settings)
        do {
          candidates = try candidates(for: fixtures, team: team, homeVenue: settings.homeVenue)
            .sorted(by: Self.stagingOrder)
          ticked = Set(candidates.filter(isTickedByDefault).map(\.id))
        } catch {
          phase = .failed((error as? AppError)?.localizedDescription ?? ImportStrings.loadErrorTitle)
          return
        }
      }
    }
    phase = .review
  }

  /// T4.9: keeps the list of every team on the page just read, for "Scarica tutti gli avversari…". Parsed off
  /// the main actor from the same HTML; an empty list stores nothing. A failure is logged (team name only) and
  /// never changes the match import.
  private func storeTeamList(snapshot: CSIPageSnapshot, team: Team, settings: ClubSettings) async {
    let parser = services.csiPageParser
    let found = await Task.detached {
      parser.teams(html: snapshot.html, pageURL: snapshot.pageURL, for: team, settings: settings)
    }
    .value
    guard !found.isEmpty else { return }
    do {
      try services.sourceTeamLists.save(teamID: team.id, source: .csi, teams: found, readAt: Date())
    } catch {
      Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.sergnanese.social", category: "import")
        .error("CSI team list not stored for \(team.name, privacy: .public)")
    }
  }

  private func resetStaging() {
    progress = nil
    wasCancelled = false
    issues = []
    candidates = []
    ticked = []
    replaceLogo = []
    venueEdits = [:]
    summary = nil
  }

  /// Cancels the fetch; the teams already read stay.
  func cancelFetch() { task?.cancel() }

  /// Closes the sheet and forgets everything. A running fetch is cancelled.
  func dismiss() {
    task?.cancel()
    task = nil
    isPresented = false
    phase = .idle
    progress = nil
    issues = []
    candidates = []
    ticked = []
    replaceLogo = []
    venueEdits = [:]
    summary = nil
    wasCancelled = false
  }

  /// Reads the teams one at a time. Awaitable, so tests can run it to the end.
  func fetch() async {
    resetStaging()
    phase = .fetching

    let teams: [Team]
    let settings: ClubSettings
    do {
      teams = try services.teams.list()
        .filter { $0.isActive && $0.tuttocampoWidgetID != nil }
        .sorted { $0.sortOrder < $1.sortOrder }
      settings = try services.settings.load()
      opponents = try services.opponents.list()
    } catch {
      phase = .failed((error as? AppError)?.localizedDescription ?? ImportStrings.loadErrorTitle)
      return
    }
    self.settings = settings

    var staged: [ImportCandidate] = []
    for (index, team) in teams.enumerated() {
      if Task.isCancelled {
        wasCancelled = true
        break
      }
      progress = Progress(team: team.name, current: index + 1, total: teams.count)
      do {
        let result = try await services.fixtureSource.fetchFixtures(for: team, settings: settings)
        switch result {
        case .fixtures(let fixtures):
          staged += try candidates(for: fixtures, team: team, homeVenue: settings.homeVenue)
        case .notYetAvailable:
          issues.append(.notYetAvailable(team: team.name))
        case .sourceProblem(let problem):
          issues.append(.sourceProblem(team: team.name, problem: problem, clubShortName: settings.clubShortName))
        }
      } catch is CancellationError {
        wasCancelled = true
        break
      } catch let error as FixtureFetchError {
        issues.append(.fetchFailed(team: team.name, reason: error))
      } catch {
        phase = .failed((error as? AppError)?.localizedDescription ?? ImportStrings.loadErrorTitle)
        return
      }
    }
    candidates = staged.sorted(by: Self.stagingOrder)
    ticked = Set(candidates.filter(isTickedByDefault).map(\.id))
    progress = nil
    phase = .review
  }

  private func candidates(for fixtures: [FetchedFixture], team: Team, homeVenue: String) throws -> [ImportCandidate] {
    guard let first = fixtures.map(\.date).min(), let last = fixtures.map(\.date).max() else { return [] }
    let existing = try services.matches.list(from: first, to: last, teamID: team.id)
    return fixtures.map {
      ImportCandidate.make(
        fixture: $0, team: team, opponents: opponents, existingMatches: existing, homeVenue: homeVenue)
    }
  }

  /// Like `MatchDetail.scheduleOrder`: date, time (untimed last), the team's order, then the id.
  static func stagingOrder(_ lhs: ImportCandidate, _ rhs: ImportCandidate) -> Bool {
    if lhs.fixture.date != rhs.fixture.date { return lhs.fixture.date < rhs.fixture.date }
    switch (lhs.fixture.time, rhs.fixture.time) {
    case (let left?, let right?) where left != right: return left < right
    case (.some, .none): return true
    case (.none, .some): return false
    default: break
    }
    if lhs.team.sortOrder != rhs.team.sortOrder { return lhs.team.sortOrder < rhs.team.sortOrder }
    return lhs.id < rhs.id
  }

  // MARK: Staging

  static func isTickable(_ candidate: ImportCandidate) -> Bool {
    (candidate.state == .new || candidate.state == .changed) && candidate.draft != nil
  }

  /// New and changed rows of the coming weekend are ticked at the start; everything else is not.
  private func isTickedByDefault(_ candidate: ImportCandidate) -> Bool {
    Self.isTickable(candidate) && weekend(containing: candidate.fixture.date) == nextWeekend(from: today())
  }

  var sections: [ImportSection] {
    let year = today().year
    var result: [ImportSection] = []
    for candidate in candidates {
      let weekend = weekend(containing: candidate.fixture.date)
      if let index = result.firstIndex(where: { $0.weekend == weekend }) {
        result[index].candidates.append(candidate)
      } else {
        result.append(
          ImportSection(
            weekend: weekend, title: formatWeekend(weekend, currentYear: year), candidates: [candidate]))
      }
    }
    return result
  }

  func isTicked(_ candidate: ImportCandidate) -> Bool { ticked.contains(candidate.id) }

  func setTicked(_ candidate: ImportCandidate, _ isOn: Bool) {
    guard Self.isTickable(candidate) else { return }
    if isOn { ticked.insert(candidate.id) } else { ticked.remove(candidate.id) }
  }

  var tickedCandidates: [ImportCandidate] {
    candidates.filter { ticked.contains($0.id) && Self.isTickable($0) }
  }

  var canImport: Bool { phase == .review && !tickedCandidates.isEmpty }

  var selectionText: String { ImportStrings.selected(tickedCandidates.count, of: candidates.count) }

  /// Candidates the user can still import (new or changed).
  var importableCount: Int { candidates.filter(Self.isTickable).count }

  func venue(for candidate: ImportCandidate) -> String { venueEdits[candidate.id] ?? candidate.draft?.venue ?? "" }

  func setVenue(_ venue: String, for candidate: ImportCandidate) { venueEdits[candidate.id] = venue }

  func setReplaceLogo(_ opponent: Opponent, _ isOn: Bool) {
    if isOn { replaceLogo.insert(opponent.id) } else { replaceLogo.remove(opponent.id) }
  }

  // MARK: Opponent resolution

  /// "Crea avversario": a new opponent with the fetched name.
  func createOpponent(for candidate: ImportCandidate) {
    do {
      let created = try services.opponents.create(OpponentDraft(name: candidate.fixture.opponentName))
      rebuild(candidate, linkedTo: created.id)
      onDataChanged()
    } catch {
      present(error, fallback: ImportStrings.saveFailed)
    }
  }

  /// "Collega a esistente…": saves the fetched name as an alias of `opponent` and resolves the row.
  func link(_ candidate: ImportCandidate, to opponent: Opponent) {
    do {
      var draft = OpponentDraft(opponent)
      if opponentsMatching(name: candidate.fixture.opponentName, in: [opponent]).isEmpty {
        draft.aliases.append(candidate.fixture.opponentName)
      }
      let updated = try services.opponents.update(id: opponent.id, with: draft)
      rebuild(candidate, linkedTo: updated.id)
      onDataChanged()
    } catch {
      present(error, fallback: ImportStrings.saveFailed)
    }
  }

  /// Opponents the link picker offers: matching `query`, or all of them.
  func linkChoices(matching query: String) -> [Opponent] {
    (try? services.opponents.search(query)) ?? []
  }

  /// Rebuilds the candidate after the opponent was created or linked, and shows its new state. A row
  /// that is now new or changed is ticked.
  private func rebuild(_ candidate: ImportCandidate, linkedTo opponentID: EntityID) {
    guard let settings, let index = candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
    opponents = (try? services.opponents.list()) ?? opponents
    let rebuilt = ImportCandidate.make(
      fixture: candidate.fixture, team: candidate.team, opponents: opponents,
      existingMatches: candidate.existing.map { [$0] } ?? [], homeVenue: settings.homeVenue,
      linkedOpponentID: opponentID)
    candidates[index] = rebuilt
    if Self.isTickable(rebuilt) { ticked.insert(rebuilt.id) } else { ticked.remove(rebuilt.id) }
  }

  // MARK: Changes of an existing match

  /// What an import changes in the existing match, as "Orario: 10:30 → 11:00".
  func changes(for candidate: ImportCandidate) -> [String] {
    guard candidate.state == .changed, let existing = candidate.existing, let draft = candidate.draft else { return [] }
    let match = existing.match
    var result: [String] = []
    func add(_ label: String, _ old: String, _ new: String) {
      if old != new { result.append(ImportStrings.change(label, from: old, to: new)) }
    }
    add(ImportStrings.changeTime, match.time?.value ?? ImportStrings.none, draft.time?.value ?? ImportStrings.none)
    add(ImportStrings.changeOpponent, existing.opponent.name, candidate.opponent?.name ?? ImportStrings.none)
    add(
      ImportStrings.changeHomeAway, match.isHome ? ImportStrings.home : ImportStrings.away,
      draft.isHome ? ImportStrings.home : ImportStrings.away)
    add(ImportStrings.changeStatus, StatusBadge.title(for: match.status), StatusBadge.title(for: draft.status))
    add(ImportStrings.changeScore, Self.scoreText(match.score), Self.scoreText(draft.score))
    add(
      ImportStrings.changeVenue, match.venue.isEmpty ? ImportStrings.none : match.venue,
      draft.venue.isEmpty ? ImportStrings.none : draft.venue)
    add(
      ImportStrings.changeRound, match.round.map(String.init) ?? ImportStrings.none,
      draft.round.map(String.init) ?? ImportStrings.none)
    return result
  }

  private static func scoreText(_ score: Score?) -> String {
    score.map { "\($0.us)–\($0.them)" } ?? ImportStrings.none
  }

  // MARK: Commit

  /// Writes the ticked rows, then downloads the missing logos. The summary and the report stay on
  /// screen until the user presses "Fine".
  func commit() async {
    guard canImport else { return }
    phase = .committing
    let chosen = tickedCandidates
    let drafts: [MatchDraft] = chosen.compactMap { candidate in
      guard var draft = candidate.draft else { return nil }
      if let venue = venueEdits[candidate.id] { draft.venue = venue }
      return draft.normalized()
    }
    do {
      summary = try services.matches.upsertFromImport(drafts)
    } catch {
      present(error, fallback: ImportStrings.importFailed)
      phase = .review
      return
    }
    onDataChanged()
    await downloadLogos(for: chosen)
    onDataChanged()
    phase = .done
  }

  /// The opponents that need a logo, with the fixture that names them. Opponents of the rows that were
  /// written, and of the rows already in the database (unchanged or locked): all of them are part of the
  /// weekend. Rows the user left unticked are not. An opponent without a logo, or one the user asked to
  /// replace.
  private func logoTargets(for chosen: [ImportCandidate]) -> [(opponent: Opponent, fixture: FetchedFixture)] {
    var targets: [(opponent: Opponent, fixture: FetchedFixture)] = []
    var seen: Set<EntityID> = []
    let inScope = chosen + candidates.filter { $0.state == .unchanged || $0.state == .locked }
    for candidate in inScope {
      guard let opponent = candidate.opponent, seen.insert(opponent.id).inserted else { continue }
      if opponent.logoFile == nil || replaceLogo.contains(opponent.id) {
        targets.append((opponent, candidate.fixture))
      }
    }
    return targets
  }

  /// CSI: the bytes are read in the browser's page session, then stored; a logo the page does not
  /// carry (placeholder shield) or cannot give is reported as information.
  private func downloadCSILogos(for chosen: [ImportCandidate], page: any PageLogoSource) async {
    var requests: [CSILogoRequest] = []
    for target in logoTargets(for: chosen) {
      if let request = CSILogoRequest(opponent: target.opponent, fixture: target.fixture) {
        requests.append(request)
      } else {
        issues.append(.csiLogoUnavailable(opponent: target.opponent.name))
      }
    }
    guard !requests.isEmpty else { return }
    let data = await page.fetchLogos(requests)
    let results = await storeCSILogos(data, in: services.logos)
    for result in results {
      var issue = result.issue
      if let fileName = result.fileName, !store(logo: fileName, for: result.request.opponentID) {
        issue = .logoFailed(opponent: result.request.opponentName)
      }
      if let issue { issues.append(issue) }
    }
  }

  private func downloadLogos(for chosen: [ImportCandidate]) async {
    if case .csi(_, let page) = source {
      await downloadCSILogos(for: chosen, page: page)
      return
    }
    let requests = logoTargets(for: chosen).map { LogoRequest(opponent: $0.opponent, fixture: $0.fixture) }
    guard !requests.isEmpty else { return }
    let results = await services.fixtureSource.downloadLogos(requests)
    for result in results {
      var issue = result.issue
      if let fileName = result.fileName, !store(logo: fileName, for: result.request.opponentID) {
        issue = .logoFailed(opponent: result.request.opponentName)
      }
      if let issue { issues.append(issue) }
    }
  }

  /// Saves the new logo on the opponent and removes the old file when its name differs.
  private func store(logo fileName: String, for opponentID: EntityID) -> Bool {
    do {
      let current = try services.opponents.get(id: opponentID)
      var draft = OpponentDraft(current)
      draft.logoFile = fileName
      _ = try services.opponents.update(id: opponentID, with: draft)
      if let old = current.logoFile, old != fileName { try? services.logos.remove(fileName: old) }
      return true
    } catch {
      return false
    }
  }

  var summaryText: String? {
    summary.map { ImportStrings.summary(inserted: $0.inserted, updated: $0.updated, locked: $0.skippedLocked) }
  }

  private func present(_ error: any Error, fallback: String) {
    errorMessage = (error as? AppError)?.localizedDescription ?? fallback
  }
}
