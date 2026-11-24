import Foundation
import SSCore

/// A fixture source with canned answers per widget id, for `--mock`, previews and tests. No network.
///
/// `AppServices.fake()` uses `scenario(referenceSaturday:logos:)`, which covers every staging state
/// and every report line against the fixture data set (see the table there).
public struct FakeFixtureSource: FixtureSource {
  /// The canned answer for one widget.
  public enum Response: Sendable, Equatable {
    case fetch(FixtureFetch)
    case failure(FixtureFetchError)
  }

  /// A canned season for one widget (T4.11): the default page is `pages[currentMatchday]` with `matchdayCount` in
  /// its head; every other page answers `pages[n]`, or `FixtureFetchError.httpStatus(404)` when absent. A
  /// `.fetch(.sourceProblem(.noFixturesOfOurs))` page is a bye.
  public struct Season: Sendable, Equatable {
    public var currentMatchday: Int
    /// `matchesNumber`; `nil` = the head has none (`readSeason` then probes for the end).
    public var matchdayCount: Int?
    public var pages: [Int: Response]

    public init(currentMatchday: Int, matchdayCount: Int?, pages: [Int: Response]) {
      self.currentMatchday = currentMatchday
      self.matchdayCount = matchdayCount
      self.pages = pages
    }
  }

  /// The canned answer for one Classifica widget (T4.9).
  public enum LeagueResponse: Sendable, Equatable {
    case fetch(LeagueTeamsFetch)
    case failure(FixtureFetchError)
  }

  /// Keyed by widget id in lower case. An id with no entry throws `FixtureFetchError.httpStatus(404)`.
  public var responses: [String: Response]
  /// Classifica answers, keyed by widget id in lower case. An id with no entry throws
  /// `FixtureFetchError.httpStatus(404)`. The teams returned get the asking team's id and `.tuttocampo`.
  public var leagueResponses: [String: LeagueResponse]
  /// Seasons (T4.11), keyed by widget id in lower case. A widget with no season but a `responses` entry gets a
  /// one-matchday season made of it (matchday 1 of 1), so a run over every team gives each team's weekend outcome.
  /// A widget with neither throws `FixtureFetchError.httpStatus(404)`.
  public var seasons: [String: Season]
  public var logos: any LogoStore
  /// The bytes stored for every logo download that succeeds.
  public var logoData: Data
  /// ClubIds whose `Teams/200` copy "fails": their fallback is stored, with `.logoFallback`.
  public var fallbackClubIDs: Set<String>
  /// ClubIds whose downloads all "fail" (`.logoFailed`).
  public var failingClubIDs: Set<String>
  /// Pause before each fetch, so progress can be seen. Cancellation during the pause throws
  /// `CancellationError`.
  public var delay: Duration

  public init(
    responses: [String: Response] = [:], logos: any LogoStore, logoData: Data = FakeFixtureSource.defaultLogoData,
    fallbackClubIDs: Set<String> = [], failingClubIDs: Set<String> = [], delay: Duration = .zero,
    leagueResponses: [String: LeagueResponse] = [:], seasons: [String: Season] = [:]
  ) {
    self.responses = Dictionary(responses.map { ($0.key.lowercased(), $0.value) }) { _, last in last }
    self.leagueResponses = Dictionary(leagueResponses.map { ($0.key.lowercased(), $0.value) }) { _, last in last }
    self.seasons = Dictionary(seasons.map { ($0.key.lowercased(), $0.value) }) { _, last in last }
    self.logos = logos
    self.logoData = logoData
    self.fallbackClubIDs = fallbackClubIDs
    self.failingClubIDs = failingClubIDs
    self.delay = delay
  }

  public func fetchFixtures(for team: Team, settings: ClubSettings) async throws -> FixtureFetch {
    guard let widgetID = team.tuttocampoWidgetID else { throw FixtureFetchError.missingWidgetID }
    if delay > .zero { try await Task.sleep(for: delay) }
    try Task.checkCancellation()
    switch responses[widgetID.lowercased()] {
    case .fetch(let fetch): return fetch
    case .failure(let error): throw error
    case nil: throw FixtureFetchError.httpStatus(404)
    }
  }

  public func fetchLeagueTeams(for team: Team, settings: ClubSettings) async throws -> LeagueTeamsFetch {
    guard let widgetID = team.tuttocampoWidgetID else { throw FixtureFetchError.missingWidgetID }
    if delay > .zero { try await Task.sleep(for: delay) }
    try Task.checkCancellation()
    switch leagueResponses[widgetID.lowercased()] {
    case .fetch(.teams(let teams)):
      return .teams(SourceTeamList(teamID: team.id, source: .tuttocampo, readAt: Date(), teams: teams).teams)
    case .fetch(.structureChanged): return .structureChanged
    case .failure(let error): throw error
    case nil: throw FixtureFetchError.httpStatus(404)
    }
  }

  /// Runs `readSeason` over the widget's `Season`, with `delay` before each page. A pause cancelled during a page
  /// counts as cancellation (the page is not read).
  public func fetchSeason(
    for team: Team, settings: ClubSettings, scope: SeasonScope, onProgress: @Sendable (SeasonProgress) async -> Void
  ) async throws -> SeasonFetch {
    guard let widgetID = team.tuttocampoWidgetID?.lowercased() else { throw FixtureFetchError.missingWidgetID }
    let season: Season
    if let stored = seasons[widgetID] {
      season = stored
    } else if let weekend = responses[widgetID] {
      season = Season(currentMatchday: 1, matchdayCount: 1, pages: [1: weekend])
    } else {
      throw FixtureFetchError.httpStatus(404)
    }
    let delay = delay
    return try await readSeason(
      scope: scope,
      readPage: { requested in
        if delay > .zero { try await Task.sleep(for: delay) }
        try Task.checkCancellation()
        let matchday = requested ?? season.currentMatchday
        switch season.pages[matchday] {
        case .fetch(let outcome):
          return SeasonPage(matchday: matchday, matchdayCount: season.matchdayCount, outcome: outcome)
        case .failure(let error): throw error
        case nil: throw FixtureFetchError.httpStatus(404)
        }
      }, onProgress: onProgress)
  }

  public func downloadLogos(_ requests: [LogoRequest]) async -> [LogoResult] {
    enum Outcome {
      case stored(String)
      case fallback(String)
      case failed
    }
    var outcomes: [String: Outcome] = [:]
    var results: [LogoResult] = []
    for request in requests {
      guard !Task.isCancelled else {
        results.append(LogoResult(request: request, fileName: nil, issue: nil))
        continue
      }
      guard let clubID = request.clubID, let fileName = tuttocampoLogoFileName(clubID: clubID) else {
        results.append(
          LogoResult(request: request, fileName: nil, issue: .logoNotRecognised(opponent: request.opponentName)))
        continue
      }
      let outcome: Outcome
      if let known = outcomes[clubID] {
        outcome = known
      } else {
        let usesFallback = fallbackClubIDs.contains(clubID)
        if failingClubIDs.contains(clubID) || (usesFallback && request.fallbackURL == nil) {
          outcome = .failed
        } else if (try? await logos.importLogo(data: logoData, fileName: fileName, replacing: nil)) != nil {
          outcome = usesFallback ? .fallback(fileName) : .stored(fileName)
        } else {
          outcome = .failed
        }
        outcomes[clubID] = outcome
      }
      switch outcome {
      case .stored(let name):
        results.append(LogoResult(request: request, fileName: name, issue: nil))
      case .fallback(let name):
        results.append(
          LogoResult(request: request, fileName: name, issue: .logoFallback(opponent: request.opponentName)))
      case .failed:
        results.append(LogoResult(request: request, fileName: nil, issue: .logoFailed(opponent: request.opponentName)))
      }
    }
    return results
  }

  /// A fixture crest when the fixtures can be found, otherwise a 1×1 PNG.
  public static var defaultLogoData: Data {
    if let folder = try? Fixtures.logosFolder(),
      let data = try? Data(contentsOf: folder.appendingPathComponent("fixture-lucia.png"))
    {
      return data
    }
    return Data(base64Encoded: onePixelPNG) ?? Data()
  }

  static let onePixelPNG =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

  // MARK: Scenario

  /// The widget id of the scenario entry for team number `index` (1-based, as in `matches.json`).
  public static func scenarioWidgetID(_ index: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", index) }

  /// ClubId of the opponent whose `Teams/200` logo "fails" in the scenario (Atletico Montesello).
  public static let scenarioFallbackClubID = "900209"

  /// Canned answers for the teams of `Resources/Fixtures/matches.json`, dated around
  /// `referenceSaturday` (pass the data set's, after shifting). With that data set:
  ///
  /// | Widget | Team | Answer | Candidate / report |
  /// |---|---|---|---|
  /// | 1 | Prima Squadra | Sun, home, "Oratorio San Gerolamo", as stored | `.unchanged` |
  /// | 2 | Juniores | Sun, away, time 11:00 instead of 10:30 | `.changed` |
  /// | 3 | Allievi U17 | Sat, home, played 3–1 | `.changed` (result) |
  /// | 4 | Allievi U16 | Sun, status "Partita sospesa" | `.needsReview` (unknown status) |
  /// | 5 | Giovanissimi U15 | page structure changed | `.sourceProblem(.structureChanged)` |
  /// | 6 | Giovanissimi U14 | "Risultati non ancora disponibili." | `.notYetAvailable` (information) |
  /// | 7 | Esordienti | network failure | `.fetchFailed(.network)` |
  /// | 8 | Pulcini | Sat, away, time 10:00 (stored without time) | `.changed` |
  /// | 9 | Primi Calci | Sun, time 11:30 | `.locked` (the stored match is locked); logo via fallback |
  /// | 10 | Femminile | Sun, "Partita rinviata", as stored | `.unchanged` |
  /// | 11 | Juniores Femminile | Sun, away, unknown "Atletico Nuovo Borgo", unrecognised logo address | `.needsReview` (opponent not found), away venue missing; logo not recognised |
  /// | 12 | Amatori | Sat 20:30, home, "Virtus Campofelice" | `.new` |
  ///
  /// Veterani has no widget id.
  ///
  /// Season (T4.11, `fetchSeason`): widget 9 (Primi Calci) has `scenarioSeason(referenceSaturday:)`; every other
  /// widget answers a one-matchday season made of its weekend answer (Giovanissimi U14 not yet available,
  /// Giovanissimi U15 a problem on the default page, Esordienti throws `.network`).
  ///
  /// Classifica answers (T4.9, `fetchLeagueTeams`), with `FakePageFixtureParser.scenarioTeams` stored for
  /// Pulcini's CSI page (`AppServices.fake` saves it):
  ///
  /// | Widget | Team | Answer |
  /// |---|---|---|
  /// | 1 | Prima Squadra | "Oratorio San Gerolamo", "Borgo Lucente" (ClubId 900301), "Real Fontanile" (900302), "Aurora Pianengo" (900303), "Virtus Campofelice" |
  /// | 2 | Juniores | "Aurora Pianengo" (another ClubId, 900304), "Sporting Ripalta Nuova" |
  /// | 5 | Giovanissimi U15 | `.structureChanged` |
  /// | 6 | Giovanissimi U14 | "Atletico Nuovo Borgo" (unrecognised logo address), "Novaria Bassa" |
  /// | 7 | Esordienti | network failure |
  /// | others | | no other team |
  ///
  /// With the fixture opponents, `OpponentCandidate.make` gives: `.new` Aurora Pianengo (seen twice),
  /// Polisportiva Fontanella (CSI), Atletico Nuovo Borgo (logo not recognised); `.missingLogo` Borgo Lucente
  /// (tuttocampo logo, also in the CSI list with the placeholder), Atletico Montesello (CSI logo
  /// `csi-90000104.png`); `.possibleDuplicate` "Real Fontanile" with "Real Fontanile B" (CSI, two new rows),
  /// "Valdorso 2016" (CSI) with F.C. Valdorso; `.present` the others.
  public static func scenario(
    referenceSaturday: DayDate, logos: any LogoStore, delay: Duration = .milliseconds(250)
  ) -> FakeFixtureSource {
    let saturday = referenceSaturday
    let sunday = referenceSaturday.adding(days: 1)
    func time(_ hour: Int, _ minute: Int) -> ClockTime? { ClockTime(hour: hour, minute: minute) }
    func logo(_ clubID: String) -> URL? { URL(string: "https://b2-content.tuttocampo.it/Teams/40/\(clubID).png?v=1") }
    func scheduled(
      _ date: DayDate, _ clock: ClockTime?, home: Bool, _ name: String, club: String, round: Int? = nil
    ) -> FetchedFixture {
      FetchedFixture(
        date: date, time: clock, isHome: home, opponentName: name, opponentClubID: club, opponentLogoURL: logo(club),
        round: round, status: .scheduled, statusText: "Partita da giocare")
    }
    var played = scheduled(saturday, time(15, 0), home: true, "Castelverde Calcio", club: "900203", round: 10)
    played.status = .played
    played.score = Score(us: 3, them: 1)
    played.statusText = "Partita terminata"
    var suspended = scheduled(sunday, time(10, 0), home: true, "Novaria Bassa", club: "900204")
    suspended.status = nil
    suspended.statusText = "Partita sospesa"
    var postponed = scheduled(sunday, time(18, 0), home: true, "Sant'Ilario Città", club: "900210")
    postponed.status = .postponed
    postponed.statusText = "Partita rinviata"
    var unknown = scheduled(sunday, time(15, 30), home: false, "Atletico Nuovo Borgo", club: "900211")
    unknown.opponentClubID = nil
    unknown.opponentLogoURL = URL(string: "https://b2-content.tuttocampo.it/Web/Images/stemma.png")

    let answers: [Int: Response] = [
      1: .fetch(
        .fixtures([scheduled(sunday, time(14, 30), home: true, "Oratorio San Gerolamo", club: "900201", round: 12)])),
      2: .fetch(
        .fixtures([
          scheduled(
            sunday, time(11, 0), home: false, "Oratorio Sant'Eufrasio di Valfonda Bassa", club: "900202", round: 10)
        ])),
      3: .fetch(.fixtures([played])),
      4: .fetch(.fixtures([suspended])),
      5: .fetch(.sourceProblem(.structureChanged)),
      6: .fetch(.notYetAvailable),
      7: .failure(.network),
      8: .fetch(.fixtures([scheduled(saturday, time(10, 0), home: false, "Prato Fiorito", club: "900208")])),
      9: .fetch(
        .fixtures([scheduled(sunday, time(11, 30), home: true, "Atletico Montesello", club: scenarioFallbackClubID)])),
      10: .fetch(.fixtures([postponed])),
      11: .fetch(.fixtures([unknown])),
      12: .fetch(
        .fixtures([scheduled(saturday, time(20, 30), home: true, "Virtus Campofelice", club: "900212", round: 8)])),
    ]
    func listed(_ name: String, club: String?) -> SourceTeam {
      SourceTeam(source: .tuttocampo, teamID: "", name: name, logoID: club, logoURL: club.flatMap(logo))
    }
    var nuovoBorgo = listed("Atletico Nuovo Borgo", club: nil)
    nuovoBorgo.logoURL = URL(string: "https://b2-content.tuttocampo.it/Web/Images/stemma.png")
    var leagues: [Int: LeagueResponse] = [
      1: .fetch(
        .teams([
          listed("Oratorio San Gerolamo", club: "900201"), listed("Borgo Lucente", club: "900301"),
          listed("Real Fontanile", club: "900302"), listed("Aurora Pianengo", club: "900303"),
          listed("Virtus Campofelice", club: "900212"),
        ])),
      2: .fetch(.teams([listed("Aurora Pianengo", club: "900304"), listed("Sporting Ripalta Nuova", club: "900305")])),
      5: .fetch(.structureChanged),
      6: .fetch(.teams([nuovoBorgo, listed("Novaria Bassa", club: "900204")])),
      7: .failure(.network),
    ]
    for index in 1...12 where leagues[index] == nil { leagues[index] = .fetch(.teams([])) }
    return FakeFixtureSource(
      responses: Dictionary(uniqueKeysWithValues: answers.map { (scenarioWidgetID($0.key), $0.value) }), logos: logos,
      fallbackClubIDs: [scenarioFallbackClubID], delay: delay,
      leagueResponses: Dictionary(uniqueKeysWithValues: leagues.map { (scenarioWidgetID($0.key), $0.value) }),
      seasons: [scenarioWidgetID(9): scenarioSeason(referenceSaturday: referenceSaturday)])
  }

  /// The 10-matchday season of Primi Calci (widget 9) around `referenceSaturday`: matchday `n` is on the Sunday
  /// `7 × (n − 5)` days from that weekend's, the current matchday is 5. Pages give no round, so `readSeason` fills
  /// it. Against `Resources/Fixtures/matches.json` (shifted), with candidate states:
  ///
  /// | Matchday | Page | Candidate / report |
  /// |---|---|---|
  /// | 1 | played 2–0, home, Novaria Bassa, 11:00 | `.new` (past) |
  /// | 2 | played 1–1, away, Real Cascina Alta, 10:00 | `.new` (past), away venue missing |
  /// | 3 | timeout | `.seasonMatchdayFailed(…, .timeout)` |
  /// | 4 | played 3–2, away, Sporting Ripalta Nuova, 10:30 | `.new` (past), away venue missing |
  /// | 5 (current) | home, Atletico Montesello, 11:30 (the weekend answer) | `.locked` |
  /// | 6 | away, Prato Fiorito, 10:00 | `.changed` (the stored match gets round 6) |
  /// | 7 | no row of ours | `.seasonBye` |
  /// | 8 | home, Oratorio Santa Lucia, 11:00 | `.new` |
  /// | 9 | away, "Polisportiva Nuova Aurora", 10:30 | `.needsReview` (opponent not found) |
  /// | 10 | home, Unione Calcio Brolo Verde, no time | `.new`, without time |
  ///
  /// `.wholeSeason` requests 10 pages (5, then 1–4 and 6–10); `.fromCurrentMatchday` 6 (5–10), with only the bye.
  public static func scenarioSeason(referenceSaturday: DayDate) -> Season {
    let sunday = referenceSaturday.adding(days: 1)
    func fixture(
      _ matchday: Int, _ clock: ClockTime?, home: Bool, _ name: String, club: String, score: Score? = nil
    ) -> Response {
      let played = score != nil
      return .fetch(
        .fixtures([
          FetchedFixture(
            date: sunday.adding(days: 7 * (matchday - 5)), time: clock, isHome: home, opponentName: name,
            opponentClubID: club,
            opponentLogoURL: URL(string: "https://b2-content.tuttocampo.it/Teams/40/\(club).png?v=1"),
            score: score, status: played ? .played : .scheduled,
            statusText: played ? "Partita terminata" : "Partita da giocare")
        ]))
    }
    return Season(
      currentMatchday: 5, matchdayCount: 10,
      pages: [
        1: fixture(
          1, ClockTime(hour: 11, minute: 0), home: true, "Novaria Bassa", club: "900204", score: Score(us: 2, them: 0)),
        2: fixture(
          2, ClockTime(hour: 10, minute: 0), home: false, "Real Cascina Alta", club: "900221",
          score: Score(us: 1, them: 1)),
        3: .failure(.timeout),
        4: fixture(
          4, ClockTime(hour: 10, minute: 30), home: false, "Sporting Ripalta Nuova", club: "900222",
          score: Score(us: 3, them: 2)),
        5: fixture(5, ClockTime(hour: 11, minute: 30), home: true, "Atletico Montesello", club: scenarioFallbackClubID),
        6: fixture(6, ClockTime(hour: 10, minute: 0), home: false, "Prato Fiorito", club: "900208"),
        7: .fetch(.sourceProblem(.noFixturesOfOurs)),
        8: fixture(8, ClockTime(hour: 11, minute: 0), home: true, "Oratorio Santa Lucia", club: "900223"),
        9: fixture(9, ClockTime(hour: 10, minute: 30), home: false, "Polisportiva Nuova Aurora", club: "900224"),
        10: fixture(10, nil, home: true, "Unione Calcio Brolo Verde", club: "900225"),
      ])
  }
}
