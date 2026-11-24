import Foundation
import SSCoreFakes
import Testing

@testable import SSCore

@Suite struct ImportTests {
  let sunday = DayDate(year: 2026, month: 11, day: 22)!
  let team = Team(id: "team", name: "Juniores", shortLabel: "Jun", sortOrder: 1, isFirstTeam: false, isActive: true)
  let gerolamo = Opponent(
    id: "o1", name: "A.S.D. Oratorio San Gerolamo", shortName: "San Gerolamo", aliases: ["Oratorio S. Gerolamo"])
  let ilario = Opponent(id: "o2", name: "G.S. Sant’Ilario Città")
  let valdorso = Opponent(id: "o3", name: "F.C. Valdorso")
  var opponents: [Opponent] { [gerolamo, ilario, valdorso] }

  func fixture(
    _ name: String = "Oratorio San Gerolamo", home: Bool = true, time: ClockTime? = ClockTime(hour: 14, minute: 30),
    status: MatchStatus? = .scheduled, score: Score? = nil, round: Int? = 12
  ) -> FetchedFixture {
    FetchedFixture(
      date: sunday, time: time, isHome: home, opponentName: name, opponentClubID: "900101",
      opponentLogoURL: URL(string: "https://b2-content.tuttocampo.it/Teams/40/900101.png?v=1"), score: score,
      round: round, status: status, statusText: status == nil ? "Partita sospesa" : "Partita da giocare")
  }

  func stored(
    opponent: Opponent? = nil, home: Bool = true, time: ClockTime? = ClockTime(hour: 14, minute: 30),
    venue: String = "Campo Comunale", status: MatchStatus = .scheduled, round: Int? = 12, score: Score? = nil,
    halfTime: Score? = nil, locked: Bool = false, source: MatchSource = .manual
  ) -> MatchDetail {
    let opponent = opponent ?? gerolamo
    let date = Date(timeIntervalSince1970: 0)
    let match = Match(
      id: "m1", teamID: team.id, opponentID: opponent.id, date: sunday, time: time, isHome: home, venue: venue,
      competition: "Juniores Regionali", round: round, status: status, score: score, halfTime: halfTime, notes: "Note",
      source: source, isLocked: locked, createdAt: date, updatedAt: date)
    return MatchDetail(match: match, team: team, opponent: opponent)
  }

  func make(_ fixture: FetchedFixture, existing: [MatchDetail] = [], linked: EntityID? = nil) -> ImportCandidate {
    ImportCandidate.make(
      fixture: fixture, team: team, opponents: opponents, existingMatches: existing, homeVenue: "Campo Comunale",
      linkedOpponentID: linked)
  }

  // MARK: Opponent matching

  @Test func opponentsMatchByNameShortNameAndAlias() {
    for name in [
      "Oratorio San Gerolamo", "A.S.D. Oratorio San Gerolamo", "oratorio  san gerolamo ", "San Gerolamo",
      "Oratorio S. Gerolamo", "ORATORIO SAN GEROLAMO",
    ] {
      #expect(opponentsMatching(name: name, in: opponents).map(\.id) == ["o1"], "\(name)")
    }
    #expect(opponentsMatching(name: "Sant'Ilario Citta", in: opponents).map(\.id) == ["o2"])  // apostrophe, accent
    #expect(opponentsMatching(name: "Gerolamo", in: opponents).isEmpty)  // no partial matches
    #expect(opponentsMatching(name: "", in: opponents).isEmpty)
    let twin = Opponent(id: "o4", name: "Valdorso", aliases: [])
    #expect(opponentsMatching(name: "Valdorso", in: opponents + [twin]).map(\.id) == ["o3", "o4"])
  }

  // MARK: Candidates

  @Test func newMatchAtHomeAndAway() throws {
    let home = make(fixture())
    #expect(home.state == .new && home.reviewReasons.isEmpty && home.opponent == gerolamo)
    let draft = try #require(home.draft)
    #expect(draft.teamID == team.id && draft.opponentID == gerolamo.id && draft.date == sunday)
    #expect(draft.time?.value == "14:30" && draft.isHome && draft.round == 12 && draft.status == .scheduled)
    #expect(draft.venue == "Campo Comunale" && draft.source == .scrape && !draft.isLocked)
    #expect(!home.isVenueMissing)
    #expect(home.id == draft.importKey)

    let away = make(fixture(home: false))
    #expect(away.state == .new && away.draft?.venue == "" && away.isVenueMissing)
  }

  @Test func unchangedIgnoresSource() {
    let candidate = make(fixture(), existing: [stored(source: .manual)])
    #expect(candidate.state == .unchanged)
    #expect(candidate.draft?.source == .scrape)
    #expect(candidate.existing?.id == "m1")
  }

  @Test func changedFields() throws {
    let later = make(fixture(time: ClockTime(hour: 15, minute: 0)), existing: [stored()])
    #expect(later.state == .changed && later.draft?.time?.value == "15:00")
    // Competition and notes are kept; a missing fixture time keeps the stored one.
    let noTime = make(fixture(time: nil, round: nil), existing: [stored()])
    #expect(noTime.state == .unchanged && noTime.draft?.time?.value == "14:30" && noTime.draft?.round == 12)
    #expect(noTime.draft?.competition == "Juniores Regionali" && noTime.draft?.notes == "Note")
    // A result.
    let played = make(fixture(status: .played, score: Score(us: 3, them: 1)), existing: [stored()])
    #expect(played.state == .changed && played.draft?.status == .played && played.draft?.score == Score(us: 3, them: 1))
    // Another opponent on the same day.
    let other = make(fixture("Valdorso"), existing: [stored()])
    #expect(other.state == .changed && other.draft?.opponentID == valdorso.id)
  }

  @Test func venueRules() {
    // Kept when home/away does not change.
    #expect(make(fixture(), existing: [stored(venue: "Campo B")]).draft?.venue == "Campo B")
    #expect(
      make(fixture(home: false), existing: [stored(home: false, venue: "Campo Valdorso")]).draft?.venue
        == "Campo Valdorso")
    // Filled when empty, reset when home/away changes.
    #expect(make(fixture(), existing: [stored(venue: "")]).draft?.venue == "Campo Comunale")
    let nowAway = make(fixture(home: false), existing: [stored(home: true, venue: "Campo Comunale")])
    #expect(nowAway.draft?.venue == "" && nowAway.isVenueMissing && nowAway.state == .changed)
    #expect(make(fixture(home: true), existing: [stored(home: false, venue: "Fuori")]).draft?.venue == "Campo Comunale")
  }

  @Test func halfTimeKeptOnlyForPlayedMatches() {
    let half = Score(us: 1, them: 0)
    let played = make(
      fixture(status: .played, score: Score(us: 2, them: 1)),
      existing: [stored(status: .played, halfTime: half)])
    #expect(played.draft?.halfTime == half)
    let postponed = make(fixture(status: .postponed), existing: [stored(status: .played, halfTime: half)])
    #expect(postponed.draft?.halfTime == nil && postponed.draft?.score == nil)
  }

  // MARK: A typed result is never erased (T4.5, C3)

  @Test func fixtureWithoutScoreKeepsTheTypedResult() throws {
    let score = Score(us: 2, them: 1)
    let half = Score(us: 1, them: 0)
    // Sunday evening: the user typed the result, the source still says "da giocare".
    let scheduled = make(fixture(), existing: [stored(status: .played, score: score, halfTime: half)])
    #expect(scheduled.state == .unchanged)
    let draft = try #require(scheduled.draft)
    #expect(draft.score == score && draft.halfTime == half && draft.status == .played)
    // A half-time score typed on a match still scheduled is kept with its status.
    let halfTyped = make(fixture(), existing: [stored(status: .scheduled, score: score, halfTime: half)])
    #expect(halfTyped.state == .unchanged && halfTyped.draft?.status == .scheduled)
    // The source already says played but has no score yet.
    let playedNoScore = make(
      fixture(status: .played), existing: [stored(status: .played, score: score, halfTime: half)])
    #expect(playedNoScore.state == .unchanged && playedNoScore.draft?.score == score)
    // Other differences still show: the row is changed, the result kept.
    let later = make(
      fixture(time: ClockTime(hour: 16, minute: 0)), existing: [stored(status: .played, score: score, halfTime: half)])
    #expect(later.state == .changed && later.draft?.score == score && later.draft?.halfTime == half)
  }

  @Test func fixtureScoreWinsOverTheTypedOne() {
    let half = Score(us: 1, them: 0)
    let candidate = make(
      fixture(status: .played, score: Score(us: 3, them: 1)),
      existing: [stored(status: .played, score: Score(us: 2, them: 1), halfTime: half)])
    #expect(candidate.state == .changed)
    #expect(candidate.draft?.score == Score(us: 3, them: 1) && candidate.draft?.halfTime == half)
    #expect(candidate.draft?.status == .played)
  }

  @Test(arguments: [MatchStatus.postponed, .cancelled])
  func postponedOrCancelledFixtureClearsTheTypedResult(_ status: MatchStatus) {
    let candidate = make(
      fixture(status: status),
      existing: [stored(status: .played, score: Score(us: 2, them: 1), halfTime: Score(us: 1, them: 0))])
    #expect(candidate.state == .changed && candidate.draft?.status == status)
    #expect(candidate.draft?.score == nil && candidate.draft?.halfTime == nil)
  }

  @Test(arguments: [MatchStatus.scheduled, .played])
  func fixtureWithoutScoreKeepsATypedHalfTimeAlone(_ status: MatchStatus) {
    let half = Score(us: 1, them: 0)
    // Stored as scheduled with only the half-time typed: nothing changes.
    let scheduled = make(fixture(status: status), existing: [stored(status: .scheduled, halfTime: half)])
    #expect(scheduled.draft?.halfTime == half && scheduled.draft?.score == nil)
    #expect(scheduled.draft?.status == status && scheduled.state == (status == .scheduled ? .unchanged : .changed))
    // The status still follows the fixture: a half-time alone does not protect it.
    let played = make(fixture(status: status), existing: [stored(status: .played, halfTime: half)])
    #expect(played.draft?.halfTime == half && played.draft?.status == status)
  }

  @Test func fixtureScoreWinsOverATypedHalfTimeAlone() {
    let half = Score(us: 1, them: 0)
    let candidate = make(
      fixture(status: .played, score: Score(us: 2, them: 0)), existing: [stored(status: .scheduled, halfTime: half)])
    #expect(candidate.state == .changed && candidate.draft?.status == .played)
    #expect(candidate.draft?.score == Score(us: 2, them: 0) && candidate.draft?.halfTime == half)
  }

  @Test(arguments: [MatchStatus.postponed, .cancelled])
  func postponedOrCancelledFixtureClearsATypedHalfTimeAlone(_ status: MatchStatus) {
    let candidate = make(
      fixture(status: status), existing: [stored(status: .scheduled, halfTime: Score(us: 1, them: 0))])
    #expect(candidate.state == .changed && candidate.draft?.status == status)
    #expect(candidate.draft?.score == nil && candidate.draft?.halfTime == nil)
  }

  @Test func withoutAStoredResultTheFixtureIsTaken() {
    let plain = make(fixture(status: .played, score: Score(us: 1, them: 1)), existing: [stored()])
    #expect(plain.state == .changed && plain.draft?.score == Score(us: 1, them: 1))
  }

  @Test func reviewReasons() {
    let unknown = make(fixture("Atletico Nuovo Borgo"))
    #expect(unknown.state == .needsReview && unknown.reviewReasons == [.opponentNotFound])
    #expect(unknown.draft == nil && unknown.opponent == nil && !unknown.isVenueMissing)
    #expect(unknown.reviewMessages == [CoreStrings.reviewOpponentNotFound("Atletico Nuovo Borgo")])

    let status = make(fixture(status: nil), existing: [stored()])
    #expect(status.state == .needsReview && status.reviewReasons == [.unknownStatus] && status.draft == nil)
    #expect(status.reviewMessages.first?.contains("Partita sospesa") == true)

    let twin = Opponent(id: "o4", name: "Valdorso")
    let ambiguous = ImportCandidate.make(
      fixture: fixture("Valdorso", status: nil), team: team, opponents: opponents + [twin], existingMatches: [],
      homeVenue: "")
    #expect(ambiguous.reviewReasons == [.opponentAmbiguous, .unknownStatus])
    // Linking resolves it.
    let linked = ImportCandidate.make(
      fixture: fixture("Valdorso"), team: team, opponents: opponents + [twin], existingMatches: [], homeVenue: "",
      linkedOpponentID: "o4")
    #expect(linked.state == .new && linked.opponent == twin && linked.draft?.opponentID == "o4")
  }

  @Test func lockedWins() {
    let locked = make(fixture(time: ClockTime(hour: 16, minute: 0)), existing: [stored(locked: true)])
    #expect(locked.state == .locked && locked.draft?.isLocked == true && locked.draft?.time?.value == "16:00")
    let lockedUnknown = make(fixture("Atletico Nuovo Borgo"), existing: [stored(locked: true)])
    #expect(lockedUnknown.state == .locked && lockedUnknown.reviewReasons.isEmpty && lockedUnknown.draft == nil)
  }

  @Test func onlyTheSameTeamAndDayIsExisting() {
    var otherDay = stored()
    otherDay.match.date = sunday.adding(days: -1)
    var otherTeam = stored()
    otherTeam.match.teamID = "another"
    #expect(make(fixture(), existing: [otherDay, otherTeam]).state == .new)
  }

  @Test func draftsPassValidation() throws {
    for candidate in [make(fixture()), make(fixture(home: false)), make(fixture(), existing: [stored()])] {
      let draft = try #require(candidate.draft)
      #expect(draft.validate().isEmpty)
    }
  }

  // MARK: Report

  @Test func issueMessages() {
    let team = "Juniores"
    let reasons: [FixtureFetchError] = [
      .missingWidgetID, .network, .timeout, .httpStatus(503), .responseTooLarge, .notAllowed, .unavailable,
    ]
    for reason in reasons {
      let issue = ImportIssue.fetchFailed(team: team, reason: reason)
      #expect(issue.message.hasPrefix("Tuttocampo: impossibile leggere i risultati di Juniores."))
      #expect(issue.isError)
    }
    #expect(ImportIssue.fetchFailed(team: team, reason: .httpStatus(503)).message.contains("503"))
    let changed = ImportIssue.sourceProblem(team: team, problem: .structureChanged, clubShortName: "Sergnanese")
    #expect(changed.message.contains("La sorgente potrebbe essere cambiata") && changed.isError)
    let none = ImportIssue.sourceProblem(team: team, problem: .noFixturesOfOurs, clubShortName: "Sergnanese")
    #expect(none.message.contains("nessuna partita della Sergnanese trovata per Juniores") && none.isError)
    let later = ImportIssue.notYetAvailable(team: team)
    #expect(later.message.contains("risultati non ancora disponibili per Juniores") && !later.isError)
    #expect(ImportIssue.logoNotRecognised(opponent: "Valdorso").isError)
    #expect(!ImportIssue.logoFallback(opponent: "Valdorso").isError)
    #expect(ImportIssue.logoFailed(opponent: "Valdorso").isError)
    for issue in [
      ImportIssue.logoNotRecognised(opponent: "Valdorso"), .logoFallback(opponent: "Valdorso"),
      .logoFailed(opponent: "Valdorso"),
    ] {
      #expect(issue.message.contains("Valdorso"))
    }
  }

  @Test func logoRequestFromFixture() {
    let request = LogoRequest(opponent: gerolamo, fixture: fixture())
    #expect(request.opponentID == "o1" && request.opponentName == gerolamo.name && request.clubID == "900101")
    #expect(request.fallbackURL?.absoluteString == "https://b2-content.tuttocampo.it/Teams/40/900101.png?v=1")
  }

  // MARK: Placeholder source

  @Test func containersWithoutASourceSayUnavailable() async throws {
    let source = UnavailableFixtureSource()
    await #expect(throws: FixtureFetchError.unavailable) {
      try await source.fetchFixtures(for: team, settings: .defaults)
    }
    let request = LogoRequest(opponentID: "o1", opponentName: "Valdorso", clubID: "1", fallbackURL: nil)
    #expect(
      await source.downloadLogos([request])
        == [LogoResult(request: request, fileName: nil, issue: .logoFailed(opponent: "Valdorso"))])
  }
}

// MARK: - LogoStore default

/// A store that implements only the original requirements, to exercise the protocol's default
/// `importLogo(data:fileName:replacing:)`.
struct MinimalLogoStore: LogoStore {
  let folder: URL

  func importLogo(from url: URL, replacing: String?) async throws -> String {
    try await importLogo(data: Data(contentsOf: url), replacing: replacing)
  }

  func importLogo(data: Data, replacing: String?) async throws -> String {
    guard !data.isEmpty else { throw AppError.validation(field: .logo, message: "vuoto") }
    let name = "\(UUID().uuidString.lowercased()).png"
    try data.write(to: url(for: name))
    if let replacing { try remove(fileName: replacing) }
    return name
  }

  func remove(fileName: String) throws {
    try? FileManager.default.removeItem(at: url(for: fileName))
  }

  func url(for fileName: String) -> URL { folder.appendingPathComponent(fileName) }
}

@Suite struct LogoStoreDefaultTests {
  func contents(_ folder: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
  }

  @Test(arguments: [false, true])
  func storesUnderTheChosenName(fake: Bool) async throws {
    let paths = try AppPaths.temporary()
    let store: any LogoStore = fake ? FakeLogoStore(folder: paths.logos) : MinimalLogoStore(folder: paths.logos)
    let png = FakeFixtureSource.defaultLogoData
    #expect(try await store.importLogo(data: png, fileName: "917410.png", replacing: nil) == "917410.png")
    #expect(try contents(paths.logos) == ["917410.png"])
    // Same name again: replaced, still one file.
    let replacement = png + Data([0])
    _ = try await store.importLogo(data: replacement, fileName: "917410.png", replacing: nil)
    #expect(try contents(paths.logos) == ["917410.png"])
    #expect(try Data(contentsOf: store.url(for: "917410.png")) == replacement)
    // `replacing` removes the old file once the new one is stored, unless it is the same name.
    let manual = try await store.importLogo(data: png, replacing: nil)
    _ = try await store.importLogo(data: png, fileName: "123.png", replacing: manual)
    #expect(try contents(paths.logos) == ["123.png", "917410.png"])
    _ = try await store.importLogo(data: png, fileName: "123.png", replacing: "123.png")
    #expect(try contents(paths.logos) == ["123.png", "917410.png"])
  }

  @Test(arguments: [false, true])
  func refusesNamesThatAreNotDigits(fake: Bool) async throws {
    let paths = try AppPaths.temporary()
    let store: any LogoStore = fake ? FakeLogoStore(folder: paths.logos) : MinimalLogoStore(folder: paths.logos)
    for bad in ["../917410.png", "917410.jpg", "abc.png", ""] {
      await #expect(throws: AppError.self) {
        try await store.importLogo(data: FakeFixtureSource.defaultLogoData, fileName: bad, replacing: nil)
      }
    }
    #expect(try contents(paths.logos).isEmpty)
  }
}
