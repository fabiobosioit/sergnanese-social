import Foundation
import SSCore

// Page 1 of the federation calendar: the title and the grid of matchdays (3 columns by 3 bands in the
// sample, but nothing here counts them). Every `GIORNATA n` line opens a block; the line under it is the date;
// the lines under the date, in the same column and above the next block of that column, are the matches.

/// One `GIORNATA` block: its number, leg and date, and the text of each match row.
struct GridBlock: Equatable {
  var number: Int
  var leg: PDFCalendar.Leg
  var date: DayDate
  var rows: [String]
}

struct CalendarTitle: Equatable {
  var category: String
  var phase: String
  var girone: String
}

enum CalendarGrid {
  /// Tells the title and the blocks, or `nil` when the page is not this layout: no title, no `GIORNATA` line,
  /// a number outside `1...FieldLimits.maxRound` or used twice, a block without a valid date.
  static func parse(_ runs: [PDFTextRun]) -> (title: CalendarTitle, blocks: [GridBlock])? {
    let headers = runs.compactMap { run in matchdayNumber(run.text).map { (number: $0, run: run) } }
    guard !headers.isEmpty else { return nil }
    guard headers.allSatisfy({ (1...FieldLimits.maxRound).contains($0.number) }),
      Set(headers.map(\.number)).count == headers.count
    else { return nil }
    guard let title = title(in: runs, above: headers.map(\.run.midY).max() ?? 0) else { return nil }

    // Columns from the centres of the headers: a new column wherever two neighbours are over 80 pt apart.
    let centres = headers.map(\.run.midX).sorted()
    var columns: [[Double]] = []
    for centre in centres {
      if let last = columns.last?.last, centre - last <= 80 {
        columns[columns.count - 1].append(centre)
      } else {
        columns.append([centre])
      }
    }
    let columnCentres = columns.map { $0.reduce(0, +) / Double($0.count) }
    func column(of x: Double) -> Int {
      var best = 0
      for index in columnCentres.indices where abs(columnCentres[index] - x) < abs(columnCentres[best] - x) {
        best = index
      }
      return best
    }

    var blocks: [GridBlock] = []
    for header in headers {
      let columnIndex = column(of: header.run.midX)
      // The band: from this header down to the next header of the same column, or the page bottom.
      let nextTop =
        headers.filter { column(of: $0.run.midX) == columnIndex && $0.run.midY < header.run.midY }
        .map(\.run.midY).max() ?? -Double.infinity
      let inBand = runs.filter {
        column(of: $0.midX) == columnIndex && $0.midY < header.run.midY - 1 && $0.midY > nextTop + 1
      }
      let lines = groupByLine(inBand)
      guard let dateLine = lines.first, let (leg, date) = matchdayDate(dateLine.text) else { return nil }
      blocks.append(
        GridBlock(number: header.number, leg: leg, date: date, rows: lines.dropFirst().map(\.text)))
    }
    return (title, blocks.sorted { $0.number < $1.number })
  }

  /// `n` of `GIORNATA n`, any case.
  static func matchdayNumber(_ text: String) -> Int? {
    guard let match = text.wholeMatch(of: /(?i)GIORNATA\s*([0-9]{1,3})/) else { return nil }
    return Int(match.1)
  }

  /// `A. 03/10/2026` (andata) or `R. 03/10/2026` (ritorno).
  static func matchdayDate(_ text: String) -> (PDFCalendar.Leg, DayDate)? {
    guard let match = text.wholeMatch(of: /(?i)([AR])\.?\s*([0-9]{1,2})\/([0-9]{1,2})\/([0-9]{4})/),
      let day = Int(match.2), let month = Int(match.3), let year = Int(match.4),
      let date = DayDate(year: year, month: month, day: day)
    else { return nil }
    return (match.1.uppercased() == "A" ? .andata : .ritorno, date)
  }

  /// The two topmost lines above the first matchday: the category, then `FASE AUTUNNALE - GIRONE B`, split at its
  /// last `" - "`. The second line is optional; the category is not.
  private static func title(in runs: [PDFTextRun], above top: Double) -> CalendarTitle? {
    let lines = groupByLine(runs.filter { $0.midY > top + 1 })
    guard let category = lines.first?.text, !category.isEmpty else { return nil }
    let second = lines.dropFirst().first?.text ?? ""
    if let split = second.range(of: " - ", options: .backwards) {
      return CalendarTitle(
        category: category, phase: String(second[..<split.lowerBound]).collapsedSpaces,
        girone: String(second[split.upperBound...]).collapsedSpaces)
    }
    return CalendarTitle(category: category, phase: second, girone: "")
  }

  /// Runs on the same line joined left to right, lines from the top down. A line is a group of runs whose
  /// vertical centres are within 3 pt (or a third of their height) of the first run of the group; rows are
  /// at least 14 pt apart, so nothing is merged.
  static func groupByLine(_ runs: [PDFTextRun]) -> [(text: String, midY: Double)] {
    var groups: [[PDFTextRun]] = []
    for run in runs.sorted(by: { $0.midY > $1.midY }) {
      if let first = groups.last?.first, abs(first.midY - run.midY) <= max(3, first.height / 3) {
        groups[groups.count - 1].append(run)
      } else {
        groups.append([run])
      }
    }
    return groups.map { group in
      (
        group.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ").collapsedSpaces,
        group[0].midY
      )
    }
  }
}

/// What a match row says.
enum MatchRow: Equatable {
  case match(home: String, away: String)
  /// `Riposo- CLUB`: the club rests.
  case bye(club: String)
  /// No separator, or more than one.
  case unreadable

  /// Splits a row at the separator `"- "` whose hyphen follows a character that is not a space
  /// (`CREMONESE- RIOZZESE`). A name with `" - "` inside it is not split there. Exactly one separator and two
  /// non-empty sides make a match; a home side `Riposo` (any case) makes a bye of the away side.
  static func split(_ text: String) -> MatchRow {
    let row = text.collapsedSpaces
    let characters = Array(row)
    var separators: [Int] = []
    for index in characters.indices where characters[index] == "-" && index > 0 && index + 1 < characters.count {
      if characters[index - 1] != " ", characters[index + 1] == " " { separators.append(index) }
    }
    guard separators.count == 1, let at = separators.first else { return .unreadable }
    let home = String(characters[..<at]).collapsedSpaces
    let away = String(characters[(at + 1)...]).collapsedSpaces
    guard !home.isEmpty, !away.isEmpty else { return .unreadable }
    if home.caseInsensitiveCompare("Riposo") == .orderedSame { return .bye(club: away) }
    return .match(home: home, away: away)
  }
}
