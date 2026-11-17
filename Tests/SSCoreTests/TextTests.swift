import Foundation
import Testing

@testable import SSCore

@Suite struct LegalPrefixTests {
  @Test(arguments: [
    ("A.S.D. Oratorio San Gerolamo", "Oratorio San Gerolamo"),
    ("ASD Castelverde", "Castelverde"),
    ("asd castelverde", "castelverde"),
    ("U.S. Castelverde Calcio", "Castelverde Calcio"),
    ("U.S.D. Novaria", "Novaria"),
    ("G.S. Sant'Ilario Città", "Sant'Ilario Città"),
    ("F.C. Valdorso", "Valdorso"),
    ("A.C. Prato Fiorito", "Prato Fiorito"),
    ("S.S.D. Novaria Bassa", "Novaria Bassa"),
    ("Pol. Borgo Lucente", "Borgo Lucente"),
    ("Polisportiva Oratorio Santa Lucia", "Oratorio Santa Lucia"),
    ("A.S.D. Polisportiva Borgo", "Borgo"),
    ("Oratorio Santa Lucia", "Oratorio Santa Lucia"),
    ("Real   Cascina  Alta", "Real Cascina Alta"),
    ("Accademia ASD", "Accademia ASD"),
    ("A.S.D.", "A.S.D."),
    ("", ""),
  ])
  func strips(_ input: String, _ expected: String) {
    #expect(stripLegalPrefixes(input) == expected)
  }
}

@Suite struct TruncationTests {
  @Test func shortTextIsUntouched() {
    #expect(truncateAtWord("Valdorso", max: 16) == Truncation(text: "Valdorso", wasCut: false))
    #expect(truncateAtWord("  Valdorso  ", max: 8) == Truncation(text: "Valdorso", wasCut: false))
    #expect(truncateAtWord("Sedici caratteri", max: 16) == Truncation(text: "Sedici caratteri", wasCut: false))
  }

  @Test func cutsAtWordBoundaryIncludingEllipsis() {
    let result = truncateAtWord("Oratorio San Gerolamo", max: 16)
    #expect(result == Truncation(text: "Oratorio San…", wasCut: true))
    #expect(result.text.count <= 16)
    #expect(truncateAtWord("Castelverde Calcio Giovani", max: 20).text == "Castelverde Calcio…")
  }

  @Test func cutsInsideALongFirstWord() {
    #expect(truncateAtWord("Supercalifragilistico", max: 10) == Truncation(text: "Supercali…", wasCut: true))
  }

  @Test func dropsDanglingPunctuation() {
    #expect(truncateAtWord("Borgo, Lucente di Sopra", max: 10).text == "Borgo…")
    #expect(truncateAtWord("Sant' Ilario Città Nuova", max: 9).text == "Sant…")
  }

  @Test func countsAccentedCharactersAsOne() {
    #expect(truncateAtWord("Città Università", max: 16) == Truncation(text: "Città Università", wasCut: false))
    #expect(truncateAtWord("Città Università Nuova", max: 17) == Truncation(text: "Città Università…", wasCut: true))
    let decomposed = "Citta\u{0300} Universita\u{0300}"  // combining accents
    #expect(truncateAtWord(decomposed, max: 16).wasCut == false)
  }

  @Test func emptyAndTinyLimits() {
    #expect(truncateAtWord("", max: 10) == Truncation(text: "", wasCut: false))
    #expect(truncateAtWord("   ", max: 10) == Truncation(text: "", wasCut: false))
    #expect(truncateAtWord("Valdorso", max: 1) == Truncation(text: "…", wasCut: true))
    #expect(truncateAtWord("Valdorso", max: 0) == Truncation(text: "", wasCut: true))
  }
}

@Suite struct DisplayNameTests {
  @Test func shortNameWins() {
    let opponent = Opponent(id: "o", name: "A.S.D. Oratorio San Gerolamo", shortName: "San Gerolamo")
    #expect(displayName(for: opponent, limit: 16) == Truncation(text: "San Gerolamo", wasCut: false))
  }

  @Test func blankShortNameIsIgnored() {
    let opponent = Opponent(id: "o", name: "F.C. Valdorso", shortName: "  ")
    #expect(displayName(for: opponent, limit: 16).text == "Valdorso")
  }

  @Test func stripsThenCuts() {
    let opponent = Opponent(id: "o", name: "A.C. Oratorio Sant'Eufrasio di Valfonda Bassa")
    #expect(opponent.name.count == 45)
    #expect(displayName(for: opponent, limit: 16) == Truncation(text: "Oratorio…", wasCut: true))
    #expect(
      displayName(for: opponent, limit: nil)
        == Truncation(text: "Oratorio Sant'Eufrasio di Valfonda Bassa", wasCut: false))
  }
}

@Suite struct InitialsAndSlugTests {
  @Test(arguments: [
    ("Oratorio San Gerolamo", "OSG"),
    ("A.S.D. Oratorio San Gerolamo", "OSG"),
    ("Treviglio", "TR"),
    ("Sergnanese", "SE"),
    ("Real Cascina Alta", "RCA"),
    ("Unione Calcio Brolo Verde", "UCB"),
    ("Oratorio Sant'Eufrasio di Valfonda", "OSE"),
    ("G.S. Sant'Ilario Città", "SIC"),
    ("Élite Calcio", "ÉC"),
    ("Borgo della Lucente", "BL"),
    ("", ""),
  ])
  func initialsOf(_ name: String, _ expected: String) {
    #expect(initials(name) == expected)
  }

  @Test(arguments: [
    ("Prima Squadra", "prima-squadra"),
    ("G.S. Sant'Ilario Città", "g-s-sant-ilario-citta"),
    ("  Giovanissimi U15  ", "giovanissimi-u15"),
    ("Perché—così?", "perche-cosi"),
    ("", ""),
    ("!!!", ""),
  ])
  func slugOf(_ text: String, _ expected: String) {
    #expect(slug(text) == expected)
  }
}

@Suite struct SearchTests {
  @Test func matchesIgnoringCaseAndAccents() {
    #expect(textMatches(query: "citta", in: ["G.S. Sant'Ilario Città"]))
    #expect(textMatches(query: "SANT ilario", in: ["G.S. Sant'Ilario Città"]))
    #expect(textMatches(query: "gerolamo", in: ["A.S.D. Oratorio", "S. Gerolamo"]))
    #expect(!textMatches(query: "gerolamo lucia", in: ["Oratorio San Gerolamo"]))
    #expect(textMatches(query: "  ", in: ["anything"]))
    #expect(searchKey("  Città   Alta ") == "citta alta")
  }
}

@Suite struct ItalianDateTests {
  @Test func longAndShort() throws {
    #expect(formatDateLong(try DayDate("2026-11-22")) == "Domenica 22 novembre")
    #expect(formatDateShort(try DayDate("2026-11-22")) == "Dom 22 nov")
    #expect(formatDateLong(try DayDate("2026-11-21")) == "Sabato 21 novembre")
    #expect(formatDateLong(try DayDate("2027-01-04")) == "Lunedì 4 gennaio")
    #expect(formatDateShort(try DayDate("2027-03-03")) == "Mer 3 mar")
  }

  @Test func weekendLabels() throws {
    #expect(formatWeekend(weekend(containing: try DayDate("2026-11-22")), currentYear: 2026) == "21–22 novembre")
    #expect(
      formatWeekend(weekend(containing: try DayDate("2026-10-31")), currentYear: 2026) == "31 ottobre – 1 novembre")
    #expect(formatWeekend(weekend(containing: try DayDate("2025-12-27")), currentYear: 2026) == "27–28 dicembre 2025")
    #expect(
      formatWeekend(weekend(containing: try DayDate("2028-01-01")), currentYear: 2026)
        == "1–2 gennaio 2028")
    #expect(
      formatWeekend(weekend(containing: try DayDate("2022-12-31")), currentYear: 2026)
        == "31 dicembre 2022 – 1 gennaio 2023")
  }
}

@Suite struct WeekendMathsTests {
  func day(_ text: String) throws -> DayDate { try DayDate(text) }

  @Test func weekdaysMapToTheComingWeekend() throws {
    for text in ["2026-11-16", "2026-11-18", "2026-11-20", "2026-11-21", "2026-11-22"] {
      let weekend = weekend(containing: try day(text))
      #expect(weekend.saturday == (try day("2026-11-21")), "\(text)")
      #expect(weekend.sunday == (try day("2026-11-22")))
    }
    #expect(weekend(containing: try day("2026-11-23")).saturday == (try day("2026-11-28")))
  }

  @Test func acrossAMonthBoundary() throws {
    let weekend = weekend(containing: try day("2026-10-29"))
    #expect(weekend.saturday == (try day("2026-10-31")))
    #expect(weekend.sunday == (try day("2026-11-01")))
    #expect(weekend.next.saturday == (try day("2026-11-07")))
  }

  @Test func acrossAYearBoundary() throws {
    // 2022-12-31 is a Saturday: the weekend spans two years.
    let weekend = weekend(containing: try day("2023-01-01"))
    #expect(weekend.saturday == (try day("2022-12-31")))
    #expect(weekend.sunday == (try day("2023-01-01")))
    #expect(weekend.previous.sunday == (try day("2022-12-25")))
    // From a Wednesday at the end of December to the first weekend of January.
    #expect(nextWeekend(from: try day("2026-12-30")).saturday == (try day("2027-01-02")))
    #expect(nextWeekend(from: try day("2026-12-30")).sunday == (try day("2027-01-03")))
  }

  @Test func nextWeekendIncludesToday() throws {
    #expect(nextWeekend(from: try day("2026-11-22")).saturday == (try day("2026-11-21")))
    #expect(nextWeekend(from: try day("2026-11-23")).saturday == (try day("2026-11-28")))
    #expect(nextWeekend(from: try day("2028-02-28")).sunday == (try day("2028-03-05")))
  }
}

@Suite struct FileNameTests {
  @Test func singleAndListNames() throws {
    let date = try DayDate("2026-11-22")
    #expect(
      renderFileName(date: date, templateID: "post-prematch", teamName: "Prima Squadra", opponentName: "San Gerolamo")
        == "2026-11-22_post-prematch_prima-squadra_vs_san-gerolamo.png")
    #expect(renderFileName(date: date, templateID: "x", teamName: "", opponentName: "!!") == "2026-11-22_x_x_vs_x.png")
    #expect(
      renderFileName(date: date, templateID: "story-programme", page: PageInfo(index: 2, total: 3))
        == "2026-11-22_story-programme_2of3.png")
    #expect(renderFolder(outputFolder: URL(fileURLWithPath: "/out"), date: date).path == "/out/2026-11-22")
  }

  @Test func neverOverwrites() {
    let taken: Set<String> = ["a.png", "a-2.png"]
    #expect(uniqueFileName("a.png") { taken.contains($0) } == "a-3.png")
    #expect(uniqueFileName("b.png") { taken.contains($0) } == "b.png")
    #expect(uniqueFileName("noext") { $0 == "noext" } == "noext-2")
  }
}
