import Foundation

// Match import from an outside source: T4.2 reads tuttocampo.it widgets; T4.8 reads CSI Live pages the
// user opens (see `CSI.swift`); T4.3 reads federation calendar PDFs (see `PDFCalendar.swift`); T4.1 (CSV) reuses
// the staging types. The tuttocampo flow, driven by the UI:
//
// 1. `FixtureSource.fetchFixtures(for:settings:)` once per active team with a widget id;
// 2. `ImportCandidate.make(…)` for every fetched fixture; the user reviews the candidates (staging);
// 3. the ticked candidates' drafts go to `MatchRepository.upsertFromImport`;
// 4. `FixtureSource.downloadLogos` for the opponents that have no logo (or whose logo the user asked
//    to replace), then `OpponentRepository.update` with each stored file name.
//
// Every problem met on the way is an `ImportIssue` with an Italian message naming the team or the
// opponent. A problem with one team or one logo never stops the others.

// MARK: - Fetched data

/// One of our matches as a source shows it, before it is matched to our teams, opponents and matches.
public struct FetchedFixture: Sendable, Codable, Equatable, Hashable {
  public var date: DayDate
  public var time: ClockTime?
  /// `true` when our side is the home side.
  public var isHome: Bool
  /// The other side's name as the source writes it, trimmed.
  public var opponentName: String
  /// Used **only** to download the opponent's logo (from `tuttocampoClubID(fromLogoURL:)`). Never a
  /// key for opponents: the same real club has a different ClubId in each widget.
  public var opponentClubID: String?
  /// The absolute logo address the source shows, the fallback download. `nil` when there is none.
  public var opponentLogoURL: URL?
  /// From our point of view; present only when `status` is `.played`.
  public var score: Score?
  /// "Giornata N", within `1...FieldLimits.maxRound`; `nil` when absent or out of range.
  public var round: Int?
  /// `nil` when the source's status text is not recognised: the candidate then needs review.
  public var status: MatchStatus?
  /// The status text exactly as the source writes it ("Partita da giocare", "Partita rinviata"),
  /// shown when the status is not recognised.
  public var statusText: String
  /// Where the match is played as the source writes it, trimmed (T4.8, CSI: the row's tooltip, venue name
  /// and address, with the trailing match code removed). `nil` when the source does not say (tuttocampo).
  /// `ImportCandidate.make` uses it for away matches only; at home the club's `homeVenue` is used.
  public var venue: String?
  /// T4.3: other names of the opponent in the same source (the PDF's full club name, `SAN BERNARDO CALCIO`, when
  /// `opponentName` is the short `S. BERNARDO CALCIO`). `ImportCandidate.make` tries them when no opponent
  /// matches `opponentName`; "Crea avversario" (`newOpponentDraft`) and "Collega a esistente…"
  /// (`Opponent.draftAddingImportNames(of:)`) save them as aliases. Empty for tuttocampo and CSI; absent from older
  /// JSON, which decodes as empty.
  public var opponentAliases: [String]
  /// T4.3: the championship as the source writes it (`PDFCalendar.competition`); `nil` when the source does not
  /// say (tuttocampo, CSI). `ImportCandidate.make` puts it in new drafts and in existing matches without one.
  public var competition: String?
  /// T4.3: `true` when the source could not give the day and time of the match (the PDF's home club is missing
  /// from its club table): `date` is only the weekend's Saturday. The candidate needs review
  /// (`ImportCandidate.ReviewReason.scheduleUnknown`) and cannot be imported. `false` for tuttocampo and CSI.
  public var scheduleUnknown: Bool

  public init(
    date: DayDate, time: ClockTime?, isHome: Bool, opponentName: String, opponentClubID: String? = nil,
    opponentLogoURL: URL? = nil, score: Score? = nil, round: Int? = nil, status: MatchStatus?, statusText: String,
    venue: String? = nil, opponentAliases: [String] = [], competition: String? = nil, scheduleUnknown: Bool = false
  ) {
    self.date = date
    self.time = time
    self.isHome = isHome
    self.opponentName = opponentName
    self.opponentClubID = opponentClubID
    self.opponentLogoURL = opponentLogoURL
    self.score = score
    self.round = round
    self.status = status
    self.statusText = statusText
    self.venue = venue
    self.opponentAliases = opponentAliases
    self.competition = competition
    self.scheduleUnknown = scheduleUnknown
  }

  enum CodingKeys: String, CodingKey {
    case date, time, isHome, opponentName, opponentClubID, opponentLogoURL, score, round, status, statusText, venue
    case opponentAliases, competition, scheduleUnknown
  }

  /// Keys added after T4.2 (`venue`, `opponentAliases`, `competition`, `scheduleUnknown`) may be absent.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      date: try container.decode(DayDate.self, forKey: .date),
      time: try container.decodeIfPresent(ClockTime.self, forKey: .time),
      isHome: try container.decode(Bool.self, forKey: .isHome),
      opponentName: try container.decode(String.self, forKey: .opponentName),
      opponentClubID: try container.decodeIfPresent(String.self, forKey: .opponentClubID),
      opponentLogoURL: try container.decodeIfPresent(URL.self, forKey: .opponentLogoURL),
      score: try container.decodeIfPresent(Score.self, forKey: .score),
      round: try container.decodeIfPresent(Int.self, forKey: .round),
      status: try container.decodeIfPresent(MatchStatus.self, forKey: .status),
      statusText: try container.decode(String.self, forKey: .statusText),
      venue: try container.decodeIfPresent(String.self, forKey: .venue),
      opponentAliases: try container.decodeIfPresent([String].self, forKey: .opponentAliases) ?? [],
      competition: try container.decodeIfPresent(String.self, forKey: .competition),
      scheduleUnknown: try container.decodeIfPresent(Bool.self, forKey: .scheduleUnknown) ?? false)
  }

  /// T4.3, "Crea avversario": a new opponent named `opponentName` (whitespace collapsed, cut with `truncateAtWord`
  /// to `FieldLimits.opponentName`), with `opponentAliases` as aliases, each whitespace collapsed, kept only when it
  /// fits `FieldLimits.alias` and matches neither the name nor an earlier alias (`opponentsMatching` rules).
  /// For tuttocampo and CSI fixtures it is `OpponentDraft(name: opponentName)`.
  public var newOpponentDraft: OpponentDraft {
    let name = truncateAtWord(opponentName.collapsedWhitespace, max: FieldLimits.opponentName).text
    return OpponentDraft(name: name, aliases: importAliases(opponentAliases, notMatching: [name]))
  }
}

extension Opponent {
  /// T4.3, "Collega a esistente…": this opponent's draft with `fixture.opponentName`, then each of
  /// `fixture.opponentAliases`, appended to `aliases` when it does not already match the opponent (its name, short
  /// name or an alias, compared as `opponentsMatching` does) nor an earlier addition, and fits `FieldLimits.alias`.
  /// Equal to `OpponentDraft(self)` when there is nothing to add (the caller may then skip the update).
  public func draftAddingImportNames(of fixture: FetchedFixture) -> OpponentDraft {
    var draft = OpponentDraft(self)
    let known = [name] + [shortName].compactMap { $0 } + aliases
    draft.aliases += importAliases([fixture.opponentName] + fixture.opponentAliases, notMatching: known)
    return draft
  }
}

/// `names` whitespace collapsed, without empty ones, those over `FieldLimits.alias`, and those whose
/// `opponentMatchKey` equals one of `known` or of an earlier name.
func importAliases(_ names: [String], notMatching known: [String]) -> [String] {
  var seen = Set(known.map(opponentMatchKey))
  var result: [String] = []
  for name in names.map(\.collapsedWhitespace) where !name.isEmpty && name.count <= FieldLimits.alias {
    let key = opponentMatchKey(name)
    guard !key.isEmpty, seen.insert(key).inserted else { continue }
    result.append(name)
  }
  return result
}

/// Why a page that was read cannot be trusted. Nothing is imported for that team.
public enum FixtureHealthProblem: String, Sendable, Codable, CaseIterable {
  /// The results table is missing, has no match rows, or a row cannot be read (no date): "la
  /// sorgente potrebbe essere cambiata".
  case structureChanged
  /// Match rows were found, but in none of them is a side named like the club
  /// (`ClubSettings.clubShortName`): "nessuna partita della Sergnanese trovata".
  case noFixturesOfOurs
}

/// The outcome of reading one team's source page.
public enum FixtureFetch: Sendable, Equatable, Hashable {
  /// Our matches on the page, in page order; never empty.
  case fixtures([FetchedFixture])
  /// The source says its results are not published yet ("Risultati non ancora disponibili.").
  /// Information, not an error.
  case notYetAvailable
  /// The page was read but is not what the parser expects.
  case sourceProblem(FixtureHealthProblem)
}

/// Why a team's page could not be read at all. Thrown by `FixtureSource.fetchFixtures`.
public enum FixtureFetchError: Error, Sendable, Equatable, Hashable {
  /// The team has no `tuttocampoWidgetID`.
  case missingWidgetID
  /// No connection, DNS or TLS failure.
  case network
  case timeout
  /// Any HTTP status other than 200.
  case httpStatus(Int)
  /// The response is larger than the source's size cap.
  case responseTooLarge
  /// A request or a redirect pointed to an address that is not https or not on the host allowlist.
  case notAllowed
  /// No source is configured in this build (the placeholder `AppServices` uses until the real source
  /// is wired).
  case unavailable
}

// MARK: - Logos

/// A logo to download for one opponent. Build it with `init(opponent:fixture:)`.
public struct LogoRequest: Sendable, Codable, Equatable, Hashable {
  public var opponentID: EntityID
  /// For the report.
  public var opponentName: String
  /// `FetchedFixture.opponentClubID`. `nil` = the address was not recognised: nothing is downloaded
  /// and the result carries `ImportIssue.logoNotRecognised`.
  public var clubID: String?
  /// `FetchedFixture.opponentLogoURL`, tried once when the `Teams/200` copy fails.
  public var fallbackURL: URL?

  public init(opponentID: EntityID, opponentName: String, clubID: String?, fallbackURL: URL?) {
    self.opponentID = opponentID
    self.opponentName = opponentName
    self.clubID = clubID
    self.fallbackURL = fallbackURL
  }

  /// The logo of `opponent` as shown in `fixture`.
  public init(opponent: Opponent, fixture: FetchedFixture) {
    self.init(
      opponentID: opponent.id, opponentName: opponent.name, clubID: fixture.opponentClubID,
      fallbackURL: fixture.opponentLogoURL)
  }
}

/// What happened to one `LogoRequest`.
public struct LogoResult: Sendable, Equatable, Hashable {
  public var request: LogoRequest
  /// The file stored in the logos folder (`"<ClubId>.png"`); `nil` when no logo was stored.
  public var fileName: String?
  /// `nil` when the `Teams/200` copy was stored without problems. `.logoFallback` comes with a
  /// `fileName`; `.logoNotRecognised` and `.logoFailed` without.
  public var issue: ImportIssue?

  public init(request: LogoRequest, fileName: String?, issue: ImportIssue?) {
    self.request = request
    self.fileName = fileName
    self.issue = issue
  }
}

// MARK: - Source

/// Where fixtures come from (T4.2: `TuttocampoWidgetSource` in SSImport; `FakeFixtureSource` in
/// SSCoreFakes). Requests are made only when these methods are called, i.e. when the user presses
/// "Importa da Tuttocampo…": no polling, no background work.
///
/// Rules for a network implementation: https only, every request and redirect checked against a
/// host allowlist, a timeout, a response size cap, no cookies, an app `User-Agent`. Fetched HTML is
/// parsed, never rendered or run.
public protocol FixtureSource: Sendable {
  /// Reads the default matchday of `team`'s widget (one request) and returns our matches on it: the
  /// rows in which one side's name equals `settings.clubShortName` (compared with `searchKey` after
  /// `stripLegalPrefixes`); that side gives `isHome`, the other side is the opponent. Other rows are
  /// ignored. The year of a date without one comes from `settings.season` (August to December = the
  /// first year, January to July = the second).
  ///
  /// Throws `FixtureFetchError` when the page cannot be read (`.missingWidgetID` when the team has no
  /// widget id) and `CancellationError` when the task is cancelled; nothing else.
  func fetchFixtures(for team: Team, settings: ClubSettings) async throws -> FixtureFetch

  /// Downloads and stores logos, one `LogoResult` per request in request order. Requests with the
  /// same `clubID` are downloaded and stored once and share the result's `fileName`. For each
  /// `clubID`: `tuttocampoLogoURL(clubID:)` first; when that fails (HTTP error, not an image, over
  /// the size cap) the request's `fallbackURL` once (`.logoFallback`); when both fail `.logoFailed`.
  /// Logos are stored with `LogoStore.importLogo(data:fileName:replacing:)` under
  /// `tuttocampoLogoFileName(clubID:)`, replacing a file of that name; `replacing` is `nil`: removing
  /// an opponent's previous file is the caller's job, after it has updated the opponent.
  ///
  /// Never throws: every failure is in its result. When the task is cancelled, the requests not yet
  /// done come back with `fileName == nil` and `issue == nil`.
  func downloadLogos(_ requests: [LogoRequest]) async -> [LogoResult]

  /// T4.9: reads `team`'s Classifica widget (one request, `https://www.tuttocampo.it/WidgetV2/Classifica/<id>`
  /// with the team's widget id, under the same rules as `fetchFixtures`) and returns every team of the league
  /// except ours, in table order, each with `source == .tuttocampo` and `teamID == team.id`.
  ///
  /// - Rows: `table.table_ranking tbody tr`. Name: the text of `td.team > a`, trimmed, whitespace collapsed.
  ///   Logo: `td.team_logo > img[src]` made absolute (`logoURL`) and its `tuttocampoClubID(fromLogoURL:)`
  ///   (`logoID`); a row without an image has neither.
  /// - Ours: a row with the class `selected`, or whose name equals `settings.clubShortName` (compared with
  ///   `searchKey` after `stripLegalPrefixes`). A table without our row is not an error: all its rows are returned.
  /// - A name seen twice (same comparison) is returned once, the first time.
  /// - `.structureChanged` when there is no standings table, no row, or a row without a name.
  ///
  /// Throws `FixtureFetchError` when the page cannot be read (`.missingWidgetID` when the team has no widget id)
  /// and `CancellationError` when the task is cancelled; nothing else. The default implementation (used by
  /// `UnavailableFixtureSource` and by sources written before T4.9) throws `FixtureFetchError.unavailable`.
  func fetchLeagueTeams(for team: Team, settings: ClubSettings) async throws -> LeagueTeamsFetch

  /// T4.11: reads every matchday of `scope` from `team`'s Risultati widget, one page at a time through the same
  /// client, rules and spacing as `fetchFixtures`, and returns our matches with the byes, failures and stops. The
  /// order, stop rules and cancellation are those of `readSeason(scope:readPage:onProgress:)`, which implementations
  /// call: the default matchday first (`fetchFixtures`' page: it gives the current matchday and `matchesNumber`, the
  /// number of matchdays), then the others in ascending order, `/WidgetV2/Risultati/<id>/<n>?y=<season>` with the
  /// season from `settings.season` (`2026/27` → `2026-27`). Rows of ours, years and `isHome` as in `fetchFixtures`;
  /// a page with a results table but no row of ours is a bye (the `tr.repose` "Riposa:" row may confirm it, it is
  /// not required). A row without a time is kept with `time == nil`; far-future times may be provisional.
  ///
  /// Throws `FixtureFetchError` only when the default page cannot be read (`.missingWidgetID` when the team has no
  /// widget id). Cancellation stops before the next request and **returns** what was read (`stoppedAfter`); it never
  /// throws `CancellationError`, so callers check `Task.isCancelled`. `.notYetAvailable` on the default page gives
  /// `SeasonFetch.notYetAvailable` and `lastMatchday == nil`. `onProgress` is awaited after every page.
  ///
  /// The default implementation (used by `UnavailableFixtureSource` and by sources written before T4.11) throws
  /// `FixtureFetchError.unavailable`.
  func fetchSeason(
    for team: Team, settings: ClubSettings, scope: SeasonScope, onProgress: @Sendable (SeasonProgress) async -> Void
  ) async throws -> SeasonFetch
}

extension FixtureSource {
  /// Throws `FixtureFetchError.unavailable`: this source cannot read a season.
  public func fetchSeason(
    for team: Team, settings: ClubSettings, scope: SeasonScope, onProgress: @Sendable (SeasonProgress) async -> Void
  ) async throws -> SeasonFetch {
    throw FixtureFetchError.unavailable
  }

  /// Throws `FixtureFetchError.unavailable`: this source cannot read standings.
  public func fetchLeagueTeams(for team: Team, settings: ClubSettings) async throws -> LeagueTeamsFetch {
    throw FixtureFetchError.unavailable
  }
}

/// The source `AppServices` uses when none is given: every fetch throws
/// `FixtureFetchError.unavailable` and every logo fails. Keeps the containers built before T4.2 valid.
@usableFromInline
struct UnavailableFixtureSource: FixtureSource {
  @usableFromInline
  init() {}

  @usableFromInline
  func fetchFixtures(for team: Team, settings: ClubSettings) async throws -> FixtureFetch {
    throw FixtureFetchError.unavailable
  }

  @usableFromInline
  func downloadLogos(_ requests: [LogoRequest]) async -> [LogoResult] {
    requests.map { LogoResult(request: $0, fileName: nil, issue: .logoFailed(opponent: $0.opponentName)) }
  }
}

// MARK: - Report

/// One line of the import report, naming the team or the opponent concerned. `message` is Italian
/// and ready to show; `isError` is `false` for information.
public enum ImportIssue: Sendable, Equatable, Hashable {
  /// The team's page could not be read.
  case fetchFailed(team: String, reason: FixtureFetchError)
  /// The team's page was read but cannot be trusted. `clubShortName` is `ClubSettings.clubShortName`.
  case sourceProblem(team: String, problem: FixtureHealthProblem, clubShortName: String)
  /// The source has not published the team's results yet. Information.
  case notYetAvailable(team: String)
  /// The opponent's logo address did not give a ClubId; no logo was downloaded.
  case logoNotRecognised(opponent: String)
  /// The `Teams/200` copy failed and the small copy shown by the widget was stored. Information.
  case logoFallback(opponent: String)
  /// No logo could be downloaded or stored.
  case logoFailed(opponent: String)
  /// T4.8: the CSI page open for `team` could not be read (too large, still loading, closed).
  case csiPageReadFailed(team: String, reason: CSIPageReadError)
  /// T4.8: the page open for `team` has no recognisable match list: "la pagina aperta non sembra un
  /// girone CSI" (`FixtureHealthProblem.structureChanged` from `PageFixtureParser`).
  case csiNotAGirone(team: String)
  /// T4.8: the page has match rows but none of the club's (`.noFixturesOfOurs`). `clubShortName` is
  /// `ClubSettings.clubShortName`.
  case csiNoFixturesOfOurs(team: String, clubShortName: String)
  /// T4.8: no logo was stored for the opponent: the page shows none (placeholder shield), or it could
  /// not be read or stored. Information: the import goes on and the logo can be added by hand.
  case csiLogoUnavailable(opponent: String)
  /// T4.9: the team's Classifica widget could not be read: "Tuttocampo: impossibile leggere la classifica di …".
  case standingsReadFailed(team: String, reason: FixtureFetchError)
  /// T4.9: the team's Classifica widget was read but cannot be trusted (`LeagueTeamsFetch.structureChanged`).
  case standingsChanged(team: String)
  /// T4.9: the team has a CSI page but no team list is stored yet: "CSI: nessuna lettura per …, usa prima Importa
  /// da CSI…". Information.
  case csiTeamListMissing(team: String)
  /// T4.3: the PDF `file` (its file name) gave no calendar; nothing is staged. `.layoutNotRecognised` reads
  /// "Formato PDF non riconosciuto".
  case pdfReadFailed(file: String, reason: PDFCalendarError)
  /// T4.3: `PDFCalendar.Problem.incomplete`: "il PDF sembra incompleto". The rows read are still listed.
  case pdfIncomplete(teams: Int, clubs: Int)
  /// T4.3: `PDFCalendar.Problem.clubNotLinked`: the club `name` (page 1) is not in the club table; its home
  /// matches need review.
  case pdfClubNotLinked(name: String)
  /// T4.3: `PDFCalendar.Problem.unreadableRow`: a match row that could not be split into two sides.
  case pdfUnreadableRow(matchday: Int, text: String)
  /// T4.3: our club rests on matchday `matchday` (`PDFCalendar.byes`): "Giornata 8: riposo". Information.
  case pdfBye(matchday: Int)
  /// T4.11: `team` rests on matchday `matchday` (`SeasonFetch.byes`): "Prima Squadra, giornata 8: riposo.".
  /// Information.
  case seasonBye(team: String, matchday: Int)
  /// T4.11: matchday `matchday` of `team` could not be read (`SeasonFetch.failedMatchdays`); the run went on.
  case seasonMatchdayFailed(team: String, matchday: Int, reason: FixtureFetchError)
  /// T4.11: matchday `matchday` of `team` was read but cannot be trusted (`SeasonFetch.problems` with a matchday):
  /// "… La sorgente potrebbe essere cambiata.".
  case seasonMatchdayChanged(team: String, matchday: Int)
  /// T4.11: `team`'s run left matchdays unread (`SeasonFetch.stoppedAfter`): "lettura interrotta dopo la giornata N".
  case seasonStopped(team: String, afterMatchday: Int)

  public var message: String {
    switch self {
    case .fetchFailed(let team, let reason):
      return CoreStrings.importReadFailed(team) + " " + Self.text(for: reason)
    case .sourceProblem(let team, .structureChanged, _):
      return CoreStrings.importReadFailed(team) + " " + CoreStrings.importSourceChanged
    case .sourceProblem(let team, .noFixturesOfOurs, let club):
      return CoreStrings.importNoFixturesOfOurs(team, club)
    case .notYetAvailable(let team):
      return CoreStrings.importNotYetAvailable(team)
    case .logoNotRecognised(let opponent):
      return CoreStrings.logoNotRecognised(opponent)
    case .logoFallback(let opponent):
      return CoreStrings.logoFallback(opponent)
    case .logoFailed(let opponent):
      return CoreStrings.logoFailed(opponent)
    case .csiPageReadFailed(let team, let reason):
      return CoreStrings.csiPageReadFailed(team) + " "
        + (reason == .tooLarge ? CoreStrings.csiPageTooLarge : CoreStrings.csiPageNotReadable)
    case .csiNotAGirone(let team):
      return CoreStrings.csiNotAGirone(team)
    case .csiNoFixturesOfOurs(let team, let club):
      return CoreStrings.csiNoFixturesOfOurs(team, club)
    case .csiLogoUnavailable(let opponent):
      return CoreStrings.csiLogoUnavailable(opponent)
    case .standingsReadFailed(let team, let reason):
      return CoreStrings.standingsReadFailed(team) + " " + Self.text(for: reason)
    case .standingsChanged(let team):
      return CoreStrings.standingsReadFailed(team) + " " + CoreStrings.importSourceChanged
    case .csiTeamListMissing(let team):
      return CoreStrings.csiTeamListMissing(team)
    case .pdfReadFailed(let file, let reason):
      return CoreStrings.pdfReadFailed(file) + " " + Self.text(for: reason)
    case .pdfIncomplete(let teams, let clubs):
      return CoreStrings.pdfIncomplete(teams: teams, clubs: clubs)
    case .pdfClubNotLinked(let name):
      return CoreStrings.pdfClubNotLinked(name)
    case .pdfUnreadableRow(let matchday, let text):
      return CoreStrings.pdfUnreadableRow(matchday, text)
    case .pdfBye(let matchday):
      return CoreStrings.pdfBye(matchday)
    case .seasonBye(let team, let matchday):
      return CoreStrings.seasonBye(team, matchday)
    case .seasonMatchdayFailed(let team, let matchday, let reason):
      return CoreStrings.seasonMatchdayFailed(team, matchday) + " " + Self.text(for: reason)
    case .seasonMatchdayChanged(let team, let matchday):
      return CoreStrings.seasonMatchdayFailed(team, matchday) + " " + CoreStrings.importSourceChanged
    case .seasonStopped(let team, let matchday):
      return CoreStrings.seasonStopped(team, matchday)
    }
  }

  /// `false` for `.notYetAvailable`, `.logoFallback`, `.csiLogoUnavailable`, `.csiTeamListMissing`, `.pdfBye` and
  /// `.seasonBye`, which are information.
  public var isError: Bool {
    switch self {
    case .notYetAvailable, .logoFallback, .csiLogoUnavailable, .csiTeamListMissing, .pdfBye, .seasonBye: return false
    case .fetchFailed, .sourceProblem, .logoNotRecognised, .logoFailed, .csiPageReadFailed, .csiNotAGirone,
      .csiNoFixturesOfOurs, .standingsReadFailed, .standingsChanged, .pdfReadFailed, .pdfIncomplete,
      .pdfClubNotLinked, .pdfUnreadableRow, .seasonMatchdayFailed, .seasonMatchdayChanged, .seasonStopped:
      return true
    }
  }

  /// T4.11: the report lines for one team's season run, in this order: `.notYetAvailable` when
  /// `fetch.notYetAvailable`; for each of `problems` and `failedMatchdays`, merged by matchday,
  /// `.sourceProblem(…, .structureChanged, …)` (a problem without a matchday: the default page),
  /// `.seasonMatchdayChanged` or `.seasonMatchdayFailed`; `.seasonStopped` when `stoppedAfter` is set; then one
  /// `.seasonBye` per bye. Empty for a run cancelled before its first page. The caller drops `.seasonStopped` when the
  /// user cancelled, if it wants.
  public static func seasonNotices(team: String, fetch: SeasonFetch, clubShortName: String) -> [ImportIssue] {
    var notices: [ImportIssue] = []
    if fetch.notYetAvailable { notices.append(.notYetAvailable(team: team)) }
    let problems: [(Int, ImportIssue)] = fetch.problems.map { problem in
      guard let matchday = problem.matchday else {
        return (0, .sourceProblem(team: team, problem: problem.problem, clubShortName: clubShortName))
      }
      return (matchday, .seasonMatchdayChanged(team: team, matchday: matchday))
    }
    let failures: [(Int, ImportIssue)] = fetch.failedMatchdays.map {
      ($0.matchday, .seasonMatchdayFailed(team: team, matchday: $0.matchday, reason: $0.error))
    }
    notices += (problems + failures).sorted { $0.0 < $1.0 }.map(\.1)
    if let stoppedAfter = fetch.stoppedAfter { notices.append(.seasonStopped(team: team, afterMatchday: stoppedAfter)) }
    notices += fetch.byes.map { .seasonBye(team: team, matchday: $0) }
    return notices
  }

  /// T4.3: the notices shown above the review of `calendar`: one per problem, in `problems` order
  /// (`.pdfUnreadableRow`, `.pdfClubNotLinked`, `.pdfIncomplete`), then one `.pdfBye` per bye, in `byes` order.
  public static func pdfNotices(for calendar: PDFCalendar) -> [ImportIssue] {
    calendar.problems.map { problem in
      switch problem {
      case .clubNotLinked(let name): return .pdfClubNotLinked(name: name)
      case .incomplete(let teams, let clubs): return .pdfIncomplete(teams: teams, clubs: clubs)
      case .unreadableRow(let matchday, let text): return .pdfUnreadableRow(matchday: matchday, text: text)
      }
    } + calendar.byes.map { .pdfBye(matchday: $0) }
  }

  /// T4.8: the report line for a CSI page whose `PageFixtureParser` outcome gave nothing to stage;
  /// `nil` for a non-empty `.fixtures`. `.structureChanged` → `.csiNotAGirone`; `.noFixturesOfOurs`,
  /// `.notYetAvailable` and an empty `.fixtures` → `.csiNoFixturesOfOurs`.
  public static func csiPage(team: String, outcome: FixtureFetch, clubShortName: String) -> ImportIssue? {
    switch outcome {
    case .fixtures(let fixtures):
      return fixtures.isEmpty ? .csiNoFixturesOfOurs(team: team, clubShortName: clubShortName) : nil
    case .sourceProblem(.structureChanged):
      return .csiNotAGirone(team: team)
    case .sourceProblem(.noFixturesOfOurs), .notYetAvailable:
      return .csiNoFixturesOfOurs(team: team, clubShortName: clubShortName)
    }
  }

  private static func text(for reason: PDFCalendarError) -> String {
    switch reason {
    case .notAPDF: return CoreStrings.pdfNotAPDF
    case .tooLarge:
      return CoreStrings.pdfTooLarge(megabytes: PDFCalendar.maxFileSize / 1_048_576, pages: PDFCalendar.maxPages)
    case .encrypted: return CoreStrings.pdfEncrypted
    case .layoutNotRecognised: return CoreStrings.pdfLayoutNotRecognised
    case .unavailable: return CoreStrings.pdfUnavailable
    }
  }

  private static func text(for reason: FixtureFetchError) -> String {
    switch reason {
    case .missingWidgetID: return CoreStrings.importMissingWidgetID
    case .network: return CoreStrings.importNetwork
    case .timeout: return CoreStrings.importTimeout
    case .httpStatus(let code): return CoreStrings.importHTTPStatus(code)
    case .responseTooLarge: return CoreStrings.importTooLarge
    case .notAllowed: return CoreStrings.importNotAllowed
    case .unavailable: return CoreStrings.importUnavailable
    }
  }
}

// MARK: - Staging

/// The opponents a fetched name refers to exactly (T4.10 level 1): those whose name, short name or an alias equals
/// `name` under `opponentMatchKey` (legal prefixes and suffixes removed; case, accents, whitespace and punctuation
/// ignored): `"Oratorio San Gerolamo"` finds `"A.S.D. Oratorio San Gerolamo"`, `"CREMONESE S.P.A."` finds
/// `"U.S. Cremonese"`. In the order of `opponents`. An empty name finds nothing.
public func opponentsMatching(name: String, in opponents: [Opponent]) -> [Opponent] {
  let key = opponentMatchKey(name)
  guard !key.isEmpty else { return [] }
  return opponents.filter { opponent in
    ([opponent.name] + [opponent.shortName].compactMap { $0 } + opponent.aliases).contains {
      opponentMatchKey($0) == key
    }
  }
}

/// The opponents `fixture` refers to: `opponentsMatching` on its `opponentName`; when none, those matching any of
/// its `opponentAliases`, each once, in the order of `opponents`.
func opponentsMatching(fixture: FetchedFixture, in opponents: [Opponent]) -> [Opponent] {
  let byName = opponentsMatching(name: fixture.opponentName, in: opponents)
  guard byName.isEmpty, !fixture.opponentAliases.isEmpty else { return byName }
  let ids = Set(fixture.opponentAliases.flatMap { opponentsMatching(name: $0, in: opponents) }.map(\.id))
  return opponents.filter { ids.contains($0.id) }
}

/// `searchKey` after `stripLegalPrefixes`, apostrophes unified. Before T4.10 it was the opponent key; it is now only
/// the row id of the T4.9 review (`OpponentCandidate.id`). Opponents are matched with `opponentMatchKey`.
func importNameKey(_ name: String) -> String {
  searchKey(stripLegalPrefixes(name).replacingOccurrences(of: "’", with: "'"))
}

/// One row of the staging review: a fetched fixture matched to our data, with the draft an import
/// would write. Build it with `make(…)`; rebuild it after the user creates or links the opponent.
public struct ImportCandidate: Sendable, Codable, Equatable, Hashable, Identifiable {
  public enum State: String, Sendable, Codable, CaseIterable {
    /// No match of this team on this date: the draft is inserted.
    case new
    /// The team's match on this date differs from the draft: it is updated.
    case changed
    /// The team's match on this date already equals the draft (ignoring `source`).
    case unchanged
    /// The team's match on this date is locked: imports never touch it. Shown, never written.
    case locked
    /// The user must act first (see `reviewReasons`); there is no draft.
    /// A locked match is `.locked` even when a review reason exists.
    case needsReview
  }

  public enum ReviewReason: String, Sendable, Codable, CaseIterable {
    /// No opponent matches the fetched name: "crea" or "collega a esistente".
    case opponentNotFound
    /// Several opponents match the fetched name: "collega a esistente".
    case opponentAmbiguous
    /// `FetchedFixture.status` is `nil`.
    case unknownStatus
    /// T4.3: `FetchedFixture.scheduleUnknown`: the day and time are not known; the match is entered by hand.
    case scheduleUnknown
  }

  public var team: Team
  public var fixture: FetchedFixture
  /// The opponent the fixture was matched to: exact, the single proposal, or linked by the user; `nil` when none or
  /// several matched (`opponentMatch` `.notFound` or `.ambiguous`).
  public var opponent: Opponent?
  /// T4.10: how `opponent` was found. `.proposed` rows show the "Proposto" tag until the user confirms (rebuild with
  /// `linkedOpponentID`, which gives `.linked`).
  public var opponentMatch: OpponentMatch
  /// T4.10: `rankOpponents` for the fixture's name and aliases, at most `maxProposals`, best first; it may include
  /// the matched opponent itself. The top of the "Collega a esistente…" / "Cambia avversario…" picker.
  public var proposals: [OpponentProposal]
  /// The team's match on the fixture's date (the `MatchDraft.importKey` row), if any.
  public var existing: MatchDetail?
  /// What the import writes, with the source given to `make`. `nil` when the opponent is not resolved, the
  /// status not recognised or the schedule unknown (state `.needsReview`, or `.locked`). The UI may edit it before
  /// committing (the away venue, see `isVenueMissing`).
  public var draft: MatchDraft?
  public var state: State
  /// Empty unless `state == .needsReview`.
  public var reviewReasons: [ReviewReason]

  /// `MatchDraft.importKey` of the fixture: team id + date. One team plays at most one match a day.
  public var id: String { "\(team.id)|\(fixture.date.value)" }

  /// `true` when the draft has no venue: an away match not known yet ("da completare").
  public var isVenueMissing: Bool {
    guard let draft else { return false }
    return draft.venue.trimmingCharacters(in: .whitespaces).isEmpty
  }

  /// One Italian sentence per review reason, in order.
  public var reviewMessages: [String] {
    reviewReasons.map { reason in
      switch reason {
      case .opponentNotFound: return CoreStrings.reviewOpponentNotFound(fixture.opponentName)
      case .opponentAmbiguous: return CoreStrings.reviewOpponentAmbiguous(fixture.opponentName)
      case .unknownStatus: return CoreStrings.reviewUnknownStatus(fixture.statusText)
      case .scheduleUnknown: return CoreStrings.reviewScheduleUnknown(fixture.opponentName)
      }
    }
  }

  /// The most proposals a candidate keeps for the picker.
  public static let maxProposals = 5

  /// `opponentMatch` defaults to `.exact` when `opponent` is set and `.notFound` otherwise.
  public init(
    team: Team, fixture: FetchedFixture, opponent: Opponent?, existing: MatchDetail?, draft: MatchDraft?,
    state: State, reviewReasons: [ReviewReason], opponentMatch: OpponentMatch? = nil, proposals: [OpponentProposal] = []
  ) {
    self.team = team
    self.fixture = fixture
    self.opponent = opponent
    self.existing = existing
    self.draft = draft
    self.state = state
    self.reviewReasons = reviewReasons
    self.opponentMatch = opponentMatch ?? (opponent == nil ? .notFound : .exact)
    self.proposals = proposals
  }

  enum CodingKeys: String, CodingKey {
    case team, fixture, opponent, existing, draft, state, reviewReasons, opponentMatch, proposals
  }

  /// `opponentMatch` and `proposals` (T4.10) may be absent: they default as in `init`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      team: try container.decode(Team.self, forKey: .team),
      fixture: try container.decode(FetchedFixture.self, forKey: .fixture),
      opponent: try container.decodeIfPresent(Opponent.self, forKey: .opponent),
      existing: try container.decodeIfPresent(MatchDetail.self, forKey: .existing),
      draft: try container.decodeIfPresent(MatchDraft.self, forKey: .draft),
      state: try container.decode(State.self, forKey: .state),
      reviewReasons: try container.decode([ReviewReason].self, forKey: .reviewReasons),
      opponentMatch: try container.decodeIfPresent(OpponentMatch.self, forKey: .opponentMatch),
      proposals: try container.decodeIfPresent([OpponentProposal].self, forKey: .proposals) ?? [])
  }

  /// Matches `fixture` of `team` to our data.
  ///
  /// - Opponent (T4.10 levels, `opponentMatch`):
  ///   - `linkedOpponentID` when given (the user linked or confirmed it) → `.linked` (`.notFound` when no opponent
  ///     has that id);
  ///   - else level 1, exact: `opponentsMatching` on `fixture.opponentName`; when that finds none, the opponents
  ///     matching any of `fixture.opponentAliases` (each once, in the order of `opponents`). One → `.exact`;
  ///     several → `.ambiguous`, review (`opponentAmbiguous`);
  ///   - else level 2: the proposals of `rankOpponents`. Exactly one → `.proposed`, pre-filled like a link, **no**
  ///     review reason; several → `.ambiguous`, review (`opponentAmbiguous`); none → `.notFound`, review
  ///     (`opponentNotFound`).
  ///   - `proposals`: the first `maxProposals` of `rankOpponents`, whatever the level.
  /// - Existing match: the one in `existingMatches` with the same team and date.
  /// - Draft, when the opponent is known, the status recognised and the schedule known:
  ///   - new match: team, opponent, date, time, home/away, round, status, score from the fixture;
  ///     venue `homeVenue` at home; away, the fixture's `venue` (whitespace collapsed, cut with
  ///     `truncateAtWord` to `FieldLimits.venue`), or empty when it has none; competition the fixture's
  ///     (whitespace collapsed, cut to `FieldLimits.competition`), `nil` when it has none;
  ///   - existing match: starts from it and takes the opponent, home/away, status and score from the
  ///     fixture, plus time and round when the fixture has them; half-time is kept only for a played
  ///     match. Exception (T4.5, a typed result is never erased): when the fixture has no score, its status
  ///     is `.scheduled` or `.played` and the existing match has a `score`, the existing `score`,
  ///     `halfTime` and `status` are kept; when the existing match has a `halfTime` but no `score`, its
  ///     `halfTime` is kept and status and score come from the fixture as usual. A fixture with a score still wins over a typed one; a postponed
  ///     or cancelled fixture still clears both scores. The venue is kept unless it is empty or home/away
  ///     changed, then it becomes the new match's venue (above). Notes are kept; competition is kept, or
  ///     becomes the fixture's when the match has none.
  ///   - source is `source` (`.scrape` for tuttocampo and CSI, `.pdf` for T4.3); `isLocked` is the existing match's.
  /// - State: `.locked` when the existing match is locked (draft still shown); else `.needsReview`
  ///   when there is a review reason; else `.new` without an existing match; else `.unchanged` when
  ///   the normalised draft equals the existing match's (ignoring `source`), `.changed` otherwise.
  public static func make(
    fixture: FetchedFixture, team: Team, opponents: [Opponent], existingMatches: [MatchDetail], homeVenue: String,
    linkedOpponentID: EntityID? = nil, source: MatchSource = .scrape
  ) -> ImportCandidate {
    let ranked = rankOpponents(name: fixture.opponentName, aliases: fixture.opponentAliases, in: opponents)
    var found: [Opponent]
    var match: OpponentMatch
    if let linkedOpponentID {
      found = opponents.filter { $0.id == linkedOpponentID }
      match = .linked
    } else {
      found = opponentsMatching(fixture: fixture, in: opponents)
      match = .exact
      if found.isEmpty {
        found = ranked.filter { $0.kind != .exact }.map(\.opponent)
        match = .proposed
      }
    }
    if found.isEmpty { match = .notFound }
    if found.count > 1 { match = .ambiguous }
    let opponent = found.count == 1 ? found[0] : nil
    var reasons: [ReviewReason] = []
    if found.isEmpty { reasons.append(.opponentNotFound) }
    if found.count > 1 { reasons.append(.opponentAmbiguous) }
    if fixture.status == nil { reasons.append(.unknownStatus) }
    if fixture.scheduleUnknown { reasons.append(.scheduleUnknown) }
    let existing = existingMatches.first { $0.match.teamID == team.id && $0.match.date == fixture.date }

    var draft: MatchDraft?
    if let opponent, let status = fixture.status, !fixture.scheduleUnknown {
      let awayVenue = fixture.venue.map { truncateAtWord($0.collapsedWhitespace, max: FieldLimits.venue).text } ?? ""
      let venueForSide = fixture.isHome ? homeVenue : awayVenue
      let competition = fixture.competition.map {
        truncateAtWord($0.collapsedWhitespace, max: FieldLimits.competition).text
      }
      if let existing {
        var updated = MatchDraft(existing.match)
        updated.opponentID = opponent.id
        if let time = fixture.time { updated.time = time }
        if updated.isHome != fixture.isHome || updated.venue.trimmingCharacters(in: .whitespaces).isEmpty {
          updated.venue = venueForSide
        }
        updated.isHome = fixture.isHome
        // T4.5: an import never erases a result the user typed before the source had it.
        let fixtureHasNoResult = fixture.score == nil && (status == .scheduled || status == .played)
        let keepsTypedResult = fixtureHasNoResult && existing.match.score != nil
        if !keepsTypedResult {
          updated.status = status
          updated.score = fixture.score
          // A half-time score typed alone is kept too.
          if status != .played && !fixtureHasNoResult { updated.halfTime = nil }
        }
        if let round = fixture.round { updated.round = round }
        if updated.competition?.collapsedWhitespace.nilIfEmpty == nil { updated.competition = competition }
        updated.source = source
        draft = updated.normalized()
      } else {
        draft = MatchDraft(
          teamID: team.id, opponentID: opponent.id, date: fixture.date, time: fixture.time, isHome: fixture.isHome,
          venue: venueForSide, competition: competition, round: fixture.round, status: status, score: fixture.score,
          source: source
        ).normalized()
      }
    }

    let state: State
    if existing?.match.isLocked == true {
      state = .locked
    } else if !reasons.isEmpty {
      state = .needsReview
    } else if let existing, let draft {
      var current = MatchDraft(existing.match).normalized()
      current.source = draft.source
      state = current == draft ? .unchanged : .changed
    } else {
      state = .new
    }
    return ImportCandidate(
      team: team, fixture: fixture, opponent: opponent, existing: existing, draft: draft, state: state,
      reviewReasons: state == .needsReview ? reasons : [], opponentMatch: match,
      proposals: Array(ranked.prefix(maxProposals)))
  }
}
