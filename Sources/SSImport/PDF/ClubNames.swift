import Foundation

// Names of the same club as the two pages of the calendar write them: page 1 short (`S. BERNARDO CALCIO`,
// `ALCIONE`, `REAL MEDA CF Sq.B`), page 2 official (`SAN BERNARDO CALCIO`, `ALCIONE MILANO SSD A RL`,
// `REAL MEDA CF sq.B`). Rules: docs/plan/tasks/wave-4-later.md, T4.3, "Short name → page-2 club".
// Pure functions on strings, so they are tested without a PDF.

enum ClubNames {
  /// Legal forms dropped wherever they stand (dots are already gone: `A.S.D.` is `ASD`).
  private static let legalWords: Set<String> = ["ASD", "SSD", "SPA", "SRL", "ARL"]
  /// Prefixes dropped from the start, the list of `stripLegalPrefixes`.
  private static let legalPrefixes: Set<String> = ["ASD", "US", "USD", "GS", "FC", "AC", "SSD", "POL", "POLISPORTIVA"]
  /// What `S` stands for in front of a saint's name; used only to compare.
  private static let saintForms: Set<String> = ["SAN", "SANTO", "SANTA"]

  /// The words of `name` for comparison: accents folded, upper case, dots removed, any other punctuation a
  /// space, legal forms (`A.S.D.`, `SSD`, `S.P.A.`, `S.R.L.`, `A RL`, `A R.L.`) and legal prefixes removed. A name
  /// made only of legal forms keeps its words. `Sq.B` and `sq.B` both give `SQB`.
  static func words(_ name: String) -> [String] {
    let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
      .uppercased()
    var cleaned = ""
    for character in folded {
      if character == "." { continue }
      cleaned.append(character.isLetter || character.isNumber ? character : " ")
    }
    let all = cleaned.split(whereSeparator: \.isWhitespace).map(String.init)

    var kept: [String] = []
    var index = 0
    while index < all.count {
      if all[index] == "A", index + 1 < all.count, all[index + 1] == "RL" {
        index += 2
        continue
      }
      if !legalWords.contains(all[index]) { kept.append(all[index]) }
      index += 1
    }
    while let first = kept.first, legalPrefixes.contains(first) { kept.removeFirst() }
    return kept.isEmpty ? all : kept
  }

  /// Two words are the same, or one is `S` and the other `SAN`, `SANTO` or `SANTA`.
  static func sameWord(_ left: String, _ right: String) -> Bool {
    if left == right { return true }
    if left == "S" { return saintForms.contains(right) }
    if right == "S" { return saintForms.contains(left) }
    return false
  }

  /// `true` when `words` begins with all of `prefix` (equal lists included). An empty `prefix` matches nothing.
  static func begins(_ words: [String], with prefix: [String]) -> Bool {
    guard !prefix.isEmpty, prefix.count <= words.count else { return false }
    return zip(words, prefix).allSatisfy { sameWord($0, $1) }
  }

  static func same(_ left: [String], _ right: [String]) -> Bool {
    !left.isEmpty && left.count == right.count && begins(left, with: right)
  }

  /// A key for a page-1 team, so that two spellings that differ in case or spacing count once.
  static func teamKey(_ name: String) -> String {
    name.collapsedSpaces.uppercased()
  }

  /// The page-2 row of each page-1 name, in the order of `names`: the index in `clubNames`, or `nil`.
  /// Each row is linked to at most one name. Rules, in order:
  /// 1. exactly one unlinked row equals the name (so our own club, whose two names are the same words, links
  ///    here);
  /// 2. exactly one unlinked row starts with all the words of the name (repeated until nothing changes,
  ///    because each link can settle another name);
  /// 3. one name and one row are left over: they belong together.
  /// A name that matches several rows is not guessed; it stays unlinked unless a later rule settles it.
  static func link(names: [String], clubNames: [String]) -> [Int?] {
    let nameWords = names.map(words)
    let clubWords = clubNames.map(words)
    var links = [Int?](repeating: nil, count: names.count)
    var claimed = Set<Int>()

    func free(where test: (Int) -> Bool) -> [Int] {
      clubNames.indices.filter { !claimed.contains($0) && test($0) }
    }
    func claim(_ name: Int, _ club: Int) {
      links[name] = club
      claimed.insert(club)
    }

    for name in names.indices where links[name] == nil && !nameWords[name].isEmpty {
      let rows = free { same(clubWords[$0], nameWords[name]) }
      if rows.count == 1 { claim(name, rows[0]) }
    }
    var changed = true
    while changed {
      changed = false
      for name in names.indices where links[name] == nil && !nameWords[name].isEmpty {
        let rows = free { begins(clubWords[$0], with: nameWords[name]) }
        if rows.count == 1 {
          claim(name, rows[0])
          changed = true
        }
      }
    }
    let unlinked = names.indices.filter { links[$0] == nil }
    let spare = free { _ in true }
    if unlinked.count == 1, spare.count == 1 { claim(unlinked[0], spare[0]) }
    return links
  }
}
