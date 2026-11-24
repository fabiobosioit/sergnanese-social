// Generates the synthetic federation-calendar PDF fixtures in this folder.
//
// Usage (from the repository root):
//   swift Tests/Fixtures/pdf/generate.swift [output-folder]
//
// The layout copies the measured geometry of a real federation calendar (see
// docs/plan/notes/t4.3-pdf-spike.md): page 1 is a grid of 3 columns by 3 bands of matchdays, page 2 is the
// club table (club, number, ground, address, time, day). Every name, address and number here is invented.
// The output is committed; regenerate only when the layout changes (PDF files carry a creation date, so a
// regeneration changes the bytes even when the content is the same).

import CoreGraphics
import CoreText
import Foundation

// MARK: - Content (all invented)

struct Club {
  /// Name as printed on page 1 (short form).
  let short: String
  /// Name as printed in the page 2 table (long form, legal suffixes).
  let long: String
  let number: Int
  let ground: String
  let address: String
  let time: String
  let day: String
}

let clubs: [Club] = [
  Club(
    short: "ESEMPIO UNO", long: "ESEMPIO UNO MILANO SSD A RL", number: 5301,
    ground: "CAMPO \"ESEMPIO UNO\" - CITTAUNO", address: "VIA ESEMPIO, 1", time: "16.00", day: "Sabato"),
  Club(
    short: "ESEMPIO DUE", long: "ESEMPIO DUE S.P.A.", number: 4112,
    ground: "C.S. ORATORIO \"S.ESEMPIO\" - CITTADUE", address: "VIA ESEMPIO, 2", time: "15.00", day: "Sabato"),
  Club(
    short: "ESEMPIO TRE 1970", long: "ESEMPIO TRE 1970", number: 733,
    ground: "STADIO COMUNALE\"E.TRE\"(E.A) - CITTATRE", address: "VIA ESEMPIO N.3", time: "14.30", day: "Sabato"),
  Club(
    short: "ESEMPIO QUATTRO 1911", long: "ESEMPIO QUATTRO 1911", number: 3958,
    ground: "C.S.ARENA ESEMPIO CAMPO N.2 - CITTAQUATTRO", address: "VIA ESEMPIO, 4", time: "16.00", day: "Sabato"),
  Club(
    short: "REAL ESEMPIO CF Sq.B", long: "REAL ESEMPIO CF sq.B", number: 2467,
    ground: "C.S.\"CITTA'DI ESEMPIO\"N.2 - CITTACINQUE", address: "VIA ESEMPIO,5/7", time: "9.30", day: "Sabato"),
  Club(
    short: "ESEMPIO SEI", long: "ESEMPIO SEI A R.L.", number: 1620,
    ground: "C.S.COMUNALE CAMPO 2 E.A. - CITTASEI FRAZ. ESEMPIO", address: "VIA ESEMPIO SEI", time: "9.30",
    day: "Domenica"),
  Club(
    short: "S. ESEMPIO CALCIO", long: "SAN ESEMPIO CALCIO", number: 3071,
    ground: "CAMPO ORATORIO SAN ESEMPIO - CITTASETTE", address: "P.ZA ESEMPIO", time: "17.00", day: "Sabato"),
  Club(
    short: "SERGNANESE", long: "SERGNANESE A.S.D.", number: 905,
    ground: "C.S.COMUNALE N.1 - CITTAOTTO - CITTAOTTO", address: "VIA ESEMPIO OTTO 8", time: "15.30", day: "Sabato"),
  Club(
    short: "WOMEN ESEMPIO", long: "WOMEN ESEMPIO", number: 2288,
    ground: "C.S.COMUNALE \"E.NOVE\" - CITTANOVE LOC.ESEMPIO", address: "VIA ESEMPIO NOVE", time: "11.30",
    day: "Sabato"),
]

let category = "ESORDIENTI MISTE FEMM. AUT."
let phase = "FASE AUTUNNALE - GIRONE B"
let girone = "GIRONE B"
let matchdayDates = [
  "03/10/2026", "10/10/2026", "17/10/2026", "24/10/2026", "31/10/2026", "07/11/2026", "14/11/2026",
  "21/11/2026", "28/11/2026",
]

/// One matchday: home/away club indices, then the club at rest (nil never happens with 9 clubs).
struct Matchday {
  var matches: [(home: Int, away: Int)]
  var rest: Int
}

/// Circle method for an odd number of clubs: each round one club rests.
func roundRobin(count n: Int) -> [Matchday] {
  var ring = Array(0..<n) + [-1]
  var days: [Matchday] = []
  for round in 0..<n {
    var matches: [(Int, Int)] = []
    var rest = -1
    for i in 0..<(ring.count / 2) {
      let a = ring[i]
      let b = ring[ring.count - 1 - i]
      if a == -1 {
        rest = b
      } else if b == -1 {
        rest = a
      } else {
        // Alternate home and away by round and position, so that no club is always at home.
        matches.append((i + round) % 2 == 0 ? (a, b) : (b, a))
      }
    }
    days.append(Matchday(matches: matches, rest: rest))
    ring.insert(ring.removeLast(), at: 1)
  }
  return days
}

// MARK: - Drawing

enum Align { case left, right, center }

struct Pen {
  let context: CGContext

  /// Draws text so that the bottom of its text bounds (as PDFKit reports them) lands on bottomY and the
  /// anchor x is the left edge, right edge or centre according to align.
  @discardableResult
  func text(
    _ string: String, x: CGFloat, bottomY: CGFloat, size: CGFloat, bold: Bool = false,
    color: CGColor = CGColor(gray: 0, alpha: 1), align: Align = .left, display: Bool = false
  ) -> CGFloat {
    // Body text of the real file uses a font with 1.21 line height, the display font uses 1.0. Helvetica
    // reports 1.0, so body text is raised by half the difference to keep the vertical centre the same.
    let fontName = display ? "HelveticaNeue-CondensedBold" : (bold ? "Helvetica-Bold" : "Helvetica")
    let font = CTFontCreateWithName(fontName as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    let originX: CGFloat
    switch align {
    case .left: originX = x
    case .right: originX = x - width
    case .center: originX = x - width / 2
    }
    context.textPosition = CGPoint(x: originX, y: bottomY + size * (Metrics.descentFactor + (display ? 0 : 0.105)))
    CTLineDraw(line, context)
    return width
  }

  func rect(_ r: CGRect, gray: CGFloat) {
    context.setFillColor(CGColor(gray: gray, alpha: 1))
    context.fill(r)
  }

  /// A flat bitmap standing in for a logo. Real calendars embed two PNG logos; a bitmap keeps the same
  /// object-replacement characters in the extracted text.
  func image(_ r: CGRect, rgb: (CGFloat, CGFloat, CGFloat)) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard
      let bitmap = CGContext(
        data: nil, width: 64, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      true
    else { fatalError("no bitmap context") }
    bitmap.setFillColor(CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
    bitmap.fill(CGRect(x: 0, y: 0, width: 64, height: 16))
    context.draw(bitmap.makeImage()!, in: r)
  }
}

enum Metrics {
  /// Bottom of the PDFKit text bounds sits this fraction of the font size below the baseline.
  static let descentFactor: CGFloat = 0.21
  static let pageSize = CGSize(width: 841.92, height: 595.32)

  // Page 1
  static let columnCentres: [CGFloat] = [149.1, 420.95, 692.8]
  /// Left edge of the "- " separator in each column; home names end here, away names start after it.
  static let separatorX: [CGFloat] = [143.2, 415.0, 686.8]
  static let separatorWidth: CGFloat = 7.3
  static let headerBottoms: [CGFloat] = [423.6, 296.3, 169.1]
  static let dateOffset: CGFloat = -14.5
  static let firstMatchOffset: CGFloat = -29.4
  static let matchStep: CGFloat = 14.43

  // Page 2
  static let tableHeaderBottom: CGFloat = 455.5
  static let firstRowBottom: CGFloat = 438.7
  static let rowStep: CGFloat = 16.15
  static let clubX: CGFloat = 60.8
  static let numberCentre: CGFloat = 237.45
  static let groundX: CGFloat = 258.9
  static let addressX: CGFloat = 536.6
  static let timeCentre: CGFloat = 720.35
  static let dayCentre: CGFloat = 784.0
}

let magenta = CGColor(srgbRed: 0.902, green: 0, blue: 0.494, alpha: 1)
let blue = CGColor(srgbRed: 0, green: 0.078, blue: 0.537, alpha: 1)
let white = CGColor(gray: 1, alpha: 1)

func makePDF(at url: URL, title: String, pages: (CGContext, Pen) -> [() -> Void]) {
  var box = CGRect(origin: .zero, size: Metrics.pageSize)
  let info: [CFString: Any] = [
    kCGPDFContextTitle: title,
    kCGPDFContextCreator: "generate.swift (synthetic fixture)",
  ]
  guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
    fatalError("cannot create PDF at \(url.path)")
  }
  let pen = Pen(context: context)
  for drawPage in pages(context, pen) {
    context.beginPDFPage(nil)
    drawPage()
    context.endPDFPage()
  }
  context.closePDF()
}

func drawCalendarPage(_ pen: Pen, days: [Matchday]) {
  pen.image(CGRect(x: 27.04, y: 491.95, width: 188.04, height: 36.04), rgb: (0.8, 0.8, 0.85))
  pen.text(category, x: 241.1, bottomY: 507.8, size: 29.88, color: magenta, display: true)
  pen.text(phase, x: 299.8, bottomY: 478.6, size: 16.56)
  pen.image(CGRect(x: 685.89, y: 488.98, width: 114.63, height: 29.69), rgb: (0.85, 0.8, 0.8))

  // Same drawing order as the real file: per band the three headers, the three dates, then the matches
  // column by column.
  for band in 0..<3 {
    let top = Metrics.headerBottoms[band]
    for column in 0..<3 {
      let index = band * 3 + column
      let centre = Metrics.columnCentres[column]
      pen.rect(CGRect(x: centre - 40, y: top - 3, width: 80, height: 18), gray: 0.25)
      pen.text("GIORNATA \(index + 1)", x: centre, bottomY: top, size: 9.96, bold: true, color: white, align: .center)
    }
    for column in 0..<3 {
      let centre = Metrics.columnCentres[column]
      pen.text(
        "A. \(matchdayDates[band * 3 + column])", x: centre, bottomY: top + Metrics.dateOffset, size: 7.44,
        align: .center)
    }
    for column in 0..<3 {
      let day = days[band * 3 + column]
      let axis = Metrics.separatorX[column]
      var row = 0
      func draw(home: String, away: String) {
        let y = top + Metrics.firstMatchOffset - CGFloat(row) * Metrics.matchStep
        pen.text(home, x: axis, bottomY: y, size: 7.44, align: .right)
        pen.text("- ", x: axis, bottomY: y, size: 6.6)
        pen.text(away + " ", x: axis + Metrics.separatorWidth, bottomY: y, size: 7.44)
        row += 1
      }
      for match in day.matches { draw(home: clubs[match.home].short, away: clubs[match.away].short) }
      draw(home: "Riposo", away: clubs[day.rest].short)
    }
  }
}

func drawClubTablePage(_ pen: Pen, rows: [Club]) {
  let headerY = Metrics.tableHeaderBottom
  pen.rect(CGRect(x: 52, y: headerY - 4, width: 756, height: 18), gray: 0.25)
  pen.text(girone, x: 56.6, bottomY: 485.8, size: 12, bold: true, color: blue)
  // Same drawing order as the real file: the table is written column by column, header first. That keeps
  // PDFKit from joining the cells of one row into a single line.
  func rowY(_ index: Int) -> CGFloat { Metrics.firstRowBottom - CGFloat(index) * Metrics.rowStep }
  func header(_ title: String, x: CGFloat) {
    pen.text(title, x: x, bottomY: headerY, size: 9.96, bold: true, color: white)
  }
  header("Società ", x: Metrics.clubX)
  for (index, club) in rows.enumerated() { pen.text(club.long + " ", x: Metrics.clubX, bottomY: rowY(index), size: 9) }
  header("N. ", x: 223.6)
  for (index, club) in rows.enumerated() {
    pen.text("\(club.number) ", x: Metrics.numberCentre, bottomY: rowY(index), size: 9, align: .center)
  }
  pen.text(category, x: 293.4, bottomY: 518.6, size: 20.04, color: blue, display: true)
  header("Campo / Località ", x: Metrics.groundX)
  for (index, club) in rows.enumerated() {
    pen.text(club.ground + " ", x: Metrics.groundX, bottomY: rowY(index), size: 9)
  }
  header("Indirizzo ", x: Metrics.addressX)
  for (index, club) in rows.enumerated() {
    pen.text(club.address + " ", x: Metrics.addressX, bottomY: rowY(index), size: 9)
  }
  header("Orario ", x: 698.7)
  for (index, club) in rows.enumerated() {
    pen.text(club.time + " ", x: Metrics.timeCentre, bottomY: rowY(index), size: 9, align: .center)
  }
  header("Giorno ", x: 746.5)
  for (index, club) in rows.enumerated() {
    pen.text(club.day + " ", x: Metrics.dayCentre, bottomY: rowY(index), size: 9, align: .center)
  }
}

func drawLetterPage(_ pen: Pen) {
  pen.text("Esempio Servizi Srl", x: 56, bottomY: 520, size: 18, bold: true)
  pen.text("Via Esempio 1 - 00000 Cittaesempio", x: 56, bottomY: 500, size: 9)
  pen.text("Fattura n. 2026/001 del 01/10/2026", x: 56, bottomY: 450, size: 12, bold: true)
  let lines = [
    "Gentile cliente,",
    "con la presente le trasmettiamo il dettaglio dei servizi del mese di settembre.",
    "Pulizia locali: 1 x 120,00 EUR",
    "Manutenzione impianto: 2 x 45,00 EUR",
    "Totale da pagare entro il 31/10/2026: 210,00 EUR",
    "Distinti saluti.",
  ]
  for (index, line) in lines.enumerated() {
    pen.text(line, x: 56, bottomY: 410 - CGFloat(index) * 18, size: 10)
  }
}

// MARK: - Ground truth

func expectedJSON(days: [Matchday], missingClubShort: String?) -> String {
  func esc(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "\\\"") }
  var out = "{\n"
  out += "  \"category\": \"\(category)\",\n  \"phase\": \"\(phase)\",\n  \"girone\": \"\(girone)\",\n"
  out += "  \"matchdays\": [\n"
  let dayLines = days.enumerated().map { index, day -> String in
    let parts = matchdayDates[index].split(separator: "/")
    let iso = "\(parts[2])-\(parts[1])-\(parts[0])"
    let matches = day.matches.map {
      "{ \"home\": \"\(clubs[$0.home].short)\", \"away\": \"\(clubs[$0.away].short)\" }"
    }
    return
      "    { \"number\": \(index + 1), \"date\": \"\(iso)\", \"matches\": [\n      "
      + matches.joined(separator: ",\n      ") + "\n    ], \"rest\": \"\(clubs[day.rest].short)\" }"
  }
  out += dayLines.joined(separator: ",\n") + "\n  ],\n"
  out += "  \"clubs\": [\n"
  let clubLines = clubs.map { club -> String in
    let missing = club.short == missingClubShort
    let venue =
      missing
      ? "\"ground\": null, \"address\": null, \"time\": null, \"day\": null"
      : "\"ground\": \"\(esc(club.ground))\", \"address\": \"\(club.address)\", \"time\": \"\(club.time)\", \"day\": \"\(club.day)\""
    return
      "    { \"short\": \"\(esc(club.short))\", \"long\": \"\(esc(club.long))\", \"number\": \(club.number), \(venue) }"
  }
  out += clubLines.joined(separator: ",\n") + "\n  ]\n}\n"
  return out
}

// MARK: - Main

let outputFolder: URL = {
  if CommandLine.arguments.count > 1 { return URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true) }
  return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
    "Tests/Fixtures/pdf", isDirectory: true)
}()
try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

let days = roundRobin(count: clubs.count)
let tableRows = clubs.sorted { $0.long < $1.long }
let missingShort = "ESEMPIO SEI"

makePDF(at: outputFolder.appendingPathComponent("calendar-sample.pdf"), title: "Calendario (fixture)") { _, pen in
  [{ drawCalendarPage(pen, days: days) }, { drawClubTablePage(pen, rows: tableRows) }]
}
makePDF(at: outputFolder.appendingPathComponent("calendar-missing-club.pdf"), title: "Calendario (fixture)") { _, pen in
  [
    { drawCalendarPage(pen, days: days) },
    { drawClubTablePage(pen, rows: tableRows.filter { $0.short != missingShort }) },
  ]
}
makePDF(at: outputFolder.appendingPathComponent("not-a-calendar.pdf"), title: "Documento (fixture)") { _, pen in
  [{ drawLetterPage(pen) }]
}
try expectedJSON(days: days, missingClubShort: nil).write(
  to: outputFolder.appendingPathComponent("calendar-sample.expected.json"), atomically: true, encoding: .utf8)
try expectedJSON(days: days, missingClubShort: missingShort).write(
  to: outputFolder.appendingPathComponent("calendar-missing-club.expected.json"), atomically: true,
  encoding: .utf8)
print("written to \(outputFolder.path)")
