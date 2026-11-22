import Foundation
import SSCore
import SwiftSoup

// Reads the rendered HTML of a CSI Live "girone" page (the page after its scripts ran, as the browser
// window gives it). SwiftSoup only: nothing is loaded, rendered or run. Facts about the markup:
// docs/plan/notes/t4.8-csi-spike.md, sanitised samples in Tests/Fixtures/csi/.

/// The CSI Live parser behind `AppServices.csiPageParser`. A pure function (see `PageFixtureParser`): no
/// network, no file access, no state.
///
/// The page repeats its calendar several times (550 rows for 110 matches on a real page), so rows are
/// deduped by the match code in the link (`P263A1`), keeping the first in page order. One pass over the
/// rows; the rest of the page is never inspected.
///
/// Outcomes beyond what `PageFixtureParser` documents: rows exist but none has two readable sides
/// → `.structureChanged`; a date that is missing or does not exist on one of our rows →
/// `.structureChanged` (`FetchedFixture.date` cannot be missing).
public struct CSIPageParser: PageFixtureParser {
  public init() {}

  public func parse(html: String, pageURL: URL, settings: ClubSettings) -> FixtureFetch {
    do {
      return try PageReader(pageURL: pageURL, clubShortName: settings.clubShortName).read(html)
    } catch {
      // SwiftSoup only throws on markup it cannot make sense of.
      return .sourceProblem(.structureChanged)
    }
  }
}

private struct PageReader {
  let pageURL: URL
  let clubKey: String

  init(pageURL: URL, clubShortName: String) {
    self.pageURL = pageURL
    self.clubKey = Self.nameKey(clubShortName)
  }

  func read(_ html: String) throws -> FixtureFetch {
    let document = try SwiftSoup.parse(html)
    // Round labels and rows in one list, in page order: a row belongs to the nearest label before it.
    let elements = try document.select("div.label-giornata, a.btn-gara").array()
    let base = try baseURL(document)

    var rounds = RoundNumbers()
    for element in elements where element.hasClass("label-giornata") {
      rounds.note(label: try Self.labelText(element))
    }

    var currentLabel: String?
    var seen = Set<String>()
    var rowCount = 0
    var readableRows = 0
    var fixtures: [FetchedFixture] = []

    for element in elements {
      if element.hasClass("label-giornata") {
        currentLabel = try Self.labelText(element)
        continue
      }
      rowCount += 1
      let code = Self.matchCode(href: try element.attr("href"))
      // Rows of a match already read are skipped before any further work.
      if let code, seen.contains("code:" + code) { continue }
      guard let row = try Row(element: element, base: base) else { continue }
      readableRows += 1
      let key = code.map { "code:" + $0 } ?? "text:\(row.dateText)|\(row.home.name)|\(row.away.name)"
      guard seen.insert(key).inserted else { continue }

      let homeIsOurs = !clubKey.isEmpty && Self.nameKey(row.home.name) == clubKey
      let awayIsOurs = !clubKey.isEmpty && Self.nameKey(row.away.name) == clubKey
      guard homeIsOurs != awayIsOurs else { continue }
      guard let date = Self.date(from: row.dateText) else { return .sourceProblem(.structureChanged) }
      fixtures.append(
        Self.fixture(
          row: row, date: date, isHome: homeIsOurs, code: code,
          round: currentLabel.flatMap { rounds.round(label: $0) }))
    }

    if rowCount == 0 || readableRows == 0 { return .sourceProblem(.structureChanged) }
    if fixtures.isEmpty { return .sourceProblem(.noFixturesOfOurs) }
    return .fixtures(fixtures)
  }

  // MARK: Rows

  /// One side of a match row.
  private struct Side {
    var name: String
    var logoURL: URL?
  }

  /// The raw values of a match row, before our side is known.
  private struct Row {
    var dateText: String
    var timeText: String
    var home: Side
    var away: Side
    var scoreText: String
    var goals: (home: String, away: String)?
    var tooltip: String

    /// `nil` when the row has no two named sides.
    init?(element: Element, base: URL) throws {
      let blocks = try element.select("div.d-flex.align-items-center").array()
      var sides: [Side] = []
      for block in blocks {
        guard let nameElement = try block.select("span.nome-squadra").first() else { continue }
        let name = collapse(try nameElement.text())
        guard !name.isEmpty else { continue }
        let source = try block.select("img").first()?.attr("src") ?? ""
        sides.append(Side(name: name, logoURL: PageReader.absoluteLogoURL(source, base: base)))
      }
      guard sides.count == 2 else { return nil }
      home = sides[0]
      away = sides[1]
      dateText = collapse(try element.select("div.d-flex.flex-column").first()?.select("span").first()?.text() ?? "")
      timeText = try element.select("span.js-gg-min").first()?.text() ?? ""
      tooltip = try element.attr("data-bs-title")
      if let cell = try element.select("div.js-gg-pt").first() {
        scoreText = collapse(try cell.text())
        let values = cell.children().array().filter { $0.tagName() == "span" }
        if values.count == 2 {
          goals = (collapse(try values[0].text()), collapse(try values[1].text()))
        }
      } else {
        scoreText = ""
      }
    }
  }

  private static func fixture(row: Row, date: DayDate, isHome: Bool, code: String?, round: Int?) -> FetchedFixture {
    let theirs = isHome ? row.away : row.home
    var status: MatchStatus?
    var score: Score?
    if let goals = row.goals {
      if let home = Self.goalCount(goals.home), let away = Self.goalCount(goals.away) {
        status = .played
        score = isHome ? Score(us: home, them: away) : Score(us: away, them: home)
      } else if Self.isNoScore(goals.home) && Self.isNoScore(goals.away) {
        status = .scheduled
      }
    }
    return FetchedFixture(
      date: date, time: try? ClockTime(row.timeText), isHome: isHome, opponentName: theirs.name,
      opponentClubID: nil, opponentLogoURL: theirs.logoURL, score: score, round: round, status: status,
      statusText: row.scoreText, venue: venue(tooltip: row.tooltip, code: code))
  }

  // MARK: Values

  /// The `P…` path segment of a match link: `P`, then capital letters and digits with at least one
  /// digit (`P263A1`). The last such segment wins.
  static func matchCode(href: String) -> String? {
    guard let path = URLComponents(string: href.trimmingCharacters(in: .whitespacesAndNewlines))?.path else {
      return nil
    }
    for segment in path.split(separator: "/").reversed() {
      let rest = segment.dropFirst()
      if segment.first == "P", !rest.isEmpty,
        rest.allSatisfy({ $0.isASCII && ($0.isNumber || $0.isUppercase) }), rest.contains(where: \.isNumber)
      {
        return String(segment)
      }
    }
    return nil
  }

  /// "03/10/26" → 2026-10-03; `nil` when it is not `dd/MM/yy` or the day does not exist.
  static func date(from text: String) -> DayDate? {
    let parts = text.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 3, (1...2).contains(parts[0].count), (1...2).contains(parts[1].count), parts[2].count == 2,
      parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
      let day = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2])
    else { return nil }
    return DayDate(year: 2000 + year, month: month, day: day)
  }

  /// A goal count: ASCII digits only, at most `FieldLimits.maxGoals`.
  private static func goalCount(_ text: String) -> Int? {
    guard !text.isEmpty, text.count <= 3, text.allSatisfy({ $0.isASCII && $0.isNumber }),
      let value = Int(text), value <= FieldLimits.maxGoals
    else { return nil }
    return value
  }

  /// What the page shows for a match not played yet.
  private static func isNoScore(_ text: String) -> Bool { text.isEmpty || text == "-" }

  /// The tooltip without the trailing `(code)`, whitespace collapsed; `nil` when empty. The code in
  /// brackets is the match code without its `P`; when the link has no code, any bracketed token of letters
  /// and digits with a digit in it is taken as the code.
  static func venue(tooltip: String, code: String?) -> String? {
    var text = collapse(tooltip)
    if text.hasSuffix(")"), let open = text.lastIndex(of: "(") {
      let inside = text[text.index(after: open)..<text.index(before: text.endIndex)]
      let isCode: Bool
      if let code {
        isCode = inside.caseInsensitiveCompare(code.dropFirst()) == .orderedSame
      } else {
        isCode =
          !inside.isEmpty && inside.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
          && inside.contains(where: \.isNumber)
      }
      if isCode { text = collapse(String(text[..<open])) }
    }
    return text.isEmpty ? nil : text
  }

  /// An absolute `http`/`https` logo address that is not the CSI placeholder shield; else `nil`.
  static func absoluteLogoURL(_ source: String, base: URL) -> URL? {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
      let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
      !isCSIPlaceholderLogo(url)
    else { return nil }
    return url
  }

  /// `<base href>` resolved against the page address, else the page address.
  private func baseURL(_ document: Document) throws -> URL {
    let href = try document.select("base[href]").first()?.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
    if let href, !href.isEmpty, let url = URL(string: href, relativeTo: pageURL)?.absoluteURL { return url }
    return pageURL
  }

  private static func labelText(_ element: Element) throws -> String {
    collapse(try element.select("label").first()?.text() ?? element.text())
  }

  private static func nameKey(_ name: String) -> String { searchKey(stripLegalPrefixes(name)) }
}

/// Round numbers from the labels "Andata giornata N" and "Ritorno giornata N". A ritorno round continues
/// after the highest andata round on the page.
private struct RoundNumbers {
  private var highestAndata = 0

  /// Called for every label on the page, before any `round(label:)`.
  mutating func note(label: String) {
    if let (leg, number) = Self.parse(label), leg == .andata { highestAndata = max(highestAndata, number) }
  }

  /// `nil` for another text or a number outside `1...FieldLimits.maxRound`.
  func round(label: String) -> Int? {
    guard let (leg, number) = Self.parse(label) else { return nil }
    let round = leg == .andata ? number : number + highestAndata
    return (1...FieldLimits.maxRound).contains(round) ? round : nil
  }

  private enum Leg { case andata, ritorno }

  private static func parse(_ label: String) -> (Leg, Int)? {
    let words = label.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    guard words.count == 3, words[1] == "giornata",
      words[2].count <= 3, words[2].allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(words[2])
    else { return nil }
    switch words[0] {
    case "andata": return (.andata, number)
    case "ritorno": return (.ritorno, number)
    default: return nil
    }
  }
}

/// Trims and collapses all whitespace (including no-break spaces) to single spaces.
private func collapse(_ text: String) -> String {
  text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}
