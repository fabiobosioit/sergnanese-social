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

/// What a Tuttocampo run reads (T4.11): the weekend's matchday (today's flow) or a season run.
enum ImportScope: String, CaseIterable, Identifiable {
  case weekend
  case fromCurrentMatchday
  case wholeSeason

  var id: String { rawValue }

  /// `nil` for "Questo weekend", which stays `fetchFixtures`.
  var seasonScope: SeasonScope? {
    switch self {
    case .weekend: nil
    case .fromCurrentMatchday: .fromCurrentMatchday
    case .wholeSeason: .wholeSeason
    }
  }
}

/// State and logic of the "Importa da Tuttocampo" sheet: fetch every active team that has a widget id,
/// stage the rows for review, write the ticked ones, then download the missing logos.
/// Nothing runs until the user starts it, and nothing runs in the background.
@MainActor @Observable
final class ImportModel {
  enum Phase: Equatable {
    case idle
    /// Tuttocampo start panel: scope and teams, before any request.
    case choosing
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
    /// A federation calendar already read from `fileName`, staged for `team`.
    case pdf(team: Team, calendar: PDFCalendar, fileName: String)
    /// A PDF that gave no calendar: the sheet shows only the report line.
    case pdfFailed(fileName: String, reason: PDFCalendarError)
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

  // Season run (T4.11)
  /// What the next run reads. Chosen in the start panel.
  var scope: ImportScope = .weekend
  /// Active teams with a widget id, as the start panel lists them.
  private(set) var startableTeams: [Team] = []
  /// Teams ticked in the start panel. Empty outside the panel: a run then reads every startable team.
  var chosenTeamIDs: Set<String> = []
  /// Progress of the team being read in a season run.
  private(set) var seasonProgress: SeasonProgress?
  /// Pages requested so far over the whole run.
  private(set) var runPagesRead = 0
  /// Report lines of the UI itself (the per-run cap).
  private(set) var notes: [String] = []
  /// Byes and unread matchdays over the run, for the header line.
  private(set) var seasonByes = 0
  private(set) var seasonUnread = 0
  /// Last season length of each team, kept for the estimate (in memory and in UserDefaults, never in the database).
  private(set) var seasonLengths: [String: SeasonLength] = [:]
  /// Review: only this team's rows; `nil` = all teams.
  var teamFilter: String?
  /// Past weekends the user opened (the others are collapsed when the scope reads the past).
  private(set) var expandedWeekends: Set<String> = []

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
  @ObservationIgnored private var currentTeamTask: Task<SeasonFetch, any Error>?
  @ObservationIgnored private var capReached = false
  @ObservationIgnored private var pagesBeforeTeam = 0
  @ObservationIgnored private let maxPagesPerRun: Int
  @ObservationIgnored private let defaults: UserDefaults

  static let seasonLengthsKey = "import.tuttocampo.seasonLengths"

  /// `maxPagesPerRun` and `defaults` are seams for tests.
  init(
    services: AppServices, source: Source = .tuttocampo,
    today: @escaping @MainActor () -> DayDate = { DayDate.today() },
    maxPagesPerRun: Int = SeasonLimits.maxPagesPerRun, defaults: UserDefaults = .standard
  ) {
    self.services = services
    self.source = source
    self.today = today
    self.maxPagesPerRun = maxPagesPerRun
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.seasonLengthsKey),
      let stored = try? JSONDecoder().decode([String: SeasonLength].self, from: data)
    {
      seasonLengths = stored
    }
  }

  var isCSI: Bool {
    if case .csi = source { return true }
    return false
  }

  var isPDF: Bool {
    switch source {
    case .pdf, .pdfFailed: return true
    default: return false
    }
  }

  var title: String {
    if isPDF { return ImportStrings.titlePDF }
    return isCSI ? ImportStrings.titleCSI : ImportStrings.title
  }

  var emptyDescription: String {
    if isPDF { return ImportStrings.emptyDescriptionPDF(clubShortName: settings?.clubShortName ?? "") }
    return isCSI ? ImportStrings.emptyDescriptionCSI : ImportStrings.emptyDescription
  }

  /// The "no matches" placeholder is hidden when the PDF could not be read at all (the report says why).
  var showsEmptyState: Bool {
    if case .pdfFailed = source { return false }
    return true
  }

  var linkMessage: String {
    if isPDF { return ImportStrings.linkMessagePDF }
    return isCSI ? ImportStrings.linkMessageCSI : ImportStrings.linkMessage
  }

  /// What the written matches are marked with.
  private var matchSource: MatchSource { isPDF ? .pdf : .scrape }

  // MARK: Availability

  /// The reason the command is disabled, for the help text; `nil` when it can start.
  var unavailableReason: String? { canStart ? nil : ImportStrings.noWidgetReason }

  /// Re-reads the teams: the command is enabled only when an active team has a widget id.
  func refreshAvailability() {
    let teams = (try? services.teams.list()) ?? []
    canStart = teams.contains { $0.isActive && $0.tuttocampoWidgetID != nil }
  }

  // MARK: Fetch

  /// Opens the sheet on the start panel (Tuttocampo). Nothing is requested until "Avvia".
  func present() {
    refreshAvailability()
    guard canStart, !isPresented else { return }
    startableTeams = ((try? services.teams.list()) ?? [])
      .filter { $0.isActive && $0.tuttocampoWidgetID != nil }
      .sorted { $0.sortOrder < $1.sortOrder }
    chosenTeamIDs = Set(startableTeams.map(\.id))
    scope = .weekend
    teamFilter = nil
    isPresented = true
    phase = .choosing
  }

  /// "Avvia" in the start panel.
  func startRun() {
    guard phase == .choosing, !chosenTeamIDs.isEmpty else { return }
    phase = .fetching
    start()
  }

  var canStartRun: Bool { phase == .choosing && !chosenTeamIDs.isEmpty }

  func setTeamChosen(_ team: Team, _ isOn: Bool) {
    if isOn { chosenTeamIDs.insert(team.id) } else { chosenTeamIDs.remove(team.id) }
  }

  /// The estimate line of the start panel; `nil` for "Questo weekend".
  var estimate: SeasonEstimate? {
    guard let seasonScope = scope.seasonScope else { return nil }
    let lengths = startableTeams.filter { chosenTeamIDs.contains($0.id) }.map { seasonLengths[$0.id] }
    return SeasonEstimate(scope: seasonScope, teams: lengths)
  }

  func start() {
    task?.cancel()
    if isPDF {
      stagePDF()  // already parsed: nothing to wait for
      return
    }
    task = Task { await isCSI ? readCSIPage() : fetch() }
  }

  // MARK: PDF

  /// Opens the sheet on a PDF source (already parsed by `PDFImportLauncher`) and stages it.
  func presentPDF() {
    guard isPDF, !isPresented else { return }
    isPresented = true
    start()
  }

  /// Stages the calendar's fixtures, or just the report when the PDF could not be read. Synchronous: the
  /// parsing happened before.
  func stagePDF() {
    resetStaging()
    switch source {
    case .pdfFailed(let fileName, let reason):
      issues = [.pdfReadFailed(file: fileName, reason: reason)]
      phase = .review
    case .pdf(let team, let calendar, _):
      do {
        let settings = try services.settings.load()
        self.settings = settings
        opponents = try services.opponents.list()
        issues = ImportIssue.pdfNotices(for: calendar)
        candidates = try candidates(for: calendar.fixtures, team: team, homeVenue: settings.homeVenue)
          .sorted(by: Self.stagingOrder)
        ticked = Set(candidates.filter(isTickedByDefault).map(\.id))
        phase = .review
      } catch {
        phase = .failed((error as? AppError)?.localizedDescription ?? ImportStrings.loadErrorTitle)
      }
    default:
      break
    }
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
    seasonProgress = nil
    runPagesRead = 0
    notes = []
    seasonByes = 0
    seasonUnread = 0
    teamFilter = nil
    expandedWeekends = []
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
    seasonProgress = nil
    runPagesRead = 0
    notes = []
    seasonByes = 0
    seasonUnread = 0
    teamFilter = nil
    expandedWeekends = []
    startableTeams = []
    chosenTeamIDs = []
    scope = .weekend
  }

  /// The teams of the run (active, with a widget id, ticked in the panel), the settings and the opponents; `nil`
  /// (and the failed phase) when they cannot be loaded.
  private func prepareRun() -> (teams: [Team], settings: ClubSettings)? {
    do {
      let teams = try services.teams.list()
        .filter { $0.isActive && $0.tuttocampoWidgetID != nil }
        .filter { chosenTeamIDs.isEmpty || chosenTeamIDs.contains($0.id) }
        .sorted { $0.sortOrder < $1.sortOrder }
      let settings = try services.settings.load()
      opponents = try services.opponents.list()
      self.settings = settings
      return (teams, settings)
    } catch {
      phase = .failed((error as? AppError)?.localizedDescription ?? ImportStrings.loadErrorTitle)
      return nil
    }
  }

  /// Reads the teams one at a time. Awaitable, so tests can run it to the end. A season scope runs the season loop.
  func fetch() async {
    if scope.seasonScope != nil { return await fetchSeason() }
    resetStaging()
    phase = .fetching
    guard let (teams, settings) = prepareRun() else { return }

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

  // MARK: Season run (T4.11)

  /// One team at a time, `fetchSeason` in a child task per team. Annulla cancels the team being read and starts no
  /// other; the per-run page cap does the same and says which teams were not read. Every row already read stays.
  func fetchSeason() async {
    guard let seasonScope = scope.seasonScope else { return await fetch() }
    resetStaging()
    phase = .fetching
    guard let (teams, settings) = prepareRun() else { return }

    var staged: [ImportCandidate] = []
    var cutTeams: [String] = []
    capReached = false
    pagesBeforeTeam = 0
    let fixtureSource = services.fixtureSource
    for (index, team) in teams.enumerated() {
      if Task.isCancelled {
        wasCancelled = true
        break
      }
      if capReached {
        cutTeams += teams[index...].map(\.name)
        break
      }
      progress = Progress(team: team.name, current: index + 1, total: teams.count)
      seasonProgress = nil
      let child = Task {
        try await fixtureSource.fetchSeason(
          for: team, settings: settings, scope: seasonScope,
          onProgress: { [weak self] progress in await self?.seasonPageRead(progress) })
      }
      currentTeamTask = child
      let outcome = await withTaskCancellationHandler {
        await child.result
      } onCancel: {
        child.cancel()
      }
      currentTeamTask = nil

      switch outcome {
      case .success(let fetch):
        pagesBeforeTeam += fetch.pagesRead
        remember(fetch.length, for: team)
        var notices = ImportIssue.seasonNotices(team: team.name, fetch: fetch, clubShortName: settings.clubShortName)
        if Task.isCancelled || capReached {
          notices.removeAll { if case .seasonStopped = $0 { true } else { false } }
        }
        issues += notices
        seasonByes += fetch.byes.count
        seasonUnread += fetch.failedMatchdays.count + fetch.problems.filter { $0.matchday != nil }.count
        if capReached, fetch.stoppedAfter != nil { cutTeams.append(team.name) }
        do {
          staged += try candidates(for: fetch.fixtures, team: team, homeVenue: settings.homeVenue)
        } catch {
          phase = .failed((error as? AppError)?.localizedDescription ?? ImportStrings.loadErrorTitle)
          return
        }
        if Task.isCancelled { wasCancelled = true }
      case .failure(let error):
        if error is CancellationError {
          wasCancelled = true
        } else if let error = error as? FixtureFetchError {
          issues.append(.fetchFailed(team: team.name, reason: error))
        } else {
          phase = .failed((error as? AppError)?.localizedDescription ?? ImportStrings.loadErrorTitle)
          return
        }
      }
      if wasCancelled { break }
    }
    if capReached, !cutTeams.isEmpty {
      notes.append(ImportStrings.capReached(maxPagesPerRun, teams: cutTeams))
    }
    candidates = staged.sorted(by: Self.stagingOrder)
    ticked = Set(candidates.filter(isTickedByDefault).map(\.id))
    progress = nil
    seasonProgress = nil
    phase = .review
  }

  /// The progress callback of `fetchSeason`, already on the main actor. Counts pages over the run and cancels the
  /// team being read when the cap is reached.
  private func seasonPageRead(_ page: SeasonProgress) {
    seasonProgress = page
    runPagesRead = pagesBeforeTeam + page.pagesRead
    if runPagesRead >= maxPagesPerRun, !capReached {
      capReached = true
      currentTeamTask?.cancel()
    }
  }

  private func remember(_ length: SeasonLength?, for team: Team) {
    guard let length else { return }
    seasonLengths[team.id] = length
    if let data = try? JSONEncoder().encode(seasonLengths) { defaults.set(data, forKey: Self.seasonLengthsKey) }
  }

  // MARK: Season review

  var isSeasonRun: Bool { !isCSI && !isPDF && scope != .weekend }

  /// Teams that have rows, for the filter pop-up.
  var filterTeams: [Team] {
    var seen: Set<String> = []
    return candidates.map(\.team).filter { seen.insert($0.id).inserted }.sorted { $0.sortOrder < $1.sortOrder }
  }

  /// "8 partite in 8 giornate, 1 squadra; 1 riposo; 1 giornata non letta" for a season review.
  var seasonSummaryText: String? {
    guard isSeasonRun, phase == .review else { return nil }
    let matchdays = Set(
      candidates.map { "\($0.team.id)|\($0.fixture.round.map(String.init) ?? $0.fixture.date.value)" })
    return ImportStrings.seasonSummary(
      matches: candidates.count, matchdays: matchdays.count, teams: Set(candidates.map(\.team.id)).count,
      byes: seasonByes, unread: seasonUnread)
  }

  /// A past weekend, in a scope that reads the past: collapsed until the user opens it.
  func isCollapsed(_ section: ImportSection) -> Bool {
    scope == .wholeSeason && section.weekend.saturday < nextWeekend(from: today()).saturday
      && !expandedWeekends.contains(section.id)
  }

  func isCollapsible(_ section: ImportSection) -> Bool {
    scope == .wholeSeason && section.weekend.saturday < nextWeekend(from: today()).saturday
  }

  func toggleCollapsed(_ section: ImportSection) {
    if expandedWeekends.contains(section.id) {
      expandedWeekends.remove(section.id)
    } else {
      expandedWeekends.insert(section.id)
    }
  }

  /// The rows on screen: the team filter applied, collapsed weekends left out.
  var visibleCandidates: [ImportCandidate] {
    sections.filter { !isCollapsed($0) }.flatMap(\.candidates)
  }

  /// "Seleziona tutte" / "Seleziona nessuna": the tickable visible rows.
  func setAllVisibleTicked(_ isOn: Bool) {
    for candidate in visibleCandidates where Self.isTickable(candidate) {
      if isOn { ticked.insert(candidate.id) } else { ticked.remove(candidate.id) }
    }
  }

  private func candidates(for fixtures: [FetchedFixture], team: Team, homeVenue: String) throws -> [ImportCandidate] {
    guard let first = fixtures.map(\.date).min(), let last = fixtures.map(\.date).max() else { return [] }
    let existing = try services.matches.list(from: first, to: last, teamID: team.id)
    return fixtures.map {
      ImportCandidate.make(
        fixture: $0, team: team, opponents: opponents, existingMatches: existing, homeVenue: homeVenue,
        source: matchSource)
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

  /// New and changed rows of the coming weekend are ticked at the start; everything else is not. A PDF
  /// holds the whole season: every new or changed row from today on is ticked.
  private func isTickedByDefault(_ candidate: ImportCandidate) -> Bool {
    if isPDF { return Self.isTickable(candidate) && candidate.fixture.date >= today() }
    if let seasonScope = scope.seasonScope {
      // Decision 7: from today on; the whole season also takes the past rows.
      return Self.isTickable(candidate) && (seasonScope == .wholeSeason || candidate.fixture.date >= today())
    }
    return Self.isTickable(candidate) && weekend(containing: candidate.fixture.date) == nextWeekend(from: today())
  }

  var sections: [ImportSection] {
    let year = today().year
    var result: [ImportSection] = []
    for candidate in candidates where teamFilter == nil || candidate.team.id == teamFilter {
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
      let created = try services.opponents.create(candidate.fixture.newOpponentDraft)
      rebuild(candidate, linkedTo: created.id)
      onDataChanged()
    } catch {
      present(error, fallback: ImportStrings.saveFailed)
    }
  }

  /// "Collega a esistente…": saves the fetched name as an alias of `opponent` and resolves the row.
  func link(_ candidate: ImportCandidate, to opponent: Opponent) {
    do {
      let draft = opponent.draftAddingImportNames(of: candidate.fixture)
      var linked = opponent
      if draft != OpponentDraft(opponent) { linked = try services.opponents.update(id: opponent.id, with: draft) }
      rebuild(candidate, linkedTo: linked.id)
      onDataChanged()
    } catch {
      present(error, fallback: ImportStrings.saveFailed)
    }
  }

  /// Opponents the link picker offers: matching `query`, or all of them.
  func linkChoices(matching query: String) -> [Opponent] {
    (try? services.opponents.search(query)) ?? []
  }

  /// What the opponent picker lists. With an empty search: "Proposti" (the candidate's proposals, best first)
  /// then "Tutti gli avversari" (every other stored opponent, alphabetical). With a search: one flat list of
  /// the opponents that match it (`proposed` empty).
  struct PickerContent: Equatable {
    var proposed: [Opponent]
    var others: [Opponent]
    var isEmpty: Bool { proposed.isEmpty && others.isEmpty }
  }

  func pickerContent(for candidate: ImportCandidate, matching query: String) -> PickerContent {
    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
      return PickerContent(proposed: [], others: linkChoices(matching: query))
    }
    let all = (try? services.opponents.list()) ?? opponents
    var seen: Set<EntityID> = []
    let proposed = candidate.proposals.map(\.opponent.id).compactMap { id in
      seen.insert(id).inserted ? all.first { $0.id == id } : nil
    }
    let others = all.filter { !seen.contains($0.id) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    return PickerContent(proposed: proposed, others: others)
  }

  /// A choice in the picker. A row without an opponent is linked at once (the name is saved as an alias, as
  /// "Collega a esistente…" always did); a row that has one is only rebuilt, and its names are saved on "Importa".
  func choose(_ opponent: Opponent, for candidate: ImportCandidate) {
    if candidate.opponent == nil {
      link(candidate, to: opponent)
    } else {
      rebuild(candidate, linkedTo: opponent.id, keepingTick: true)
    }
  }

  /// "Conferma": the proposed opponent becomes a user's link; the draft and the tick stay as they are. No write.
  func confirm(_ candidate: ImportCandidate) {
    guard candidate.opponentMatch == .proposed, let opponent = candidate.opponent else { return }
    rebuild(candidate, linkedTo: opponent.id, keepingTick: true)
  }

  /// "Crea nuovo «…»" in the picker is for rows without an opponent: creating writes at once, and nothing may be
  /// written before "Importa" for a row that already has one.
  func canCreateOpponent(_ candidate: ImportCandidate) -> Bool { candidate.opponent == nil }

  /// "Cambia avversario…" is offered on every row that has an opponent, except a locked match (never written).
  func canChangeOpponent(_ candidate: ImportCandidate) -> Bool {
    candidate.opponent != nil && candidate.state != .locked
  }

  /// Rows that are not locked, by how their opponent was found.
  struct MatchCounts: Equatable {
    /// `.exact` and `.linked`.
    var matched = 0
    var proposed = 0
    /// `.notFound` and `.ambiguous`.
    var toLink = 0
  }

  var matchCounts: MatchCounts {
    var counts = MatchCounts()
    for candidate in candidates where candidate.state != .locked {
      switch candidate.opponentMatch {
      case .exact, .linked: counts.matched += 1
      case .proposed: counts.proposed += 1
      case .notFound, .ambiguous: counts.toLink += 1
      }
    }
    return counts
  }

  var matchCountsText: String? {
    let counts = matchCounts
    guard counts.matched + counts.proposed + counts.toLink > 0 else { return nil }
    return ImportStrings.matchCounts(matched: counts.matched, proposed: counts.proposed, toLink: counts.toLink)
  }

  /// Rebuilds the candidate after the opponent was created or linked, and shows its new state. A row
  /// that is now new or changed is ticked.
  private func rebuild(_ candidate: ImportCandidate, linkedTo opponentID: EntityID, keepingTick: Bool = false) {
    guard let settings, let index = candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
    let wasTickable = Self.isTickable(candidates[index])
    let wasTicked = ticked.contains(candidate.id)
    opponents = (try? services.opponents.list()) ?? opponents
    let rebuilt = ImportCandidate.make(
      fixture: candidate.fixture, team: candidate.team, opponents: opponents,
      existingMatches: candidate.existing.map { [$0] } ?? [], homeVenue: settings.homeVenue,
      linkedOpponentID: opponentID, source: matchSource)
    candidates[index] = rebuilt
    if !Self.isTickable(rebuilt) {
      ticked.remove(rebuilt.id)
    } else if !(keepingTick && wasTickable && !wasTicked) {
      ticked.insert(rebuilt.id)
    }
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
      ImportStrings.changeCompetition, match.competition ?? ImportStrings.none,
      draft.competition ?? ImportStrings.none)
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
      try saveImportNames(of: chosen)
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

  /// T4.10: the fixture's names become aliases of the opponent of every ticked row that came from an exact match,
  /// a proposal or a link, so the next import of the same source is exact. Read fresh from the repository, so two
  /// rows of one opponent add up. An opponent is never renamed; nothing is written when the draft is unchanged.
  private func saveImportNames(of chosen: [ImportCandidate]) throws {
    var changed = false
    for candidate in chosen {
      guard let opponent = candidate.opponent, [.exact, .proposed, .linked].contains(candidate.opponentMatch) else {
        continue
      }
      let current = try services.opponents.get(id: opponent.id)
      let draft = current.draftAddingImportNames(of: candidate.fixture)
      if draft != OpponentDraft(current) {
        _ = try services.opponents.update(id: current.id, with: draft)
        changed = true
      }
    }
    if changed { opponents = (try? services.opponents.list()) ?? opponents }
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
    if isPDF { return }  // a PDF carries no logos
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
