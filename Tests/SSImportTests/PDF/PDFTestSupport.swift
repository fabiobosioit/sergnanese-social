import CoreGraphics
import CoreText
import Foundation
import SSCore

// Helpers for the federation PDF tests. The synthetic calendars come from Tests/Fixtures/pdf/ (made by
// generate.swift); the odd files (encrypted, too many pages, one broken row) are drawn here, with invented text.

/// `Tests/Fixtures/pdf/<name>`, located from this file.
func pdfFixtureURL(_ name: String) -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/pdf/\(name)")
}

func pdfFixture(_ name: String) throws -> Data {
  try Data(contentsOf: pdfFixtureURL(name))
}

/// Settings whose short name is `club`; everything else as in the other import tests.
func pdfSettings(club: String = "Sergnanese") -> ClubSettings {
  ClubSettings(
    clubName: "ASD \(club)", clubShortName: club, season: "2026/27", accentColor: "#CF3326", socialHandle: "",
    homeVenue: "Campo comunale")
}

// MARK: - Small PDFs drawn with CoreGraphics

/// One text on a page: its left edge (or centre), the bottom of the text box and the size.
struct DrawnText {
  var text: String
  var x: Double
  var y: Double
  var size: Double = 9
  var centred = false
}

/// A PDF with one list of texts per page. `userPassword` makes it encrypted.
func makePDF(pages: [[DrawnText]], userPassword: String? = nil) -> Data {
  let data = NSMutableData()
  var box = CGRect(x: 0, y: 0, width: 841.92, height: 595.32)
  var info: [String: Any] = [:]
  if let userPassword {
    info[kCGPDFContextUserPassword as String] = userPassword
    info[kCGPDFContextOwnerPassword as String] = userPassword + "-owner"
  }
  guard let consumer = CGDataConsumer(data: data),
    let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)
  else { fatalError("no PDF context") }
  for texts in pages {
    context.beginPDFPage(nil)
    for drawn in texts {
      let font = CTFontCreateWithName("Helvetica" as CFString, drawn.size, nil)
      let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
      let line = CTLineCreateWithAttributedString(NSAttributedString(string: drawn.text, attributes: attributes))
      let width = CTLineGetTypographicBounds(line, nil, nil, nil)
      context.textPosition = CGPoint(x: drawn.centred ? drawn.x - width / 2 : drawn.x, y: drawn.y)
      CTLineDraw(line, context)
    }
    context.endPDFPage()
  }
  context.closePDF()
  return data as Data
}

/// `count` pages without any text.
func blankPDF(pages count: Int) -> Data {
  makePDF(pages: Array(repeating: [], count: count))
}

/// A calendar laid out as the federation one (columns, bands, spacing copied from the fixtures), from
/// invented content: each block is (`GIORNATA` label, date text, rows). A row is drawn as one text, centred on
/// its column. `clubs` are the page-2 rows as six cells, `nil` leaves page 2 without a table header.
func drawnCalendar(
  title: String = "CATEGORIA DI PROVA", subtitle: String = "FASE UNO - GIRONE Z",
  blocks: [(label: String, date: String, rows: [String])], clubs: [[String]]?
) -> Data {
  let centres = [149.1, 420.95, 692.8]
  let bands = [423.6, 296.3, 169.1]
  var page1 = [
    DrawnText(text: title, x: 424, y: 507.8, size: 29.88, centred: true),
    DrawnText(text: subtitle, x: 421, y: 478.6, size: 16.56, centred: true),
  ]
  for (index, block) in blocks.enumerated() {
    let centre = centres[index % 3]
    let top = bands[index / 3]
    page1.append(DrawnText(text: block.label, x: centre, y: top, size: 9.96, centred: true))
    page1.append(DrawnText(text: block.date, x: centre, y: top - 14.5, size: 7.44, centred: true))
    for (row, text) in block.rows.enumerated() {
      page1.append(
        DrawnText(text: text, x: centre, y: top - 29.4 - Double(row) * 14.43, size: 7.44, centred: true))
    }
  }
  var page2: [DrawnText] = [DrawnText(text: "GIRONE Z", x: 56.6, y: 485.8, size: 12)]
  if let clubs {
    let lefts = [60.8, 223.6, 258.9, 536.6, 698.7, 746.5]
    let labels = ["Società", "N.", "Campo / Località", "Indirizzo", "Orario", "Giorno"]
    for (column, label) in labels.enumerated() {
      page2.append(DrawnText(text: label, x: lefts[column], y: 455.5, size: 9.96))
      for (row, cells) in clubs.enumerated() where !cells[column].isEmpty {
        let centred = column == 1 || column == 4 || column == 5
        let x = [60.8, 237.45, 258.9, 536.6, 720.35, 784.0][column]
        page2.append(
          DrawnText(text: cells[column], x: x, y: 438.7 - Double(row) * 16.15, size: 9, centred: centred))
      }
    }
  }
  return makePDF(pages: [page1, page2])
}
