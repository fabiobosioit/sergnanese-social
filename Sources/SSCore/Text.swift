import Foundation

// Pure text and date functions shared by the render engine, the seed and the UI.
// Italian names are fixed tables, not locale lookups, so output is identical on every Mac.

// MARK: - Names (decision D5)

/// A text after an optional cut.
public struct Truncation: Sendable, Equatable, Hashable {
  public var text: String
  /// `true` when the text was cut (and ends with `…`).
  public var wasCut: Bool

  public init(text: String, wasCut: Bool) {
    self.text = text
    self.wasCut = wasCut
  }
}

/// Legal prefixes removed from the start of a club name, compared without dots and case.
let legalPrefixes: Set<String> = ["ASD", "US", "USD", "GS", "FC", "AC", "SSD", "POL", "POLISPORTIVA"]

/// Removes leading legal prefixes (`A.S.D.`, `ASD`, `U.S.`, `U.S.D.`, `G.S.`, `F.C.`, `A.C.`,
/// `S.S.D.`, `Pol.`, `Polisportiva`), repeatedly, case-insensitively. Words that identify the club,
/// such as `Oratorio`, are kept. Whitespace is collapsed. A name made only of prefixes is returned
/// unchanged (trimmed).
public func stripLegalPrefixes(_ name: String) -> String {
  let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
  var start = 0
  while start < words.count {
    let key = words[start].replacingOccurrences(of: ".", with: "").uppercased()
    guard legalPrefixes.contains(key) else { break }
    start += 1
  }
  if start == words.count { return words.joined(separator: " ") }
  return words[start...].joined(separator: " ")
}

/// Cuts `text` so that it fits in `max` characters **including** the final `…`, at a word boundary.
/// A first word longer than the room is cut inside the word. Punctuation left at the end of the cut
/// (`,` `-` `.` `'`) is dropped before the `…`. Text that already fits is returned trimmed and uncut.
/// Characters are user-perceived characters, so `"à"` counts as one.
public func truncateAtWord(_ text: String, max: Int) -> Truncation {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.count <= max { return Truncation(text: trimmed, wasCut: false) }
  guard max > 1 else { return Truncation(text: max == 1 ? "…" : "", wasCut: true) }
  let room = max - 1
  let words = trimmed.split(whereSeparator: \.isWhitespace)
  var kept = ""
  for word in words {
    let candidate = kept.isEmpty ? String(word) : kept + " " + word
    if candidate.count > room { break }
    kept = candidate
  }
  if kept.isEmpty { kept = String(trimmed.prefix(room)) }
  let dangling: Set<Character> = [",", "-", ".", "'", "’", ":", ";", "·"]
  while let last = kept.last, dangling.contains(last) || last.isWhitespace { kept.removeLast() }
  if kept.isEmpty { kept = String(trimmed.prefix(room)) }
  return Truncation(text: kept + "…", wasCut: true)
}

/// The name a template shows for an opponent: its `shortName` when set, otherwise the name without
/// legal prefixes; then cut to `limit` with `truncateAtWord` (`nil` = no cut).
public func displayName(for opponent: Opponent, limit: Int?) -> Truncation {
  let short = opponent.shortName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  let base = short.isEmpty ? stripLegalPrefixes(opponent.name) : short
  guard let limit else { return Truncation(text: base, wasCut: false) }
  return truncateAtWord(base, max: limit)
}

/// Small Italian words skipped when making initials.
let initialsStopWords: Set<String> = [
  "di", "da", "de", "del", "della", "dello", "dei", "degli", "delle", "e", "ed", "il", "lo", "la", "i", "gli",
  "le", "l", "d",
]

/// Up to three upper-case initials of the significant words of a club name, after removing legal
/// prefixes: `"Oratorio San Gerolamo"` → `"OSG"`. A one-word name gives its first two letters
/// (`"Treviglio"` → `"TR"`). Words are split at spaces, hyphens and apostrophes, so
/// `"Sant'Elia"` gives `"SE"`. Accented letters are kept (`"Él"`). Empty input gives `""`.
public func initials(_ name: String) -> String {
  let words = stripLegalPrefixes(name)
    .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "'" || $0 == "’" })
    .map { String($0).filter { $0.isLetter || $0.isNumber } }
    .filter { !$0.isEmpty }
  let significant = words.filter { !initialsStopWords.contains($0.lowercased()) }
  let source = significant.isEmpty ? words : significant
  guard let first = source.first else { return "" }
  if source.count == 1 { return String(first.prefix(2)).uppercased() }
  return String(source.prefix(3).compactMap(\.first)).uppercased()
}

/// Lower-case ASCII slug for file names: accents folded, every run of other characters turned into
/// one `-`, no leading or trailing `-`. `"Sant'Elia Fiumerapido"` → `"sant-elia-fiumerapido"`.
/// Empty or symbol-only input gives `""`.
public func slug(_ text: String) -> String {
  let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
  var result = ""
  var pendingDash = false
  for scalar in folded.unicodeScalars {
    let isAlnum = scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar))
    if isAlnum {
      if pendingDash && !result.isEmpty { result.append("-") }
      pendingDash = false
      result.unicodeScalars.append(scalar)
    } else {
      pendingDash = true
    }
  }
  return result.lowercased()
}

// MARK: - Search

/// Folded form used for searching: lower case, no accents, whitespace collapsed.
public func searchKey(_ text: String) -> String {
  text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// `true` when every word of `query` appears in at least one of `fields`, ignoring case and accents.
/// An empty query matches everything. Used by `OpponentRepository.search` and list filters.
public func textMatches(query: String, in fields: [String]) -> Bool {
  let words = searchKey(query).split(separator: " ")
  guard !words.isEmpty else { return true }
  let haystack = fields.map(searchKey)
  return words.allSatisfy { word in haystack.contains { $0.contains(word) } }
}

// MARK: - Dates in Italian

let italianWeekdays = ["Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"]
let italianWeekdaysShort = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
let italianMonths = [
  "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre",
  "novembre", "dicembre",
]
let italianMonthsShort = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]

/// `"Domenica 22 novembre"`.
public func formatDateLong(_ date: DayDate) -> String {
  "\(italianWeekdays[date.isoWeekday - 1]) \(date.day) \(italianMonths[date.month - 1])"
}

/// `"Dom 22 nov"`.
public func formatDateShort(_ date: DayDate) -> String {
  "\(italianWeekdaysShort[date.isoWeekday - 1]) \(date.day) \(italianMonthsShort[date.month - 1])"
}

/// Label of a weekend for the weekend switcher: `"21–22 novembre"`, across months
/// `"31 ottobre – 1 novembre"`. The year is added when it differs from `currentYear`
/// (`"27–28 dicembre 2025"`, `"31 dicembre 2027 – 1 gennaio 2028"`).
public func formatWeekend(_ weekend: Weekend, currentYear: Int) -> String {
  let sat = weekend.saturday
  let sun = weekend.sunday
  let satMonth = italianMonths[sat.month - 1]
  let sunMonth = italianMonths[sun.month - 1]
  if sat.year != sun.year {
    return "\(sat.day) \(satMonth) \(sat.year) – \(sun.day) \(sunMonth) \(sun.year)"
  }
  let year = sun.year == currentYear ? "" : " \(sun.year)"
  if sat.month == sun.month { return "\(sat.day)–\(sun.day) \(sunMonth)\(year)" }
  return "\(sat.day) \(satMonth) – \(sun.day) \(sunMonth)\(year)"
}

// MARK: - Weekends

/// The weekend of the Monday–Sunday week that contains `day`: for a Saturday or Sunday that
/// weekend, for Monday to Friday the coming one. This is "Questo weekend" in the UI.
public func weekend(containing day: DayDate) -> Weekend {
  Weekend(saturday: day.adding(days: 6 - day.isoWeekday))
}

/// The next weekend to play from `day`, today included: the weekend in progress on Saturday and
/// Sunday, the coming one on weekdays. It is the default weekend of Partite and Genera and the first
/// of the seed's "next four weekends". (Equal to `weekend(containing:)`, because weeks run Monday to
/// Sunday; both names exist so call sites read as what they mean.)
public func nextWeekend(from day: DayDate) -> Weekend {
  weekend(containing: day)
}

// MARK: - Output file names (01-architecture.md §6)

/// `"<date>_<templateID>_<team slug>_vs_<opponent slug>.png"`, e.g.
/// `"2026-11-22_post-prematch_prima-squadra_vs_oratorio-san-gerolamo.png"`. Empty slugs become `x`.
public func renderFileName(date: DayDate, templateID: String, teamName: String, opponentName: String) -> String {
  let team = slug(teamName).nilIfEmpty ?? "x"
  let opponent = slug(opponentName).nilIfEmpty ?? "x"
  return "\(date.value)_\(templateID)_\(team)_vs_\(opponent).png"
}

/// `"<date>_<templateID>_<page>of<total>.png"`, e.g. `"2026-11-22_story-programme_1of3.png"`.
public func renderFileName(date: DayDate, templateID: String, page: PageInfo) -> String {
  "\(date.value)_\(templateID)_\(page.index)of\(page.total).png"
}

/// Folder of an image: `<outputFolder>/<YYYY-MM-DD>/`.
public func renderFolder(outputFolder: URL, date: DayDate) -> URL {
  outputFolder.appendingPathComponent(date.value, isDirectory: true)
}

/// `name` if `exists` says it is free, otherwise `name-2.png`, `name-3.png`, … (never overwrite).
public func uniqueFileName(_ name: String, exists: (String) -> Bool) -> String {
  guard exists(name) else { return name }
  let url = URL(fileURLWithPath: name)
  let ext = url.pathExtension
  let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
  var counter = 2
  while true {
    let candidate = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
    if !exists(candidate) { return candidate }
    counter += 1
  }
}
