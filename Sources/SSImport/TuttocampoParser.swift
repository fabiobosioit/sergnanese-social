import Foundation
import SSCore
import SwiftSoup

// Reads the HTML of a tuttocampo.it "Risultati" widget. The page is parsed with SwiftSoup and never
// rendered or run. Facts about the markup: docs/plan/notes/t4.2-spike.md.

/// Our matches on one widget page, or why the page cannot be trusted.
///
/// - Parameters:
///   - html: the page.
///   - pageURL: where it came from; the base for relative addresses when the page has no `<base href>`.
///   - clubShortName: `ClubSettings.clubShortName`; a side is ours when its name equals it under
///     `searchKey(stripLegalPrefixes(_:))`.
///   - season: `ClubSettings.season` ("2026/27"); gives the year of dates, which the widget writes
///     without one (August to December = first year, January to July = second).
func parseResults(html: String, pageURL: URL, clubShortName: String, season: String) -> FixtureFetch {
  do {
    return try ResultsParser(pageURL: pageURL, clubShortName: clubShortName, season: season).parse(html)
  } catch {
    // SwiftSoup only throws on markup it cannot make sense of.
    return .sourceProblem(.structureChanged)
  }
}

private struct ResultsParser {
  let pageURL: URL
  let clubKey: String
  let startYear: Int?

  init(pageURL: URL, clubShortName: String, season: String) {
    self.pageURL = pageURL
    self.clubKey = Self.nameKey(clubShortName)
    self.startYear = Self.startYear(ofSeason: season)
  }

  func parse(_ html: String) throws -> FixtureFetch {
    let document = try SwiftSoup.parse(html)

    if let message = try document.select("#content .message_info").first(),
      try message.text().localizedLowercase.contains("non ancora disponibili")
    {
      return .notYetAvailable
    }
    guard let table = try document.select("#table_results_content table").first() else {
      return .sourceProblem(.structureChanged)
    }

    let round = try Self.round(table: table, document: document)
    let imageBase = try baseURL(document)

    var currentDate: DayDate?
    var matchRows = 0
    var fixtures: [FetchedFixture] = []
    for row in try table.select("tr.date, tr.match") {
      if row.hasClass("date") {
        let label = try row.select("span").first()?.text() ?? row.text()
        guard let date = dayDate(from: label) else { return .sourceProblem(.structureChanged) }
        currentDate = date
        continue
      }
      matchRows += 1
      guard let date = currentDate else { return .sourceProblem(.structureChanged) }
      guard let home = try Side(cell: row.select("td.team.home").first(), base: imageBase),
        let away = try Side(cell: row.select("td.team.away").first(), base: imageBase)
      else { return .sourceProblem(.structureChanged) }
      let homeIsOurs = !clubKey.isEmpty && Self.nameKey(home.name) == clubKey
      let awayIsOurs = !clubKey.isEmpty && Self.nameKey(away.name) == clubKey
      guard homeIsOurs != awayIsOurs else { continue }
      let timeText = try row.select(".match-time").first()?.text()
      let time = timeText.flatMap { try? ClockTime($0) }
      fixtures.append(
        Self.fixture(
          date: date, time: time, round: round, ours: homeIsOurs ? home : away, theirs: homeIsOurs ? away : home,
          isHome: homeIsOurs))
    }

    if matchRows == 0 { return .sourceProblem(.structureChanged) }
    if fixtures.isEmpty { return .sourceProblem(.noFixturesOfOurs) }
    return .fixtures(fixtures)
  }

  // MARK: Rows

  /// One side of a match row.
  private struct Side {
    var name: String
    var logoURL: URL?
    var goalText: String
    var goalTitle: String

    /// `nil` when the cell is missing or has no team name.
    init?(cell: Element?, base: URL) throws {
      guard let cell else { return nil }
      let name = try cell.select(".team-name").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !name.isEmpty else { return nil }
      self.name = name
      let source = try cell.select("img").first()?.attr("src").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !source.isEmpty, let url = URL(string: source, relativeTo: base)?.absoluteURL,
        let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
      {
        self.logoURL = url
      } else {
        self.logoURL = nil
      }
      let goal = try cell.select("span.goal").first()
      self.goalText = try goal?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      self.goalTitle = try goal?.attr("title").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
  }

  private static func fixture(
    date: DayDate, time: ClockTime?, round: Int?, ours: Side, theirs: Side, isHome: Bool
  ) -> FetchedFixture {
    let title = ours.goalTitle
    let lowered = title.lowercased()
    var status: MatchStatus?
    var score: Score?
    if lowered == "partita da giocare" {
      status = .scheduled
    } else if lowered == "partita terminata" {
      if let us = goals(ours.goalText), let them = goals(theirs.goalText) {
        status = .played
        score = Score(us: us, them: them)
      }
    } else if lowered == "partita rinviata" {
      status = .postponed
    } else if lowered.hasPrefix("partita in corso") {
      // A live score is not imported: import again after the match.
      status = .scheduled
    }
    return FetchedFixture(
      date: date, time: time, isHome: isHome, opponentName: theirs.name,
      opponentClubID: theirs.logoURL.flatMap { tuttocampoClubID(fromLogoURL: $0) },
      opponentLogoURL: theirs.logoURL, score: score, round: round, status: status, statusText: title)
  }

  /// A goal count: digits only, at most `FieldLimits.maxGoals`.
  private static func goals(_ text: String) -> Int? {
    guard !text.isEmpty, text.count <= 3, text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text),
      value <= FieldLimits.maxGoals
    else { return nil }
    return value
  }

  // MARK: Page values

  /// "Risultati Giornata 11" in the caption's title, else the selected entry of the matchday strip.
  private static func round(table: Element, document: Document) throws -> Int? {
    let candidates = [
      try table.select("caption").first()?.attr("title"),
      try document.select(".swiper-slide.selected span").first()?.attr("title"),
    ]
    for candidate in candidates.compactMap({ $0 }) {
      let last = candidate.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
      if last.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(last),
        (1...FieldLimits.maxRound).contains(value)
      {
        return value
      }
    }
    return nil
  }

  /// `<base href>` resolved against the page address, else the page address.
  private func baseURL(_ document: Document) throws -> URL {
    let href = try document.select("base[href]").first()?.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
    if let href, !href.isEmpty, let url = URL(string: href, relativeTo: pageURL)?.absoluteURL { return url }
    return pageURL
  }

  // MARK: Dates

  private static let months = [
    "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre",
    "novembre",
    "dicembre",
  ]

  /// "Dom. 22 novembre": weekday ignored, day without leading zero, full Italian month name, any case.
  private func dayDate(from text: String) -> DayDate? {
    guard let startYear else { return nil }
    let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
    guard let dayIndex = tokens.firstIndex(where: { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
      dayIndex + 1 < tokens.count, let day = Int(tokens[dayIndex])
    else { return nil }
    let monthName = tokens[dayIndex + 1].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
    guard let monthIndex = Self.months.firstIndex(of: monthName) else { return nil }
    let month = monthIndex + 1
    return DayDate(year: month >= 8 ? startYear : startYear + 1, month: month, day: day)
  }

  /// 2026 for "2026/27" (or "2026-27").
  private static func startYear(ofSeason season: String) -> Int? {
    let digits = season.trimmingCharacters(in: .whitespaces).prefix(4)
    guard digits.count == 4, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    return Int(digits)
  }

  private static func nameKey(_ name: String) -> String { searchKey(stripLegalPrefixes(name)) }
}
