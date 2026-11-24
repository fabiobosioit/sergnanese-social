import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

@MainActor
struct ImportModelPDFTests {
  static let today = try! DayDate("2026-11-18")  // a Wednesday: the fake data's reference Saturday is 21 November

  struct Fixture {
    var services: AppServices
    var team: Team
    var calendar: PDFCalendar
  }

  func makeFixture(parser: (any PDFCalendarParser)? = nil) throws -> Fixture {
    var services = AppServices.fake(today: Self.today)
    if let parser { services.pdfCalendarParser = parser }
    let team = try #require(try services.teams.list().first { $0.name == "Femminile" })
    let calendar = try services.pdfCalendarParser.parse(pdf: Data(), settings: try services.settings.load())
    return Fixture(services: services, team: team, calendar: calendar)
  }

  func makeModel(_ fixture: Fixture) -> ImportModel {
    let model = ImportModel(
      services: fixture.services,
      source: .pdf(team: fixture.team, calendar: fixture.calendar, fileName: "calendario.pdf"),
      today: { Self.today })
    model.stagePDF()
    return model
  }

  func candidate(_ model: ImportModel, _ opponent: String) throws -> ImportCandidate {
    try #require(model.candidates.first { $0.fixture.opponentName == opponent })
  }

  @Test func statesFollowTheScenarioTable() throws {
    let model = makeModel(try makeFixture())
    #expect(model.phase == .review)
    #expect(model.title == ImportStrings.titlePDF)
    let expected: [String: ImportCandidate.State] = [
      "S. ILARIO": .changed, "BORGO LUCENTE": .new, "AURORA PIANENGO": .needsReview, "NUOVA ESEMPIO": .needsReview,
    ]
    #expect(model.candidates.count == expected.count)
    for (name, state) in expected { #expect(try candidate(model, name).state == state, "\(name)") }
    let unknown = try candidate(model, "NUOVA ESEMPIO")
    #expect(unknown.reviewReasons.contains(.scheduleUnknown))
    #expect(unknown.draft == nil)
  }

  @Test func noticesComeInOrderWithTheByeLastAsInformation() throws {
    let model = makeModel(try makeFixture())
    #expect(model.issues.count == 4)
    #expect(model.issues.map(\.isError) == [true, true, true, false])
    #expect(model.issues.last == .pdfBye(matchday: 1))
  }

  @Test func onlyRowsFromTodayOnAreTicked() throws {
    let model = makeModel(try makeFixture())
    let ticked = Set(model.tickedCandidates.map(\.fixture.opponentName))
    #expect(ticked == ["S. ILARIO", "BORGO LUCENTE"])
  }

  @Test func pastRowsStartUnticked() throws {
    var fixture = try makeFixture()
    let late = try DayDate("2027-01-01")
    let calendar = FakePDFCalendarParser.scenarioCalendar(referenceSaturday: late)
    fixture.calendar = calendar
    let model = ImportModel(
      services: fixture.services, source: .pdf(team: fixture.team, calendar: calendar, fileName: "x.pdf"),
      today: { try! DayDate("2027-02-01") })
    model.stagePDF()
    #expect(model.tickedCandidates.isEmpty)
  }

  @Test func creatingAuroraSavesTheAliasAndTheRowBecomesNew() throws {
    let fixture = try makeFixture()
    let model = makeModel(fixture)
    model.createOpponent(for: try candidate(model, "AURORA PIANENGO"))
    let aurora = try candidate(model, "AURORA PIANENGO")
    #expect(aurora.state == .new)
    #expect(aurora.opponent?.aliases.contains("A.S.D. AURORA PIANENGO 1990") == true)
    #expect(model.isTicked(aurora))
  }

  @Test func linkingNuovaEsempioAddsTheAliasAndKeepsScheduleUnknown() throws {
    let fixture = try makeFixture()
    let model = makeModel(fixture)
    let target = try #require(try fixture.services.opponents.list().first)
    let row = try candidate(model, "NUOVA ESEMPIO")
    model.link(row, to: target)
    let linked = try candidate(model, "NUOVA ESEMPIO")
    #expect(linked.state == .needsReview)
    #expect(linked.reviewReasons == [.scheduleUnknown])
    let stored = try fixture.services.opponents.get(id: target.id)
    #expect(stored.aliases.contains("NUOVA ESEMPIO"))
  }

  @Test func commitWritesPDFMatchesWithTimesVenuesAndCompetition() async throws {
    let fixture = try makeFixture()
    let model = makeModel(fixture)
    await model.commit()
    #expect(model.phase == .done)
    let settings = try fixture.services.settings.load()
    let all = try fixture.services.matches.list(
      from: try DayDate("2026-11-01"), to: try DayDate("2027-01-31"), teamID: fixture.team.id)
    let ilario = try #require(all.first { $0.opponent.name == "G.S. Sant'Ilario Città" })
    #expect(ilario.match.source == .pdf)
    #expect(ilario.match.time == ClockTime(hour: 10, minute: 30))
    #expect(ilario.match.date == (try DayDate("2026-11-22")))
    #expect(ilario.match.venue == "C.S. COMUNALE - SANT'ILARIO, VIA ROMA 10")
    #expect(ilario.match.competition == fixture.calendar.competition)
    let borgo = try #require(all.first { $0.match.source == .pdf && $0.match.isHome })
    #expect(borgo.match.time == ClockTime(hour: 17, minute: 30))
    #expect(borgo.match.venue == settings.homeVenue)
    #expect(borgo.match.competition == fixture.calendar.competition)
    #expect(model.summaryText != nil)
  }

  @Test func changesListTheCompetition() throws {
    let model = makeModel(try makeFixture())
    let changes = model.changes(for: try candidate(model, "S. ILARIO"))
    #expect(changes.contains { $0.hasPrefix("\(ImportStrings.changeCompetition):") })
  }

  @Test func anEmptyCalendarSaysSoAndKeepsTheNotices() throws {
    var fixture = try makeFixture()
    fixture.calendar.fixtures = []
    let model = makeModel(fixture)
    #expect(model.candidates.isEmpty)
    #expect(model.emptyDescription.contains("Sergnanese"))
    #expect(model.issues.count == 4)
  }

  // MARK: Launcher

  func tempFile(named name: String, size: Int = 16) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(name)
    FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0x25, count: size))
    return url
  }

  @Test func aReadableFileShowsThePickerThenTheStaging() async throws {
    let services = AppServices.fake(today: Self.today)
    let launcher = PDFImportLauncher(services: services, today: { Self.today })
    let url = try tempFile(named: "calendario.pdf")
    await launcher.begin(url: url)
    #expect(launcher.isPickerPresented)
    #expect(launcher.calendar?.competition.contains("FEMMINILI") == true)
    launcher.pickedTeamID = nil
    launcher.confirmPick()
    #expect(launcher.model == nil)  // nothing happens without a team
    launcher.pickedTeamID = try #require(try services.teams.list().first { $0.name == "Femminile" }).id
    launcher.confirmPick()
    #expect(launcher.isPickerPresented == false)
    #expect(launcher.model?.isPresented == true)
    #expect(launcher.model?.candidates.count == 4)
  }

  @Test func theTeamChosenLastIsPreselectedNextTime() async throws {
    let services = AppServices.fake(today: Self.today)
    let memory = PDFImportLauncher.TeamMemory()
    let first = PDFImportLauncher(services: services, memory: memory, today: { Self.today })
    let url = try tempFile(named: "a.pdf")
    await first.begin(url: url)
    let team = try #require(first.teams.last)
    first.pickedTeamID = team.id
    first.confirmPick()
    let second = PDFImportLauncher(services: services, memory: memory, today: { Self.today })
    await second.begin(url: url)
    #expect(second.pickedTeamID == team.id)
  }

  @Test func aParserErrorShowsOnlyTheReportLine() async throws {
    var services = AppServices.fake(today: Self.today)
    services.pdfCalendarParser = FakePDFCalendarParser(failing: .layoutNotRecognised)
    let launcher = PDFImportLauncher(services: services, today: { Self.today })
    await launcher.begin(url: try tempFile(named: "strano.pdf"))
    let model = try #require(launcher.model)
    #expect(launcher.isPickerPresented == false)
    #expect(model.candidates.isEmpty)
    #expect(model.issues.count == 1)
    #expect(model.issues[0].message.contains("Formato PDF non riconosciuto"))
    #expect(model.issues[0].message.contains("strano.pdf"))
    #expect(model.showsEmptyState == false)
  }

  @Test func aFileOverTheLimitIsRefusedWithoutCallingTheParser() async throws {
    var services = AppServices.fake(today: Self.today)
    // If the parser were called it would say .unavailable; the size check must answer first.
    services.pdfCalendarParser = FakePDFCalendarParser(failing: .unavailable)
    let launcher = PDFImportLauncher(services: services, today: { Self.today })
    let url = try tempFile(named: "grande.pdf", size: 0)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: UInt64(PDFCalendar.maxFileSize + 1))
    try handle.close()
    await launcher.begin(url: url)
    let model = try #require(launcher.model)
    #expect(model.issues == [.pdfReadFailed(file: "grande.pdf", reason: .tooLarge)])
  }

  @Test func droppingAPDFStartsTheFlowAndAPNGDoesNothing() async throws {
    let services = AppServices.fake(today: Self.today)
    let launcher = PDFImportLauncher(services: services, today: { Self.today })
    #expect(launcher.handleDrop([try tempFile(named: "logo.png")]) == false)
    #expect(launcher.isReading == false)
    #expect(launcher.handleDrop([try tempFile(named: "logo.png"), try tempFile(named: "c.pdf")]))
  }

  @Test func theCommandIsDisabledWithoutAnActiveTeam() throws {
    let services = AppServices.fake(today: Self.today)
    for team in try services.teams.list() {
      var draft = TeamDraft(team)
      draft.isActive = false
      _ = try services.teams.update(id: team.id, with: draft)
    }
    let launcher = PDFImportLauncher(services: services, today: { Self.today })
    launcher.refresh()
    #expect(launcher.canStart == false)
    #expect(launcher.unavailableReason == ImportStrings.noTeamReasonPDF)
    launcher.chooseFile()
    #expect(launcher.isFileImporterPresented == false)
  }
}
