import Foundation

// Match import from an outside source: T4.2 reads tuttocampo.it widgets; T4.1 (CSV) reuses the staging
// types. The flow, driven by the UI:
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

  public init(
    date: DayDate, time: ClockTime?, isHome: Bool, opponentName: String, opponentClubID: String? = nil,
    opponentLogoURL: URL? = nil, score: Score? = nil, round: Int? = nil, status: MatchStatus?, statusText: String
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
  }
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
    }
  }

  /// `false` for `.notYetAvailable` and `.logoFallback`, which are information.
  public var isError: Bool {
    switch self {
    case .notYetAvailable, .logoFallback: return false
    case .fetchFailed, .sourceProblem, .logoNotRecognised, .logoFailed: return true
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

/// The opponents a fetched name refers to: those whose name, short name or an alias equals `name`
/// once legal prefixes are removed and case, accents, whitespace and apostrophe style are ignored
/// (`"Oratorio San Gerolamo"` finds `"A.S.D. Oratorio San Gerolamo"`). In the order of `opponents`.
/// An empty name finds nothing.
public func opponentsMatching(name: String, in opponents: [Opponent]) -> [Opponent] {
  let key = importNameKey(name)
  guard !key.isEmpty else { return [] }
  return opponents.filter { opponent in
    ([opponent.name] + [opponent.shortName].compactMap { $0 } + opponent.aliases).contains { importNameKey($0) == key }
  }
}

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
  }

  public var team: Team
  public var fixture: FetchedFixture
  /// The opponent the fixture was matched to; `nil` when none or several matched.
  public var opponent: Opponent?
  /// The team's match on the fixture's date (the `MatchDraft.importKey` row), if any.
  public var existing: MatchDetail?
  /// What the import writes, with source `.scrape`. `nil` when the opponent is not resolved or the
  /// status not recognised (state `.needsReview`, or `.locked`). The UI may edit it before
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
      }
    }
  }

  public init(
    team: Team, fixture: FetchedFixture, opponent: Opponent?, existing: MatchDetail?, draft: MatchDraft?,
    state: State, reviewReasons: [ReviewReason]
  ) {
    self.team = team
    self.fixture = fixture
    self.opponent = opponent
    self.existing = existing
    self.draft = draft
    self.state = state
    self.reviewReasons = reviewReasons
  }

  /// Matches `fixture` of `team` to our data.
  ///
  /// - Opponent: `linkedOpponentID` when given (the user linked it), else `opponentsMatching`; none
  ///   or several → review.
  /// - Existing match: the one in `existingMatches` with the same team and date.
  /// - Draft, when the opponent is known and the status recognised:
  ///   - new match: team, opponent, date, time, home/away, round, status, score from the fixture;
  ///     venue `homeVenue` at home, empty away;
  ///   - existing match: starts from it and takes the opponent, home/away, status and score from the
  ///     fixture, plus time and round when the fixture has them; half-time is kept only for a played
  ///     match; the venue is kept unless it is empty or home/away changed, then it becomes
  ///     `homeVenue` at home and empty away. Competition and notes are kept.
  ///   - source is always `.scrape`; `isLocked` is the existing match's.
  /// - State: `.locked` when the existing match is locked (draft still shown); else `.needsReview`
  ///   when there is a review reason; else `.new` without an existing match; else `.unchanged` when
  ///   the normalised draft equals the existing match's (ignoring `source`), `.changed` otherwise.
  public static func make(
    fixture: FetchedFixture, team: Team, opponents: [Opponent], existingMatches: [MatchDetail], homeVenue: String,
    linkedOpponentID: EntityID? = nil
  ) -> ImportCandidate {
    let found =
      linkedOpponentID.map { id in opponents.filter { $0.id == id } }
      ?? opponentsMatching(name: fixture.opponentName, in: opponents)
    let opponent = found.count == 1 ? found[0] : nil
    var reasons: [ReviewReason] = []
    if found.isEmpty { reasons.append(.opponentNotFound) }
    if found.count > 1 { reasons.append(.opponentAmbiguous) }
    if fixture.status == nil { reasons.append(.unknownStatus) }
    let existing = existingMatches.first { $0.match.teamID == team.id && $0.match.date == fixture.date }

    var draft: MatchDraft?
    if let opponent, let status = fixture.status {
      let venueForSide = fixture.isHome ? homeVenue : ""
      if let existing {
        var updated = MatchDraft(existing.match)
        updated.opponentID = opponent.id
        if let time = fixture.time { updated.time = time }
        if updated.isHome != fixture.isHome || updated.venue.trimmingCharacters(in: .whitespaces).isEmpty {
          updated.venue = venueForSide
        }
        updated.isHome = fixture.isHome
        updated.status = status
        updated.score = fixture.score
        if status != .played { updated.halfTime = nil }
        if let round = fixture.round { updated.round = round }
        updated.source = .scrape
        draft = updated.normalized()
      } else {
        draft = MatchDraft(
          teamID: team.id, opponentID: opponent.id, date: fixture.date, time: fixture.time, isHome: fixture.isHome,
          venue: venueForSide, round: fixture.round, status: status, score: fixture.score, source: .scrape
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
      reviewReasons: state == .needsReview ? reasons : [])
  }
}
