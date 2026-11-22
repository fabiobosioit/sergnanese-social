import Foundation
import SSCore
import Testing

@testable import SSImport

@Suite("Tuttocampo parser: fixtures")
struct TuttocampoParserFixtureTests {
  private func parse(_ name: String) throws -> FixtureFetch {
    parseResults(
      html: try tuttocampoFixture(name), pageURL: testWidgetPage, clubShortName: "Sergnanese", season: "2026/27")
  }

  @Test("home match played 8-4: round 10, home, score from our side")
  func homePlayed() throws {
    let expected = FetchedFixture(
      date: day("2026-11-21"), time: clock("15:45"), isHome: true, opponentName: "Monte Chiaro",
      opponentClubID: "900183",
      opponentLogoURL: URL(string: "https://b2-content.tuttocampo.it/Teams/40/900183.png?v=1"),
      score: Score(us: 8, them: 4), round: 10, status: .played, statusText: "Partita terminata")
    #expect(try parse("risultati-home-played") == .fixtures([expected]))
  }

  @Test("away match scheduled: round 11, 14:30, no score")
  func awayScheduled() throws {
    let expected = FetchedFixture(
      date: day("2026-11-22"), time: clock("14:30"), isHome: false, opponentName: "Quarto Colle",
      opponentClubID: "900211",
      opponentLogoURL: URL(string: "https://b2-content.tuttocampo.it/Teams/40/900211.png?v=1"),
      score: nil, round: 11, status: .scheduled, statusText: "Partita da giocare")
    #expect(try parse("risultati-away-scheduled") == .fixtures([expected]))
  }

  @Test("postponed: our row only, live and finished rows of other clubs are ignored")
  func postponedLive() throws {
    let expected = FetchedFixture(
      date: day("2026-11-22"), time: clock("10:00"), isHome: false, opponentName: "Gialloblu Ponte",
      opponentClubID: "900155",
      opponentLogoURL: URL(string: "https://b2-content.tuttocampo.it/Teams/40/900155.png?v=4"),
      score: nil, round: 10, status: .postponed, statusText: "Partita rinviata")
    #expect(try parse("risultati-postponed-live") == .fixtures([expected]))
  }

  @Test("a page without our club is a health problem")
  func noSergnanese() throws {
    #expect(try parse("risultati-no-sergnanese") == .sourceProblem(.noFixturesOfOurs))
  }

  @Test("the empty page says results are not available yet")
  func empty() throws {
    #expect(try parse("risultati-empty") == .notYetAvailable)
  }

  @Test("the ranking page is not a results page")
  func ranking() throws {
    #expect(try parse("classifica-normal") == .sourceProblem(.structureChanged))
  }
}

@Suite("Tuttocampo parser: derived pages")
struct TuttocampoParserDerivedTests {
  private func parse(_ html: String, club: String = "Sergnanese", season: String = "2026/27") -> FixtureFetch {
    parseResults(html: html, pageURL: testWidgetPage, clubShortName: club, season: season)
  }

  private func single(_ fetch: FixtureFetch) throws -> FetchedFixture {
    guard case .fixtures(let fixtures) = fetch, fixtures.count == 1 else {
      Issue.record("expected exactly one fixture, got \(fetch)")
      throw CancellationError()
    }
    return fixtures[0]
  }

  @Test("an unrecognised status text needs review")
  func unknownTitle() throws {
    let html = try tuttocampoFixture("risultati-away-scheduled").replacingOccurrences(
      of: "Partita da giocare", with: "Partita sospesa")
    let fixture = try single(parse(html))
    #expect(fixture.status == nil)
    #expect(fixture.statusText == "Partita sospesa")
    #expect(fixture.score == nil)
  }

  @Test("a missing table is a structure problem")
  func missingTable() throws {
    let html = try tuttocampoFixture("risultati-home-played").replacingOccurrences(
      of: "table_results_content", with: "something_else")
    #expect(parse(html) == .sourceProblem(.structureChanged))
  }

  @Test("a table without match rows is a structure problem")
  func noMatchRows() {
    #expect(parse(widgetPage(body: dateRow("Dom. 22 novembre"))) == .sourceProblem(.structureChanged))
  }

  @Test("a match row before any date row is a structure problem")
  func matchBeforeDate() throws {
    let html = try tuttocampoFixture("risultati-home-played").replacingOccurrences(
      of: "(?s)<tr class=\"date\">.*?</tr>", with: "", options: .regularExpression)
    #expect(parse(html) == .sourceProblem(.structureChanged))
  }

  @Test("January belongs to the second year of the season")
  func januaryDate() throws {
    let html = try tuttocampoFixture("risultati-home-played").replacingOccurrences(
      of: "Sab. 21 novembre", with: "Sab. 3 gennaio")
    #expect(try single(parse(html)).date == day("2027-01-03"))
  }

  @Test("August to December belong to the first year, January to July to the second")
  func seasonYears() throws {
    let cases = [
      ("1 agosto", "2026-08-01"), ("31 dicembre", "2026-12-31"), ("1 luglio", "2027-07-01"),
      ("28 FEBBRAIO", "2027-02-28"),
    ]
    for (text, expected) in cases {
      let html = widgetPage(body: dateRow("Dom. \(text)") + matchRow(home: "Sergnanese", away: "Beta"))
      #expect(try single(parse(html)).date == day(expected), "\(text)")
    }
    // The season may be written with a dash.
    let html = widgetPage(body: dateRow("Sab. 3 gennaio") + matchRow(home: "Sergnanese", away: "Beta"))
    #expect(try single(parse(html, season: "2026-27")).date == day("2027-01-03"))
  }

  @Test("a date that does not exist or cannot be read is a structure problem")
  func impossibleDates() throws {
    for text in ["Dom. 30 febbraio", "Dom. 22 smarch", "Dom.", "domenica prossima"] {
      let html = widgetPage(body: dateRow(text) + matchRow(home: "Sergnanese", away: "Beta"))
      #expect(parse(html) == .sourceProblem(.structureChanged), "\(text)")
    }
    // 29 February exists in 2028 (season 2027/28, January to July).
    let html = widgetPage(body: dateRow("Mar. 29 febbraio") + matchRow(home: "Sergnanese", away: "Beta"))
    #expect(try single(parse(html, season: "2027/28")).date == day("2028-02-29"))
    #expect(parse(html, season: "2026/27") == .sourceProblem(.structureChanged))
    #expect(parse(html, season: "boh") == .sourceProblem(.structureChanged))
  }

  @Test("a relative logo address is resolved against <base href>")
  func relativeLogo() throws {
    let body =
      dateRow("Dom. 22 novembre")
      + matchRow(
        home: "Sergnanese", away: "Beta", homeLogo: "Teams/40/917410.png?v=1", awayLogo: "Teams/40/900002.png?v=3")
    let fixture = try single(parse(widgetPage(base: "https://b2-content.tuttocampo.it/", body: body)))
    #expect(fixture.opponentLogoURL?.absoluteString == "https://b2-content.tuttocampo.it/Teams/40/900002.png?v=3")
    #expect(fixture.opponentClubID == "900002")
  }

  @Test("without <base href> a relative address resolves against the page")
  func relativeLogoWithoutBase() throws {
    let body =
      dateRow("Dom. 22 novembre") + matchRow(home: "Sergnanese", away: "Beta", awayLogo: "/Teams/40/900002.png")
    let fixture = try single(parse(widgetPage(body: body)))
    #expect(fixture.opponentLogoURL?.absoluteString == "https://www.tuttocampo.it/Teams/40/900002.png")
    // Not the logo host: no ClubId is guessed.
    #expect(fixture.opponentClubID == nil)
  }

  @Test("a missing or unusable logo gives no address and no ClubId")
  func noLogo() throws {
    let body =
      dateRow("Dom. 22 novembre")
      + matchRow(home: "Sergnanese", away: "Beta", awayLogo: nil)
    let fixture = try single(parse(widgetPage(body: body)))
    #expect(fixture.opponentLogoURL == nil)
    #expect(fixture.opponentClubID == nil)
    let javascript = widgetPage(
      body: dateRow("Dom. 22 novembre") + matchRow(home: "Sergnanese", away: "Beta", awayLogo: "javascript:alert(1)"))
    #expect(try single(parse(javascript)).opponentLogoURL == nil)
  }

  @Test("a name with a legal prefix counts as ours; case and accents are ignored")
  func ourName() throws {
    for name in ["A.S.D. Sergnanese", "ASD SERGNANESE", "sergnanese", "A.S.D. Sérgnanese"] {
      let html = widgetPage(body: dateRow("Dom. 22 novembre") + matchRow(home: "Beta", away: name))
      let fixture = try single(parse(html))
      #expect(fixture.isHome == false, "\(name)")
      #expect(fixture.opponentName == "Beta", "\(name)")
    }
    // The configured short name goes through the same normalisation.
    let html = widgetPage(body: dateRow("Dom. 22 novembre") + matchRow(home: "Beta", away: "A.S.D. Sergnanese"))
    #expect(try single(parse(html, club: "ASD Sergnanese")).opponentName == "Beta")
  }

  @Test("a similar name is not ours")
  func similarName() {
    let html = widgetPage(body: dateRow("Dom. 22 novembre") + matchRow(home: "Sergnanese Under 14", away: "Beta"))
    #expect(parse(html) == .sourceProblem(.noFixturesOfOurs))
  }

  @Test("a row with both sides ours is ignored")
  func bothSidesOurs() throws {
    let body =
      dateRow("Dom. 22 novembre") + matchRow(home: "Sergnanese", away: "A.S.D. Sergnanese")
      + matchRow(home: "Gamma", away: "Sergnanese")
    let fixture = try single(parse(widgetPage(body: body)))
    #expect(fixture.opponentName == "Gamma")
    let only = widgetPage(body: dateRow("Dom. 22 novembre") + matchRow(home: "Sergnanese", away: "Sergnanese"))
    #expect(parse(only) == .sourceProblem(.noFixturesOfOurs))
  }

  @Test("an empty club name matches nothing")
  func emptyClubName() {
    let html = widgetPage(body: dateRow("Dom. 22 novembre") + matchRow(home: "Alfa", away: "Beta"))
    #expect(parse(html, club: "") == .sourceProblem(.noFixturesOfOurs))
  }

  @Test("each date row applies to the rows after it, in page order")
  func severalDates() throws {
    let body =
      dateRow("Sab. 21 novembre") + matchRow(home: "Sergnanese", away: "Beta", time: "15:00")
      + dateRow("Dom. 22 novembre") + matchRow(home: "Gamma", away: "Sergnanese", time: "10:30")
    guard case .fixtures(let fixtures) = parse(widgetPage(body: body)) else {
      Issue.record("expected fixtures")
      return
    }
    #expect(fixtures.map(\.date) == [day("2026-11-21"), day("2026-11-22")])
    #expect(fixtures.map(\.time) == [clock("15:00"), clock("10:30")])
    #expect(fixtures.map(\.isHome) == [true, false])
  }

  @Test(
    "status table",
    arguments: [
      ("Partita da giocare", "-", "-", MatchStatus.scheduled as MatchStatus?),
      ("Partita rinviata", "-", "-", .postponed),
      ("Partita in corso (34')", "1", "2", .scheduled),
      ("Partita in corso (35+')", "0", "0", .scheduled),
      ("Partita terminata", "3", "1", .played),
      ("Partita terminata", "-", "-", nil),
      ("Partita terminata", "3", "-", nil),
      ("Partita terminata", "100", "1", nil),
      ("Partita terminata", "99", "0", .played),
      ("Partita annullata", "-", "-", nil),
      ("", "-", "-", nil),
    ])
  func statuses(title: String, ourGoal: String, theirGoal: String, expected: MatchStatus?) throws {
    let html = widgetPage(
      body: dateRow("Dom. 22 novembre")
        + matchRow(home: "Beta", away: "Sergnanese", homeGoal: theirGoal, awayGoal: ourGoal, title: title))
    let fixture = try single(parse(html))
    #expect(fixture.status == expected)
    #expect(fixture.statusText == title)
    if expected == .played {
      #expect(fixture.score == Score(us: Int(ourGoal)!, them: Int(theirGoal)!))
    } else {
      #expect(fixture.score == nil)
    }
  }

  @Test("the score is from our side whichever side we are")
  func scoreSides() throws {
    let home = widgetPage(
      body: dateRow("Sab. 21 novembre")
        + matchRow(home: "Sergnanese", away: "Beta", homeGoal: "2", awayGoal: "5", title: "Partita terminata"))
    #expect(try single(parse(home)).score == Score(us: 2, them: 5))
    let away = widgetPage(
      body: dateRow("Sab. 21 novembre")
        + matchRow(home: "Beta", away: "Sergnanese", homeGoal: "2", awayGoal: "5", title: "Partita terminata"))
    #expect(try single(parse(away)).score == Score(us: 5, them: 2))
  }

  @Test("an unreadable time is nil, a one-digit hour is padded")
  func times() throws {
    for (text, expected) in [("da definire", nil), ("", nil), ("9:30", "09:30"), ("25:00", nil)] as [(String, String?)]
    {
      let html = widgetPage(body: dateRow("Dom. 22 novembre") + matchRow(home: "Sergnanese", away: "Beta", time: text))
      #expect(try single(parse(html)).time == expected.map(clock), "\(text)")
    }
  }

  @Test("the round comes from the caption, else the selected matchday, within 1...99")
  func rounds() throws {
    let row = dateRow("Dom. 22 novembre") + matchRow(home: "Sergnanese", away: "Beta")
    #expect(try single(parse(widgetPage(caption: "Risultati Giornata 7", body: row))).round == 7)
    #expect(try single(parse(widgetPage(caption: nil, selectedSlide: "12", body: row))).round == 12)
    #expect(try single(parse(widgetPage(caption: "Risultati", selectedSlide: "5", body: row))).round == 5)
    #expect(try single(parse(widgetPage(caption: nil, body: row))).round == nil)
    #expect(try single(parse(widgetPage(caption: "Risultati Giornata 0", body: row))).round == nil)
    #expect(try single(parse(widgetPage(caption: "Risultati Giornata 100", body: row))).round == nil)
  }

  @Test("the not-available message wins over everything else")
  func notAvailable() {
    let html =
      "<html><body><div id=\"content\"><div class=\"message_info\">Risultati non ancora disponibili.</div></div></body></html>"
    #expect(parse(html) == .notYetAvailable)
    #expect(parse("") == .sourceProblem(.structureChanged))
  }

  @Test("markup in team names and scripts is treated as data")
  func hostileContent() throws {
    let body =
      dateRow("Dom. 22 novembre")
      + matchRow(home: "<script>alert(1)</script>Beta &amp; Co", away: "Sergnanese")
    let fixture = try single(parse(widgetPage(body: body)))
    #expect(fixture.opponentName == "Beta & Co")
  }
}
