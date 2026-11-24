import Foundation
import SSCore
import Testing

@testable import SSImport

private let competition = "ESORDIENTI MISTE FEMM. AUT. – FASE AUTUNNALE – GIRONE B"

private func parse(_ name: String, club: String = "Sergnanese") throws -> PDFCalendar {
  try FederationPDFParser().parse(pdf: pdfFixture(name), settings: pdfSettings(club: club))
}

/// A fixture as the parser documents it, with the fields every one of them shares.
private func fixture(
  _ date: String, _ time: String?, home: Bool, against opponent: String, round: Int, venue: String? = nil,
  aliases: [String] = [], scheduleUnknown: Bool = false
) -> FetchedFixture {
  FetchedFixture(
    date: day(date), time: time.map(clock), isHome: home, opponentName: opponent, round: round, status: .scheduled,
    statusText: "", venue: venue, opponentAliases: aliases, competition: competition,
    scheduleUnknown: scheduleUnknown)
}

/// The ground truth written by the fixture generator.
private struct Expected: Decodable {
  struct Match: Decodable {
    var home: String
    var away: String
  }
  struct Matchday: Decodable {
    var number: Int
    var date: String
    var matches: [Match]
    var rest: String
  }
  struct Club: Decodable {
    var short: String
    var long: String
    var number: Int
    var ground: String?
    var address: String?
    var time: String?
    var day: String?
  }
  var category: String
  var phase: String
  var girone: String
  var matchdays: [Matchday]
  var clubs: [Club]
}

private func expected(_ name: String) throws -> Expected {
  try JSONDecoder().decode(Expected.self, from: pdfFixture(name))
}

@Suite("Federation PDF parser: the sample calendar")
struct FederationPDFSampleTests {
  @Test("title, matchdays and every club row with every column, all names linked")
  func structure() throws {
    let calendar = try parse("calendar-sample.pdf")
    let truth = try expected("calendar-sample.expected.json")

    #expect(calendar.category == truth.category)
    #expect(calendar.phase == "FASE AUTUNNALE")
    #expect(calendar.girone == truth.girone)
    #expect(calendar.competition == competition)

    #expect(calendar.matchdays.count == 9)
    for (matchday, wanted) in zip(calendar.matchdays, truth.matchdays) {
      #expect(matchday.number == wanted.number)
      #expect(matchday.leg == .andata)
      #expect(matchday.date.value == wanted.date)
      #expect(matchday.date.isoWeekday == 6)
    }

    #expect(calendar.clubs.count == truth.clubs.count)
    let rows = Dictionary(uniqueKeysWithValues: calendar.clubs.map { ($0.fullName, $0) })
    for wanted in truth.clubs {
      let row = try #require(rows[wanted.long], "no row for \(wanted.long)")
      #expect(row.number == String(wanted.number))
      #expect(row.venue == wanted.ground)
      #expect(row.address == wanted.address)
      #expect(row.time == wanted.time.flatMap { try? ClockTime($0) })
      #expect(row.homeDay == (wanted.day == "Domenica" ? .sunday : .saturday))
      #expect(row.shortName == wanted.short)
    }
    // The table order is kept (sorted by long name in the file).
    #expect(calendar.clubs.map(\.fullName) == truth.clubs.map(\.long).sorted())
    #expect(calendar.problems.isEmpty)
  }

  @Test("the three kinds of short name are linked: the S. name, the squad letter, the prefix of its long name")
  func linkedNames() throws {
    let calendar = try parse("calendar-sample.pdf")
    func shortName(of full: String) -> String? { calendar.clubs.first { $0.fullName == full }?.shortName }
    #expect(shortName(of: "SAN ESEMPIO CALCIO") == "S. ESEMPIO CALCIO")
    #expect(shortName(of: "REAL ESEMPIO CF sq.B") == "REAL ESEMPIO CF Sq.B")
    #expect(shortName(of: "ESEMPIO UNO MILANO SSD A RL") == "ESEMPIO UNO")
    #expect(shortName(of: "ESEMPIO SEI A R.L.") == "ESEMPIO SEI")
    #expect(shortName(of: "SERGNANESE A.S.D.") == "SERGNANESE")
    #expect(calendar.clubs.allSatisfy { $0.shortName != nil })
  }

  @Test("our fixtures, one by one")
  func ourFixtures() throws {
    let calendar = try parse("calendar-sample.pdf")
    let wanted = [
      // Away at a Sabato club, the opponent's page-1 name is its full name: no alias.
      fixture(
        "2026-10-03", "14:30", home: false, against: "ESEMPIO TRE 1970", round: 1,
        venue: "STADIO COMUNALE\"E.TRE\"(E.A) - CITTATRE, VIA ESEMPIO N.3"),
      fixture(
        "2026-10-17", "16:00", home: false, against: "ESEMPIO UNO", round: 3,
        venue: "CAMPO \"ESEMPIO UNO\" - CITTAUNO, VIA ESEMPIO, 1", aliases: ["ESEMPIO UNO MILANO SSD A RL"]),
      // At home: our time, no venue (the app uses the Settings home venue).
      fixture("2026-10-24", "15:30", home: true, against: "ESEMPIO SEI", round: 4, aliases: ["ESEMPIO SEI A R.L."]),
      fixture("2026-10-31", "15:30", home: true, against: "ESEMPIO QUATTRO 1911", round: 5),
      fixture("2026-11-07", "15:30", home: true, against: "ESEMPIO DUE", round: 6, aliases: ["ESEMPIO DUE S.P.A."]),
      fixture("2026-11-14", "15:30", home: true, against: "WOMEN ESEMPIO", round: 7),
      fixture(
        "2026-11-21", "15:30", home: true, against: "S. ESEMPIO CALCIO", round: 8, aliases: ["SAN ESEMPIO CALCIO"]),
      fixture(
        "2026-11-28", "15:30", home: true, against: "REAL ESEMPIO CF Sq.B", round: 9,
        aliases: ["REAL ESEMPIO CF sq.B"]),
    ]
    #expect(calendar.fixtures.count == wanted.count)
    for (got, want) in zip(calendar.fixtures, wanted) {
      #expect(got == want, "round \(want.round ?? 0)")
    }
    // No fixture on our bye, and the bye is recorded.
    #expect(!calendar.fixtures.contains { $0.round == 2 })
    #expect(calendar.byes == [2])
  }

  @Test("a match at the Domenica club is played the day after the printed Saturday")
  func sundayAway() throws {
    // Esempio Due plays away at Esempio Sei (Domenica, 9.30) on matchday 7, printed 14/11/2026.
    let calendar = try parse("calendar-sample.pdf", club: "Esempio Due")
    let match = try #require(calendar.fixtures.first { $0.round == 7 })
    #expect(match.date.value == "2026-11-15")
    #expect(match.date.isoWeekday == 7)
    #expect(match.time == clock("09:30"))
    #expect(!match.isHome)
    #expect(match.opponentName == "ESEMPIO SEI")
    #expect(match.venue == "C.S.COMUNALE CAMPO 2 E.A. - CITTASEI FRAZ. ESEMPIO, VIA ESEMPIO SEI")
    #expect(match.opponentAliases == ["ESEMPIO SEI A R.L."])
    #expect(!match.scheduleUnknown)
  }

  @Test("a Domenica club at home: its own day and time, no venue")
  func sundayHome() throws {
    let calendar = try parse("calendar-sample.pdf", club: "Esempio Sei")
    let match = try #require(calendar.fixtures.first { $0.round == 6 })
    #expect(match.date.value == "2026-11-08")
    #expect(match.time == clock("09:30"))
    #expect(match.isHome)
    #expect(match.venue == nil)
    // Its bye is on matchday 3.
    #expect(calendar.byes == [3])
  }

  @Test("the settings' club short name picks the club: the same file gives that club's matches")
  func otherClub() throws {
    let ours = try parse("calendar-sample.pdf")
    let other = try parse("calendar-sample.pdf", club: "Women Esempio")
    #expect(other.fixtures.count == 8)
    #expect(other.fixtures.map(\.opponentName) != ours.fixtures.map(\.opponentName))
    #expect(other.byes == [6])
    // Legal prefixes and case do not matter.
    let written = try parse("calendar-sample.pdf", club: "A.S.D. sergnanese")
    #expect(written.fixtures == ours.fixtures)
    // A club that is not in the calendar: nothing of ours, the rest is returned as it is.
    let absent = try parse("calendar-sample.pdf", club: "Altra Squadra")
    #expect(absent.fixtures.isEmpty)
    #expect(absent.byes.isEmpty)
    #expect(absent.matchdays.count == 9)
    #expect(absent.clubs.count == 9)
    #expect(absent.problems.isEmpty)
  }

  @Test("the fixtures are sorted by matchday")
  func sorted() throws {
    let calendar = try parse("calendar-sample.pdf")
    #expect(calendar.fixtures.compactMap(\.round) == [1, 3, 4, 5, 6, 7, 8, 9])
  }

  @Test("an empty club short name matches nothing")
  func emptyShortName() throws {
    let calendar = try parse("calendar-sample.pdf", club: "  ")
    #expect(calendar.fixtures.isEmpty)
  }
}

@Suite("Federation PDF parser: page-2 club missing")
struct FederationPDFMissingClubTests {
  @Test("the home match of the missing club needs review: Saturday, no time, no venue; problems in order")
  func missingHome() throws {
    // Esempio Quattro 1911 plays away at Esempio Sei on matchday 6 (printed 07/11/2026); Esempio Sei has no row.
    let calendar = try parse("calendar-missing-club.pdf", club: "Esempio Quattro 1911")
    let match = try #require(calendar.fixtures.first { $0.round == 6 })
    #expect(match.scheduleUnknown)
    #expect(match.date.value == "2026-11-07")
    #expect(match.time == nil)
    #expect(match.venue == nil)
    #expect(match.opponentName == "ESEMPIO SEI")
    #expect(match.opponentAliases.isEmpty)
    #expect(calendar.problems == [.clubNotLinked(name: "ESEMPIO SEI"), .incomplete(teams: 9, clubs: 8)])
    // The other fixtures are complete.
    #expect(calendar.fixtures.filter(\.scheduleUnknown).count == 1)
    #expect(calendar.clubs.count == 8)
    #expect(calendar.clubs.allSatisfy { $0.shortName != nil })
  }

  @Test("our own matches against the missing club are complete: our row is there")
  func missingOpponent() throws {
    let calendar = try parse("calendar-missing-club.pdf")
    let match = try #require(calendar.fixtures.first { $0.round == 4 })
    #expect(match.opponentName == "ESEMPIO SEI")
    #expect(match.isHome)
    #expect(match.time == clock("15:30"))
    #expect(!match.scheduleUnknown)
    #expect(match.opponentAliases.isEmpty)
    #expect(calendar.problems == [.clubNotLinked(name: "ESEMPIO SEI"), .incomplete(teams: 9, clubs: 8)])
  }

  @Test("the calendar of the file with the club present is complete")
  func completeFile() throws {
    #expect(try parse("calendar-sample.pdf").problems.isEmpty)
  }
}

@Suite("Federation PDF parser: refusals")
struct FederationPDFRefusalTests {
  private func parseData(_ data: Data) throws -> PDFCalendar {
    try FederationPDFParser().parse(pdf: data, settings: pdfSettings())
  }

  private func failure(_ data: Data) -> PDFCalendarError? {
    do {
      _ = try parseData(data)
      return nil
    } catch let error as PDFCalendarError {
      return error
    } catch {
      Issue.record("not a PDFCalendarError: \(error)")
      return nil
    }
  }

  @Test("a PDF that is not the federation layout")
  func notFederation() throws {
    #expect(failure(try pdfFixture("not-a-calendar.pdf")) == .layoutNotRecognised)
  }

  @Test("a text file renamed .pdf, empty data and random bytes are not PDFs")
  func notAPDF() {
    #expect(failure(Data("Gentile cliente, questo non è un PDF.".utf8)) == .notAPDF)
    #expect(failure(Data()) == .notAPDF)
    #expect(failure(Data((0..<2000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })) == .notAPDF)
  }

  @Test("a password-protected PDF is refused without trying a password")
  func encrypted() {
    let locked = makePDF(pages: [[DrawnText(text: "riservato", x: 60, y: 400)], []], userPassword: "segreto")
    #expect(failure(locked) == .encrypted)
  }

  @Test("over the size cap is too large, before the bytes are looked at")
  func tooLargeFile() {
    // Not a PDF: if PDFKit were asked first the answer would be .notAPDF.
    #expect(failure(Data(count: PDFCalendar.maxFileSize + 1)) == .tooLarge)
    // At the cap the size is fine (and the bytes are not a PDF).
    #expect(failure(Data(count: PDFCalendar.maxFileSize)) == .notAPDF)
  }

  @Test("more pages than the cap is too large")
  func tooManyPages() {
    #expect(failure(blankPDF(pages: PDFCalendar.maxPages + 1)) == .tooLarge)
    #expect(failure(blankPDF(pages: PDFCalendar.maxPages)) == .layoutNotRecognised)
  }

  @Test("one page, or pages without text, are not the layout")
  func noText() {
    #expect(failure(blankPDF(pages: 1)) == .layoutNotRecognised)
    #expect(failure(blankPDF(pages: 2)) == .layoutNotRecognised)
  }
}

@Suite("Federation PDF parser: odd layouts")
struct FederationPDFOddLayoutTests {
  private let clubs: [[String]] = [
    ["ALFA SSD A RL", "101", "CAMPO ALFA - ALFAVILLE", "VIA UNO 1", "15.00", "Sabato"],
    ["BETA CALCIO", "102", "CAMPO BETA - BETAVILLE", "VIA DUE 2", "9.30", "Domenica"],
    ["SERGNANESE A.S.D.", "103", "CAMPO NOSTRO - NOSTRA", "VIA TRE 3", "16.30", "Sabato"],
  ]

  private func parse(_ data: Data) throws -> PDFCalendar {
    try FederationPDFParser().parse(pdf: data, settings: pdfSettings())
  }

  private func block(
    _ number: Int, _ date: String = "A. 03/10/2026", rows: [String] = ["ALFA- BETA", "Riposo- SERGNANESE"]
  ) -> (label: String, date: String, rows: [String]) {
    ("GIORNATA \(number)", date, rows)
  }

  @Test("a small calendar: ritorno dates, byes and fixtures")
  func small() throws {
    let data = drawnCalendar(
      blocks: [
        block(1, "R. 14/03/2027", rows: ["SERGNANESE- BETA", "Riposo- ALFA"]),
        block(2, "R. 21/03/2027", rows: ["BETA- ALFA", "Riposo- SERGNANESE"]),
        block(3, "R. 28/03/2027", rows: ["ALFA- SERGNANESE", "Riposo- BETA"]),
      ], clubs: clubs)
    let calendar = try parse(data)
    #expect(calendar.category == "CATEGORIA DI PROVA")
    #expect(calendar.phase == "FASE UNO")
    #expect(calendar.girone == "GIRONE Z")
    #expect(calendar.matchdays.map(\.leg) == [.ritorno, .ritorno, .ritorno])
    #expect(calendar.matchdays.map(\.number) == [1, 2, 3])
    #expect(calendar.byes == [2])
    #expect(calendar.problems.isEmpty)
    #expect(calendar.fixtures.count == 2)
    let home = calendar.fixtures[0]
    #expect(home.isHome && home.round == 1 && home.opponentName == "BETA")
    // Beta plays at home on Sunday, but this match is at ours: our day is Sabato.
    #expect(home.date.value == "2027-03-14" && home.time == clock("16:30") && home.venue == nil)
    #expect(home.opponentAliases == ["BETA CALCIO"])
    let away = calendar.fixtures[1]
    #expect(!away.isHome && away.round == 3 && away.opponentName == "ALFA")
    #expect(away.date.value == "2027-03-28" && away.time == clock("15:00"))
    #expect(away.venue == "CAMPO ALFA - ALFAVILLE, VIA UNO 1")
    #expect(away.opponentAliases == ["ALFA SSD A RL"])
  }

  @Test("a row without a separator is reported and gives no fixture")
  func unreadableRow() throws {
    let data = drawnCalendar(
      blocks: [
        block(1, rows: ["SERGNANESE- BETA", "ALFA BETA", "Riposo- ALFA"]),
        block(2, "A. 10/10/2026", rows: ["ALFA- SERGNANESE- BETA", "Riposo- BETA"]),
        block(3, "A. 17/10/2026", rows: ["BETA- SERGNANESE", "Riposo- ALFA"]),
      ], clubs: clubs)
    let calendar = try parse(data)
    #expect(
      calendar.problems == [
        .unreadableRow(matchday: 1, text: "ALFA BETA"),
        .unreadableRow(matchday: 2, text: "ALFA- SERGNANESE- BETA"),
      ])
    #expect(calendar.fixtures.compactMap(\.round) == [1, 3])
    #expect(calendar.fixtures[1].date.value == "2026-10-18")  // at Beta, Domenica
  }

  @Test("a club row with no day is a home match to review")
  func noHomeDay() throws {
    var rows = clubs
    rows[1][5] = "Lunedì"
    let calendar = try parse(
      drawnCalendar(
        blocks: [block(1, rows: ["BETA- SERGNANESE", "Riposo- ALFA"])], clubs: rows))
    let match = try #require(calendar.fixtures.first)
    #expect(match.scheduleUnknown && match.time == nil && match.venue == nil)
    #expect(match.date.value == "2026-10-03")
  }

  @Test("an empty Orario gives no time but keeps the day and the venue")
  func noTime() throws {
    var rows = clubs
    rows[0][4] = ""
    let calendar = try parse(
      drawnCalendar(
        blocks: [block(1, rows: ["ALFA- SERGNANESE", "Riposo- BETA"])], clubs: rows))
    let match = try #require(calendar.fixtures.first)
    #expect(match.time == nil && !match.scheduleUnknown)
    #expect(match.date.value == "2026-10-03")
    #expect(calendar.clubs.first { $0.shortName == "ALFA" }?.time == nil)
  }

  @Test("an empty club number is nil")
  func noNumber() throws {
    var rows = clubs
    rows[1][1] = ""
    let calendar = try parse(
      drawnCalendar(blocks: [block(1, rows: ["BETA- ALFA", "Riposo- SERGNANESE"])], clubs: rows))
    #expect(calendar.clubs.first { $0.fullName == "BETA CALCIO" }?.number == nil)
    #expect(calendar.clubs.first { $0.fullName == "ALFA SSD A RL" }?.number == "101")
  }

  @Test("fewer page-2 rows than teams is reported as incomplete")
  func incomplete() throws {
    let calendar = try parse(
      drawnCalendar(blocks: [block(1)], clubs: Array(clubs.dropFirst())))
    #expect(calendar.problems == [.clubNotLinked(name: "ALFA"), .incomplete(teams: 3, clubs: 2)])
  }

  @Test("a matchday without a valid date is not the layout")
  func badDate() {
    let data = drawnCalendar(blocks: [block(1, "03/10/2026")], clubs: clubs)
    #expect(throws: PDFCalendarError.layoutNotRecognised) { try parse(data) }
    let impossible = drawnCalendar(blocks: [block(1, "A. 31/02/2026")], clubs: clubs)
    #expect(throws: PDFCalendarError.layoutNotRecognised) { try parse(impossible) }
  }

  @Test("a matchday number out of range, or repeated, is not the layout")
  func badNumber() {
    let zero = drawnCalendar(blocks: [block(0)], clubs: clubs)
    #expect(throws: PDFCalendarError.layoutNotRecognised) { try parse(zero) }
    let huge = drawnCalendar(blocks: [block(100)], clubs: clubs)
    #expect(throws: PDFCalendarError.layoutNotRecognised) { try parse(huge) }
    let twice = drawnCalendar(blocks: [block(1), block(1, "A. 10/10/2026")], clubs: clubs)
    #expect(throws: PDFCalendarError.layoutNotRecognised) { try parse(twice) }
  }

  @Test("no GIORNATA line, or no club table header, is not the layout")
  func missingParts() {
    let none = drawnCalendar(blocks: [], clubs: clubs)
    #expect(throws: PDFCalendarError.layoutNotRecognised) { try parse(none) }
    let noTable = drawnCalendar(blocks: [block(1)], clubs: nil)
    #expect(throws: PDFCalendarError.layoutNotRecognised) { try parse(noTable) }
  }

  @Test("no title is not the layout")
  func noTitle() {
    let data = drawnCalendar(title: "", subtitle: "", blocks: [block(1)], clubs: clubs)
    #expect(throws: PDFCalendarError.layoutNotRecognised) { try parse(data) }
  }

  @Test("a calendar with no fixture of ours is returned as it is")
  func noOwnFixtures() throws {
    let data = drawnCalendar(blocks: [block(1, rows: ["ALFA- BETA", "Riposo- CAMPIONE"])], clubs: clubs)
    let calendar = try parse(data)
    #expect(calendar.fixtures.isEmpty && calendar.byes.isEmpty)
    #expect(calendar.matchdays.count == 1)
    #expect(calendar.clubs.count == 3)
  }
}
