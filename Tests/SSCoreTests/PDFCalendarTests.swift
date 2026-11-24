import Foundation
import SSCoreFakes
import Testing

@testable import SSCore

@Suite struct PDFCalendarTests {
  let saturday = DayDate(year: 2026, month: 10, day: 10)!
  let team = Team(id: "team", name: "Femminile", shortLabel: "Femm.", sortOrder: 1, isFirstTeam: false, isActive: true)
  let bernardo = Opponent(id: "o1", name: "San Bernardo Calcio")
  let alcione = Opponent(id: "o2", name: "Alcione", aliases: ["Alcione Milano"])

  func calendar(category: String = "ESORDIENTI MISTE FEMM. AUT.", phase: String = "FASE AUTUNNALE") -> PDFCalendar {
    PDFCalendar(
      category: category, phase: phase, girone: "GIRONE B", matchdays: [], clubs: [], fixtures: [], byes: [8],
      problems: [
        .unreadableRow(matchday: 3, text: "ALFA BETA"), .clubNotLinked(name: "GAMMA"), .incomplete(teams: 9, clubs: 8),
      ])
  }

  func fixture(
    _ name: String = "S. BERNARDO CALCIO", aliases: [String] = ["SAN BERNARDO CALCIO"], home: Bool = false,
    competition: String? = "ESORDIENTI – FASE AUTUNNALE – GIRONE B", scheduleUnknown: Bool = false
  ) -> FetchedFixture {
    FetchedFixture(
      date: saturday.adding(days: 1), time: ClockTime(hour: 9, minute: 30), isHome: home, opponentName: name,
      round: 2, status: .scheduled, statusText: "", venue: home ? nil : "C.S. COMUNALE, VIA ESEMPIO 4",
      opponentAliases: aliases, competition: competition, scheduleUnknown: scheduleUnknown)
  }

  func stored(competition: String?, locked: Bool = false) -> MatchDetail {
    let date = Date(timeIntervalSince1970: 0)
    let match = Match(
      id: "m1", teamID: team.id, opponentID: bernardo.id, date: saturday.adding(days: 1), time: nil, isHome: false,
      venue: "Campo vecchio", competition: competition, round: 2, status: .scheduled, source: .manual,
      isLocked: locked, createdAt: date, updatedAt: date)
    return MatchDetail(match: match, team: team, opponent: bernardo)
  }

  func make(
    _ fixture: FetchedFixture, opponents: [Opponent]? = nil, existing: [MatchDetail] = [],
    source: MatchSource = .pdf
  ) -> ImportCandidate {
    ImportCandidate.make(
      fixture: fixture, team: team, opponents: opponents ?? [bernardo, alcione], existingMatches: existing,
      homeVenue: "Campo Comunale", source: source)
  }

  // MARK: Calendar helpers

  @Test func competitionJoinsTitleParts() {
    #expect(calendar().competition == "ESORDIENTI MISTE FEMM. AUT. – FASE AUTUNNALE – GIRONE B")
    #expect(calendar(category: "  ESORDIENTI   MISTI ", phase: "").competition == "ESORDIENTI MISTI – GIRONE B")
    let long = calendar(category: String(repeating: "CATEGORIA ", count: 8)).competition
    #expect(long.count <= FieldLimits.competition && long.hasSuffix("…"))
  }

  @Test func homeDayGivesTheMatchDate() {
    #expect(PDFCalendar.HomeDay.saturday.matchDate(saturday: saturday) == saturday)
    #expect(PDFCalendar.HomeDay.sunday.matchDate(saturday: saturday) == DayDate(year: 2026, month: 10, day: 11))
  }

  @Test func clubMatchVenueJoinsVenueAndAddress() {
    func club(_ venue: String, _ address: String) -> PDFCalendar.Club {
      PDFCalendar.Club(
        fullName: "ALFA", number: nil, venue: venue, address: address, time: nil, homeDay: nil, shortName: nil)
    }
    #expect(club("C.S.COMUNALE N.1 -  PAESE", " VIA ESEMPIO 4").matchVenue == "C.S.COMUNALE N.1 - PAESE, VIA ESEMPIO 4")
    #expect(club("CAMPO", "").matchVenue == "CAMPO")
    #expect(club("", "VIA ESEMPIO").matchVenue == "VIA ESEMPIO")
  }

  @Test func calendarRoundTripsThroughJSON() throws {
    let scenario = FakePDFCalendarParser.scenarioCalendar(referenceSaturday: DayDate(year: 2026, month: 11, day: 21)!)
    #expect(try JSONDecoder().decode(PDFCalendar.self, from: JSONEncoder().encode(scenario)) == scenario)
    #expect(try JSONDecoder().decode(PDFCalendar.self, from: JSONEncoder().encode(calendar())) == calendar())
  }

  @Test func newFixtureFieldsAreOptionalInJSON() throws {
    let full = fixture(scheduleUnknown: true)
    #expect(try JSONDecoder().decode(FetchedFixture.self, from: JSONEncoder().encode(full)) == full)
    var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(full)) as? [String: Any])
    for key in ["venue", "opponentAliases", "competition", "scheduleUnknown"] { object[key] = nil }
    let old = try JSONDecoder().decode(FetchedFixture.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(old.opponentAliases.isEmpty && old.competition == nil && !old.scheduleUnknown && old.venue == nil)
    #expect(old.opponentName == full.opponentName && old.time == full.time && old.date == full.date)
  }

  // MARK: Opponent names

  @Test func newOpponentDraftKeepsDistinctAliases() {
    let draft = fixture(aliases: ["SAN BERNARDO CALCIO", "san  bernardo calcio", "A.S.D. S. Bernardo Calcio", ""])
      .newOpponentDraft
    #expect(draft == OpponentDraft(name: "S. BERNARDO CALCIO", aliases: ["SAN BERNARDO CALCIO"]))
    let long = String(repeating: "x", count: FieldLimits.alias + 1)
    #expect(fixture(aliases: [long]).newOpponentDraft.aliases.isEmpty)
    let longName = fixture(String(repeating: "Nome ", count: 20), aliases: []).newOpponentDraft
    #expect(longName.name.count <= FieldLimits.opponentName && longName.name.hasSuffix("…"))
    #expect(fixture("Real  Meda", aliases: []).newOpponentDraft == OpponentDraft(name: "Real Meda"))
  }

  @Test func linkingAddsOnlyUnknownNames() {
    let added = alcione.draftAddingImportNames(of: fixture("ALCIONE", aliases: ["ALCIONE MILANO SSD A RL"]))
    #expect(added.aliases == ["Alcione Milano", "ALCIONE MILANO SSD A RL"])
    #expect(added.name == "Alcione")
    let both = bernardo.draftAddingImportNames(of: fixture())
    #expect(both.aliases == ["S. BERNARDO CALCIO"])  // the full name already is the opponent's name
    let nothing = alcione.draftAddingImportNames(of: fixture("Alcione Milano", aliases: ["ALCIONE"]))
    #expect(nothing == OpponentDraft(alcione))
    let csi = bernardo.draftAddingImportNames(of: fixture("Bernardo", aliases: []))
    #expect(csi.aliases == ["Bernardo"])
  }

  // MARK: Staging

  @Test func opponentFoundThroughAnAlias() {
    let candidate = make(fixture())
    #expect(candidate.opponent == bernardo && candidate.state == .new)
    #expect(candidate.draft?.source == .pdf)
    #expect(candidate.draft?.venue == "C.S. COMUNALE, VIA ESEMPIO 4")
    #expect(candidate.draft?.competition == "ESORDIENTI – FASE AUTUNNALE – GIRONE B")
    #expect(candidate.draft?.time == ClockTime(hour: 9, minute: 30) && candidate.draft?.round == 2)
  }

  @Test func theNameWinsOverAliases() {
    let short = Opponent(id: "o3", name: "S. Bernardo Calcio")
    #expect(make(fixture(), opponents: [bernardo, short]).opponent == short)
  }

  @Test func aliasesMatchingSeveralOpponentsAreAmbiguous() {
    let twin = Opponent(id: "o3", name: "Bernardo", aliases: ["San Bernardo Calcio"])
    let candidate = make(fixture(), opponents: [twin, bernardo])
    #expect(candidate.state == .needsReview && candidate.reviewReasons == [.opponentAmbiguous])
    let twice = make(fixture(aliases: ["SAN BERNARDO CALCIO", "A.S.D. San Bernardo Calcio"]), opponents: [bernardo])
    #expect(twice.opponent == bernardo)
    #expect(make(fixture(aliases: []), opponents: [bernardo]).reviewReasons == [.opponentNotFound])
  }

  @Test func sourceDefaultsToScrape() {
    #expect(make(fixture(), source: .scrape).draft?.source == .scrape)
    let tuttocampo = ImportCandidate.make(
      fixture: fixture(), team: team, opponents: [bernardo], existingMatches: [], homeVenue: "Campo Comunale")
    #expect(tuttocampo.draft?.source == .scrape)
  }

  @Test func competitionFillsOnlyAnEmptyOne() {
    #expect(make(fixture(), existing: [stored(competition: nil)]).draft?.competition == fixture().competition)
    #expect(make(fixture(), existing: [stored(competition: " ")]).draft?.competition == fixture().competition)
    #expect(make(fixture(), existing: [stored(competition: "Coppa")]).draft?.competition == "Coppa")
    #expect(make(fixture(competition: nil)).draft?.competition == nil)
    let long = make(fixture(competition: String(repeating: "Girone ", count: 12))).draft?.competition ?? ""
    #expect(long.count <= FieldLimits.competition)
    let home = make(fixture(home: true))
    #expect(home.draft?.venue == "Campo Comunale" && home.draft?.isHome == true)
  }

  @Test func unknownScheduleNeedsReview() {
    let candidate = make(fixture(scheduleUnknown: true))
    #expect(candidate.state == .needsReview && candidate.draft == nil)
    #expect(candidate.reviewReasons == [.scheduleUnknown])
    #expect(candidate.reviewMessages == [CoreStrings.reviewScheduleUnknown("S. BERNARDO CALCIO")])
    let both = make(fixture("GAMMA", aliases: [], scheduleUnknown: true))
    #expect(both.reviewReasons == [.opponentNotFound, .scheduleUnknown])
    let locked = make(fixture(scheduleUnknown: true), existing: [stored(competition: nil, locked: true)])
    #expect(locked.state == .locked && locked.reviewReasons.isEmpty && locked.draft == nil)
  }

  // MARK: Report

  @Test func noticesFollowProblemsThenByes() {
    #expect(
      ImportIssue.pdfNotices(for: calendar()) == [
        .pdfUnreadableRow(matchday: 3, text: "ALFA BETA"), .pdfClubNotLinked(name: "GAMMA"),
        .pdfIncomplete(teams: 9, clubs: 8), .pdfBye(matchday: 8),
      ])
  }

  @Test func pdfMessages() {
    #expect(ImportIssue.pdfBye(matchday: 8).message == "Giornata 8: riposo.")
    #expect(!ImportIssue.pdfBye(matchday: 8).isError)
    let layout = ImportIssue.pdfReadFailed(file: "calendario.pdf", reason: .layoutNotRecognised)
    #expect(layout.message.hasPrefix("PDF: impossibile leggere «calendario.pdf». Formato PDF non riconosciuto"))
    #expect(ImportIssue.pdfReadFailed(file: "a.pdf", reason: .tooLarge).message.contains("10 MB e 20 pagine"))
    for reason in [PDFCalendarError.notAPDF, .tooLarge, .encrypted, .layoutNotRecognised, .unavailable] {
      let issue = ImportIssue.pdfReadFailed(file: "a.pdf", reason: reason)
      #expect(issue.isError && issue.message.count > CoreStrings.pdfReadFailed("a.pdf").count + 5)
    }
    #expect(ImportIssue.pdfIncomplete(teams: 9, clubs: 8).message.contains("9 squadre"))
    #expect(ImportIssue.pdfIncomplete(teams: 9, clubs: 8).isError)
    #expect(ImportIssue.pdfClubNotLinked(name: "GAMMA").message.contains("«GAMMA»"))
    #expect(ImportIssue.pdfUnreadableRow(matchday: 3, text: "ALFA BETA").message.contains("giornata 3"))
  }

  // MARK: Parsers

  @Test func defaultParserIsUnavailable() {
    #expect(throws: PDFCalendarError.unavailable) {
      try UnavailablePDFCalendarParser().parse(pdf: Data(), settings: .defaults)
    }
  }

  @Test func fakeParserGivesItsOutcome() throws {
    #expect(throws: PDFCalendarError.encrypted) {
      try FakePDFCalendarParser(failing: .encrypted).parse(pdf: Data(), settings: .defaults)
    }
    #expect(try FakePDFCalendarParser(calendar: calendar()).parse(pdf: Data([1]), settings: .defaults) == calendar())
  }
}

@MainActor
@Suite struct FakePDFCalendarParserTests {
  let services: AppServices
  let data: FakeDataSet

  init() throws {
    data = try Fixtures.dataSet().shifted(toWeekendOf: .today())
    services = try AppServices.fake(dataSet: data, renderDelay: .zero)
  }

  @Test func scenarioCoversTheReviewCases() throws {
    let settings = try services.settings.load()
    let calendar = try services.pdfCalendarParser.parse(pdf: Data(), settings: settings)
    let team = try #require(try services.teams.list().first { $0.name == "Femminile" })
    var opponents = try services.opponents.list()
    func stage(_ fixture: FetchedFixture) throws -> ImportCandidate {
      let existing = try services.matches.list(from: fixture.date, to: fixture.date, teamID: team.id)
      return ImportCandidate.make(
        fixture: fixture, team: team, opponents: opponents, existingMatches: existing, homeVenue: settings.homeVenue,
        source: .pdf)
    }
    let saturday = data.referenceSaturday
    #expect(calendar.matchdays.map(\.date) == [-7, 0, 7, 14, 21].map { saturday.adding(days: $0) })
    #expect(calendar.fixtures.map(\.date) == [1, 7, 14, 21].map { saturday.adding(days: $0) })
    let rows = try calendar.fixtures.map(stage)
    #expect(rows.map(\.state) == [.changed, .new, .needsReview, .needsReview])
    #expect(rows[0].opponent?.name == "G.S. Sant'Ilario Città")
    #expect(rows[0].draft?.time == ClockTime(hour: 10, minute: 30) && rows[0].draft?.isHome == false)
    #expect(rows[0].draft?.venue == "C.S. COMUNALE - SANT'ILARIO, VIA ROMA 10")
    #expect(rows[1].draft?.venue == settings.homeVenue && rows[1].draft?.time == ClockTime(hour: 17, minute: 30))
    #expect(rows[1].draft?.competition == "ESORDIENTI FEMMINILI – FASE AUTUNNALE – GIRONE A")
    #expect(rows[2].reviewReasons == [.opponentNotFound])
    #expect(rows[3].reviewReasons == [.opponentNotFound, .scheduleUnknown])
    #expect(ImportIssue.pdfNotices(for: calendar).last == .pdfBye(matchday: 1))
    #expect(ImportIssue.pdfNotices(for: calendar).count == 4)

    let created = try services.opponents.create(calendar.fixtures[2].newOpponentDraft)
    #expect(created.name == "AURORA PIANENGO" && created.aliases == ["A.S.D. AURORA PIANENGO 1990"])
    opponents = try services.opponents.list()
    let again = try stage(calendar.fixtures[2])
    #expect(again.state == .new && again.opponent?.id == created.id)
    #expect(again.draft?.venue == "ORATORIO AURORA - PIANENGO, VIA MANZONI 2" && again.draft?.source == .pdf)
  }
}
