import Foundation
import SSCore

// Page 2 of the federation calendar: one row per club. The header line (`Società | N. | Campo / Località |
// Indirizzo | Orario | Giorno`) gives the columns; the text under it is grouped into rows by height and into
// cells by position.

enum ClubTable {
  private static let headerLabels = ["societa", "n.", "campo/localita", "indirizzo", "orario", "giorno"]
  /// Centred cells (the club number, the time, the day) may start a little left of their header.
  private static let leftTolerance = 15.0

  /// The club rows in table order (`shortName` still `nil`), or `nil` when the header is not there.
  /// A line below the header with fewer than two filled cells (a page number) is not a club.
  static func parse(_ runs: [PDFTextRun]) -> [PDFCalendar.Club]? {
    guard let header = headerRuns(in: runs) else { return nil }
    let headerY = header.map(\.midY).reduce(0, +) / Double(header.count)
    let lefts = header.map(\.minX)
    // A cell is in the last column whose left edge, less the tolerance, is not right of the cell's own.
    func column(of run: PDFTextRun) -> Int {
      var found = 0
      for index in 1..<lefts.count where run.minX >= lefts[index] - leftTolerance { found = index }
      return found
    }

    let cells = runs.filter { $0.midY < headerY - 3 }
    var rows: [[PDFTextRun]] = []
    // Cells of one row share a vertical centre to a fraction of a point; rows are about 16 pt apart, so a
    // tolerance of a third of the text height (at least 2.5 pt) is well under half the spacing.
    let heights = cells.map(\.height).sorted()
    let tolerance = max(2.5, (heights.isEmpty ? 9 : heights[heights.count / 2]) / 3)
    for run in cells.sorted(by: { $0.midY > $1.midY }) {
      if let first = rows.last?.first, abs(first.midY - run.midY) <= tolerance {
        rows[rows.count - 1].append(run)
      } else {
        rows.append([run])
      }
    }

    var clubs: [PDFCalendar.Club] = []
    for row in rows {
      var texts = [String](repeating: "", count: lefts.count)
      for run in row.sorted(by: { $0.minX < $1.minX }) {
        let index = column(of: run)
        texts[index] = (texts[index] + " " + run.text).collapsedSpaces
      }
      guard !texts[0].isEmpty, texts.filter({ !$0.isEmpty }).count >= 2 else { continue }
      clubs.append(
        PDFCalendar.Club(
          fullName: texts[0], number: texts[1].isEmpty ? nil : texts[1], venue: texts[2], address: texts[3],
          time: try? ClockTime(texts[4]), homeDay: homeDay(texts[5]), shortName: nil))
    }
    return clubs
  }

  /// The six header cells in column order, all on one line; `nil` when one is missing, repeated on the line
  /// or out of order.
  private static func headerRuns(in runs: [PDFTextRun]) -> [PDFTextRun]? {
    func key(_ text: String) -> String {
      text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
        .lowercased().filter { !$0.isWhitespace }
    }
    // The line of the first header (the club column): the other five must be on it.
    guard let anchor = runs.first(where: { key($0.text) == headerLabels[0] }) else { return nil }
    let line = runs.filter { abs($0.midY - anchor.midY) <= 3 }
    var found: [PDFTextRun] = []
    for label in headerLabels {
      let matches = line.filter { key($0.text) == label }
      guard matches.count == 1, let match = matches.first else { return nil }
      found.append(match)
    }
    guard zip(found, found.dropFirst()).allSatisfy({ $0.minX < $1.minX }) else { return nil }
    return found
  }

  /// `Sabato` or `Domenica`, any case, accents ignored; anything else `nil`.
  static func homeDay(_ text: String) -> PDFCalendar.HomeDay? {
    switch searchKey(text) {
    case "sabato": .saturday
    case "domenica": .sunday
    default: nil
    }
  }
}
