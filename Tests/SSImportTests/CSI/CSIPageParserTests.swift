import Foundation
import SSCore
import Testing

@testable import SSImport

private func logo(_ id: String) -> URL? {
  URL(string: "https://static.centrosportivoitaliano.it/modulistica/logo/\(id)_202601010000.jpg")
}

private func parse(
  _ html: String, settings: ClubSettings = csiTestSettings, pageURL: URL = csiTestPage
) -> FixtureFetch {
  CSIPageParser().parse(html: html, pageURL: pageURL, settings: settings)
}

private func fixtures(_ fetch: FixtureFetch) -> [FetchedFixture] {
  if case .fixtures(let list) = fetch { return list }
  Issue.record("expected fixtures, got \(fetch)")
  return []
}

@Suite("CSI parser: fixture")
struct CSIPageParserFixtureTests {
  private let venueOne = "CAMPO SPORTIVO ESEMPIO Via Esempio 1 - 00100 ESEMPIO XX"

  @Test("our four matches once each, in page order, with every field")
  func fullExpectation() throws {
    let expected = [
      // Home, played 3-1, andata 1.
      FetchedFixture(
        date: day("2026-10-03"), time: clock("16:00"), isHome: true, opponentName: "ASD Esempio Uno",
        opponentLogoURL: logo("90000002"), score: Score(us: 3, them: 1), round: 1, status: .played,
        statusText: "3 1", venue: venueOne),
      // Away, played 0-4 (4 for us), andata 2; the venue has no trailing code.
      FetchedFixture(
        date: day("2026-10-10"), time: clock("17:00"), isHome: false, opponentName: "Polisportiva Esempio Tre",
        opponentLogoURL: logo("90000004"), score: Score(us: 4, them: 0), round: 2, status: .played,
        statusText: "0 4", venue: "Oratorio Fittizio Via Inventata 3 - 00300 INVENTATA XX"),
      // Home, not played, opponent with the placeholder shield: no logo.
      FetchedFixture(
        date: day("2026-10-17"), time: clock("16:00"), isHome: true, opponentName: "US Esempio Due 2016",
        opponentLogoURL: nil, score: nil, round: 3, status: .scheduled, statusText: "- -", venue: venueOne),
      // Away, not played, ritorno 1 after three andata rounds.
      FetchedFixture(
        date: day("2026-10-24"), time: clock("15:00"), isHome: false, opponentName: "ASD Esempio Uno",
        opponentLogoURL: logo("90000002"), score: nil, round: 4, status: .scheduled, statusText: "- -",
        venue: "IMPIANTO SPORTIVO DI PROVA Piazza Nessuna 4 - 00400 PROVA XX"),
    ]
    #expect(parse(try csiFixture("girone-sample")) == .fixtures(expected))
  }

  @Test("the logo address of the first opponent gives the fake CSI id")
  func logoID() throws {
    let list = fixtures(parse(try csiFixture("girone-sample")))
    #expect(list[0].opponentLogoURL.flatMap { csiTeamID(fromLogoURL: $0) } == "90000002")
    #expect(list[2].opponentLogoURL == nil)
    #expect(list.allSatisfy { $0.opponentClubID == nil })
  }

  @Test("another club of the page: entities in the venue are decoded, score is read from the away side")
  func otherClub() throws {
    let list = fixtures(
      parse(try csiFixture("girone-sample"), settings: csiSettings(clubShortName: "US Esempio Due 2016")))
    let played = try #require(list.first { $0.opponentName == "ASD Esempio Uno" })
    // P999A4: ASD Esempio Uno 5 - 3 US Esempio Due 2016 (away).
    #expect(!played.isHome)
    #expect(played.score == Score(us: 3, them: 5))
    let withQuotes = try #require(list.first { $0.venue?.contains("FANTASIA ROSSI") == true })
    #expect(withQuotes.venue == "CAMPO SPORTIVO COMUNALE \"FANTASIA ROSSI\" Via Fittizia. 22 - 00200 FANTASIA XX")
  }

  @Test("a page with matches but none of ours")
  func noOurs() throws {
    #expect(parse(try csiFixture("girone-no-ours")) == .sourceProblem(.noFixturesOfOurs))
  }

  @Test("an empty calendar is not a match list")
  func noRows() throws {
    #expect(parse(try csiFixture("girone-no-table")) == .sourceProblem(.structureChanged))
  }

  @Test("any other HTML is not a girone")
  func notAGirone() {
    #expect(
      parse("<html><body><h1>Ciao</h1><table><tr><td>Sergnanese</td></tr></table></body></html>")
        == .sourceProblem(.structureChanged))
    #expect(parse("") == .sourceProblem(.structureChanged))
  }
}

@Suite("CSI parser: variants of the fixture")
struct CSIPageParserVariantTests {
  @Test("\"ASD Sergnanese\" counts as ours")
  func legalPrefix() throws {
    let html = try csiFixture("girone-sample").replacingOccurrences(of: ">Sergnanese<", with: ">ASD Sergnanese<")
    #expect(fixtures(parse(html)).count == 4)
  }

  @Test("a different case or accent counts as ours")
  func caseInsensitive() throws {
    let html = try csiFixture("girone-sample").replacingOccurrences(of: ">Sergnanese<", with: ">SERGNANESE<")
    #expect(fixtures(parse(html)).count == 4)
  }

  @Test("31/02/26 on our row: the whole page is a structure problem")
  func impossibleDate() throws {
    let html = try csiFixture("girone-sample").replacingOccurrences(of: "03/10/26", with: "31/02/26")
    #expect(parse(html) == .sourceProblem(.structureChanged))
  }

  @Test("a bad date on a row that is not ours does not matter")
  func impossibleDateElsewhere() throws {
    // P999A2 (not ours) has the same date as P999A1: replace it only inside the second row.
    let html = try csiFixture("girone-sample")
    let marker = "P999A2/?j=ZmFrZS10b2tlbg\""
    let parts = html.components(separatedBy: marker)
    #expect(parts.count > 1)
    var patched = parts[0]
    for part in parts.dropFirst() {
      patched +=
        marker
        + part.replacingOccurrences(of: "03/10/26", with: "31/02/26", options: [], range: part.range(of: "03/10/26"))
    }
    #expect(fixtures(parse(patched)).count == 4)
  }

  @Test("both sides ours: the row is ignored")
  func bothOurs() throws {
    let html = try csiFixture("girone-sample").replacingOccurrences(of: ">ASD Esempio Uno<", with: ">Sergnanese<")
    let list = fixtures(parse(html))
    // P999A1 (3 October) and P999A7 were against ASD Esempio Uno: now both sides are ours.
    #expect(!list.isEmpty)
    #expect(!list.contains { $0.date == day("2026-10-03") })
    #expect(!list.contains { $0.opponentName == "Sergnanese" })
  }

  @Test("a relative img src is resolved against the page address")
  func relativeLogo() throws {
    let html = try csiFixture("girone-sample").replacingOccurrences(
      of: "https://static.centrosportivoitaliano.it/modulistica/logo/", with: "/modulistica/logo/")
    let list = fixtures(parse(html))
    #expect(
      list[0].opponentLogoURL?.absoluteString
        == "https://live.centrosportivoitaliano.it/modulistica/logo/90000002_202601010000.jpg")
  }

  @Test("a base href wins over the page address")
  func baseHref() throws {
    let html = try csiFixture("girone-sample")
      .replacingOccurrences(of: "https://static.centrosportivoitaliano.it/modulistica/logo/", with: "modulistica/logo/")
      .replacingOccurrences(of: "<head>", with: "<head><base href=\"https://static.centrosportivoitaliano.it/\">")
    let list = fixtures(parse(html))
    #expect(list[0].opponentLogoURL == logo("90000002"))
    #expect(list[0].opponentLogoURL.flatMap { csiTeamID(fromLogoURL: $0) } == "90000002")
  }

  @Test("a missing time is nil, the rest of the row is kept")
  func missingTime() throws {
    let html = try csiFixture("girone-sample")
      .replacingOccurrences(of: "<span class=\"js-gg-min \">16:00</span>", with: "<span class=\"js-gg-min \"></span>")
    let list = fixtures(parse(html))
    #expect(list.count == 4)
    #expect(list[0].time == nil)
    #expect(list[0].status == .played)
    #expect(list[1].time == clock("17:00"))
  }

  @Test("a venue over 60 characters is returned whole")
  func longVenue() throws {
    let long = "CAMPO SPORTIVO COMUNALE INTITOLATO A UN BENEMERITO CITTADINO Via Lunghissima 123 - 00100 ESEMPIO XX"
    #expect(long.count > 60)
    let html = try csiFixture("girone-sample").replacingOccurrences(
      of: "CAMPO SPORTIVO ESEMPIO Via Esempio 1 - 00100 ESEMPIO XX (999A1)", with: "\(long) (999A1)")
    #expect(fixtures(parse(html))[0].venue == long)
  }
}

@Suite("CSI parser: small pages")
struct CSIPageParserSmallPageTests {
  private func one(_ row: String, label: String = "Andata giornata 1") -> FixtureFetch {
    parse(csiPage(body: csiLabel(label) + row))
  }

  @Test("a score text that is not goals or dashes needs review with its text")
  func unknownScore() {
    let list = fixtures(one(csiRow(homeGoals: "Rinv.", awayGoals: "-")))
    #expect(list.count == 1)
    #expect(list[0].status == nil)
    #expect(list[0].score == nil)
    #expect(list[0].statusText == "Rinv. -")
  }

  @Test("one dash and one number needs review")
  func halfScore() {
    let list = fixtures(one(csiRow(homeGoals: "3", awayGoals: "-")))
    #expect(list[0].status == nil)
    #expect(list[0].statusText == "3 -")
  }

  @Test("goals over the limit need review")
  func hugeScore() {
    let list = fixtures(one(csiRow(homeGoals: "100", awayGoals: "0")))
    #expect(list[0].status == nil)
    let max = fixtures(one(csiRow(homeGoals: "\(FieldLimits.maxGoals)", awayGoals: "0")))
    #expect(max[0].status == .played)
    #expect(max[0].score == Score(us: FieldLimits.maxGoals, them: 0))
  }

  @Test("empty score spans mean not played")
  func emptyScore() {
    let list = fixtures(one(csiRow(homeGoals: "", awayGoals: "")))
    #expect(list[0].status == .scheduled)
    #expect(list[0].score == nil)
  }

  @Test("a row without a score cell needs review")
  func noScoreCell() {
    let row = csiRow().replacingOccurrences(of: "js-gg-pt", with: "other")
    let list = fixtures(one(row))
    #expect(list[0].status == nil)
    #expect(list[0].statusText == "")
  }

  @Test("an unreadable time is nil")
  func badTime() {
    #expect(fixtures(one(csiRow(time: "25:99")))[0].time == nil)
    #expect(fixtures(one(csiRow(time: "9:05")))[0].time == clock("09:05"))
  }

  @Test("the first occurrence of a match code wins, later ones are dropped")
  func dedupeByCode() {
    let first = csiRow(code: "P1A1", homeGoals: "1", awayGoals: "0")
    let later = csiRow(code: "P1A1", homeGoals: "2", awayGoals: "0")
    let list = fixtures(
      parse(csiPage(body: csiLabel("Andata giornata 1") + first + csiLabel("Andata giornata 5") + later)))
    #expect(list.count == 1)
    #expect(list[0].score == Score(us: 1, them: 0))
    #expect(list[0].round == 1)
  }

  @Test("rows without a code are deduped by date and names")
  func dedupeWithoutCode() {
    let row = csiRow(code: nil)
    let other = csiRow(code: nil, date: "10/10/26")
    let list = fixtures(parse(csiPage(body: row + other + row)))
    #expect(list.map(\.date) == [day("2026-10-03"), day("2026-10-10")])
  }

  @Test("round numbers: andata, ritorno after the highest andata, unknown labels")
  func rounds() {
    let body =
      csiLabel("Andata giornata 1") + csiRow(code: "P1A1", date: "03/10/26")
      + csiLabel("Andata giornata 7") + csiRow(code: "P1A2", date: "10/10/26")
      + csiLabel("Ritorno giornata 2") + csiRow(code: "P1A3", date: "17/10/26")
      + csiLabel("Finale") + csiRow(code: "P1A4", date: "24/10/26")
      + csiLabel("Ritorno giornata 99") + csiRow(code: "P1A5", date: "31/10/26")
    let list = fixtures(parse(csiPage(body: body)))
    #expect(list.map(\.round) == [1, 7, 9, nil, nil])
  }

  @Test("a row before any label has no round")
  func noLabel() {
    #expect(fixtures(parse(csiPage(body: csiRow())))[0].round == nil)
  }

  @Test("a venue without a trailing code is kept; an empty tooltip is nil; whitespace is collapsed")
  func venues() {
    #expect(fixtures(parse(csiPage(body: csiRow(tooltip: "Campo  A\n Via Roma 2"))))[0].venue == "Campo A Via Roma 2")
    #expect(fixtures(parse(csiPage(body: csiRow(tooltip: ""))))[0].venue == nil)
    #expect(fixtures(parse(csiPage(body: csiRow(tooltip: "(999Z1)"))))[0].venue == nil)
    #expect(fixtures(parse(csiPage(body: csiRow(tooltip: "Campo (B) (999Z1)"))))[0].venue == "Campo (B)")
    #expect(fixtures(parse(csiPage(body: csiRow(tooltip: "Campo (Nord)"))))[0].venue == "Campo (Nord)")
  }

  @Test("only http and https logos are kept; the placeholder shield is not a logo")
  func logos() {
    func logoURL(_ address: String) -> URL? {
      fixtures(parse(csiPage(body: csiRow(awayLogo: address))))[0].opponentLogoURL
    }
    #expect(logoURL("https://cdncsi.csi-net.it/risultati/img_2/csi-shield-b.svg") == nil)
    #expect(logoURL("javascript:alert(1)") == nil)
    #expect(logoURL("data:image/png;base64,AAAA") == nil)
    #expect(logoURL("") == nil)
    #expect(logoURL("http://static.centrosportivoitaliano.it/modulistica/logo/90000002_1.jpg") != nil)
  }

  @Test("whitespace in names is collapsed, years and age groups are kept")
  func names() {
    let list = fixtures(parse(csiPage(body: csiRow(away: "  US   Esempio\n 2016 "))))
    #expect(list[0].opponentName == "US Esempio 2016")
  }

  @Test("rows whose sides cannot be read: not a girone")
  func unreadableRows() {
    let broken = "<a href=\"/x/P1A1/\" class=\"btn btn-gara\"><span>03/10/26</span></a>"
    #expect(parse(csiPage(body: broken)) == .sourceProblem(.structureChanged))
  }

  @Test("an empty club name matches nothing")
  func emptyClubName() {
    #expect(
      parse(csiPage(body: csiRow()), settings: csiSettings(clubShortName: "")) == .sourceProblem(.noFixturesOfOurs))
  }

  @Test("never notYetAvailable")
  func neverNotYetAvailable() {
    for html in ["", csiPage(body: ""), csiPage(body: csiRow(home: "A", away: "B"))] {
      #expect(parse(html) != .notYetAvailable)
    }
  }

  @Test("a page of 550 rows (110 matches) is read quickly")
  func largePage() {
    var body = ""
    for repeatIndex in 0..<5 {
      body += csiLabel("Andata giornata \(repeatIndex + 1)")
      for match in 0..<110 {
        let code = "P\(100 + match)A1"
        body += csiRow(
          code: code, date: "03/10/26", home: match % 5 == 0 ? "Sergnanese" : "Club \(match)",
          away: "Club \(match + 500)",
          homeGoals: "1", awayGoals: "0")
      }
    }
    let html = csiPage(body: body)
    let start = ContinuousClock.now
    let list = fixtures(parse(html))
    let elapsed = ContinuousClock.now - start
    #expect(list.count == 22)
    #expect(elapsed < .seconds(10), "took \(elapsed)")
  }
}
