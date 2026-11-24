import Foundation
import PDFKit

// Text of a PDF page as runs with positions. The federation calendar cannot be read from `PDFPage.string`:
// PDFKit returns the text in drawing order, which jumbles the columns, and `selectionsByLine()` merges or splits
// cells in a way that depends on the producer (a row of three dates comes back as one line). So the text is read
// one character at a time (`selection(for:)` with its bounds) and cut into runs: characters on the same line
// with a small gap between them. Only text and positions are read: annotations, links, forms and scripts in
// the file are never looked at. Measurements: docs/plan/notes/t4.3-pdf-spike.md.

/// A run of text on one line of a page. PDF coordinates: origin at the bottom left, y grows upward.
struct PDFTextRun: Sendable, Equatable {
  var text: String
  var minX: Double
  var maxX: Double
  /// Vertical centre of the text box: the value used to group runs into rows.
  var midY: Double
  var height: Double

  var midX: Double { (minX + maxX) / 2 }
}

enum PDFTextReader {
  /// More characters than this on one page is not a calendar (a calendar page has about 1 600): the page is
  /// refused rather than read, so a hostile file cannot make the parser loop over millions of characters.
  static let maxCharactersPerPage = 50_000

  /// The runs of `page` in the order PDFKit lists them, or `nil` when the page has too many characters.
  /// A page without text gives an empty list.
  static func runs(on page: PDFPage) -> [PDFTextRun]? {
    guard let string = page.string else { return [] }
    let units = Array(string.utf16)
    guard units.count <= maxCharactersPerPage else { return nil }

    var builder = RunBuilder()
    for (index, unit) in units.enumerated() {
      if isSeparator(unit) {
        builder.noteSeparator()
        continue
      }
      // The bounds of a space or a newline can stretch across a whole row (they are not the bounds of a
      // glyph), so only visible characters define where a run is.
      guard let selection = page.selection(for: NSRange(location: index, length: 1)) else {
        builder.noteSeparator()
        continue
      }
      let box = selection.bounds(for: page)
      guard box.height > 0, box.width >= 0, box.minX.isFinite, box.maxX.isFinite, box.midY.isFinite else {
        builder.noteSeparator()
        continue
      }
      builder.add(
        unit, minX: Double(box.minX), maxX: Double(box.maxX), midY: Double(box.midY), height: Double(box.height))
    }
    return builder.finish()
  }

  /// White space, control characters and the object-replacement character PDFKit puts where an image is.
  private static func isSeparator(_ unit: UInt16) -> Bool {
    if unit < 0x20 || unit == 0xFFFC || unit == 0xFFFD { return true }
    guard let scalar = Unicode.Scalar(unit) else { return false }  // half of a surrogate pair: text
    return CharacterSet.whitespacesAndNewlines.contains(scalar)
  }
}

/// Builds runs from characters in string order. A run goes on while the next character is on the same line
/// (its vertical centre is within a quarter of the line height) and starts at most about a line height after
/// the end of the previous one. Cells of a table are at least 20 pt apart; the words of a name are about 2 pt
/// apart; the home and away names of a match row are about 5 pt apart, so a row stays one run.
struct RunBuilder {
  private struct Current {
    var units: [UInt16] = []
    var minX: Double
    var maxX: Double
    var midY: Double
    var height: Double
  }

  private var current: Current?
  private var pendingSpace = false
  private var runs: [PDFTextRun] = []

  mutating func noteSeparator() {
    pendingSpace = true
  }

  mutating func add(_ unit: UInt16, minX: Double, maxX: Double, midY: Double, height: Double) {
    if var run = current {
      let gap = minX - run.maxX
      let sameLine = abs(midY - run.midY) <= max(1.5, 0.25 * run.height)
      let limit = max(8, 1.2 * run.height)
      if sameLine, gap >= -3, gap <= limit {
        if pendingSpace { run.units.append(0x20) }
        run.units.append(unit)
        run.maxX = max(run.maxX, maxX)
        run.height = max(run.height, height)
        current = run
        pendingSpace = false
        return
      }
      flush()
    }
    current = Current(units: [unit], minX: minX, maxX: maxX, midY: midY, height: height)
    pendingSpace = false
  }

  mutating func finish() -> [PDFTextRun] {
    flush()
    return runs
  }

  private mutating func flush() {
    guard let run = current else { return }
    current = nil
    let text = String(decoding: run.units, as: UTF16.self).collapsedSpaces
    guard !text.isEmpty else { return }
    runs.append(PDFTextRun(text: text, minX: run.minX, maxX: run.maxX, midY: run.midY, height: run.height))
  }
}

extension String {
  /// Trimmed, every run of white space turned into one space.
  var collapsedSpaces: String {
    split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }
}
