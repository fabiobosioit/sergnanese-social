import Foundation

// T4.10: how an imported opponent name is matched to the stored opponents (decision D12). The same rules
// serve every import review (tuttocampo, CSI, PDF):
//
// 1. Exact: equal under `opponentMatchKey` → linked (`opponentsMatching`).
// 2. Close: `rankOpponents` compares significant tokens → proposed; pre-filled only when exactly one.
// 3. None: the user creates or links the opponent, with the picker ranked by `rankOpponents`.

// MARK: - Level 1: exact

/// Legal suffixes removed from the end of a club name, written without dots and spaces
/// (`S.p.A.`, `A R.L.`, `S.S.D. a r.l.` all compare as one of these).
let legalSuffixes: Set<String> = ["spa", "srl", "arl", "scarl", "ssd", "asd", "ssdarl", "ssdrl"]

/// The key two names must share to be the same opponent: lower case, accents folded, every character that is
/// not a letter or a digit (dots, apostrophes, hyphens, slashes…) treated as a space, then legal prefixes
/// removed from the start (`legalPrefixes`: `A.S.D.`, `U.S.`, `Pol.`…) and legal suffixes from the end
/// (`legalSuffixes`: `S.p.A.`, `S.r.l.`, `A R.L.`, `SSD a rl`…), repeatedly. A prefix or suffix may be
/// spread over several words (`A. S. D.`, `S.S.D. a r.l.`): the words are compared joined. A name made only of
/// prefixes and suffixes keeps its last word. Words are joined with one space.
///
/// `"U.S. Cremonese S.p.A."` → `"cremonese"`, `"Sant’Ilario Città"` → `"sant ilario citta"`,
/// `"REAL MEDA CF Sq.B"` → `"real meda cf sq b"`. Empty or symbol-only input gives `""`.
public func opponentMatchKey(_ name: String) -> String {
  var words = matchWords(name)
  let prefixes = Set(legalPrefixes.map { $0.lowercased() })
  var changed = true
  while changed {
    changed = false
    if let count = longestAffix(of: words, in: prefixes, fromEnd: false) {
      words.removeFirst(count)
      changed = true
    }
    if let count = longestAffix(of: words, in: legalSuffixes, fromEnd: true) {
      words.removeLast(count)
      changed = true
    }
  }
  return words.joined(separator: " ")
}

/// Lower case, accents folded, split at every character that is not a letter or a digit.
func matchWords(_ text: String) -> [String] {
  text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
    .lowercased()
    .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
    .map(String.init)
}

/// The largest number of words at the start (or end) of `words` that, joined without spaces, is in `affixes`,
/// leaving at least one word; `nil` when there is none.
private func longestAffix(of words: [String], in affixes: Set<String>, fromEnd: Bool) -> Int? {
  guard words.count > 1 else { return nil }
  var joined = ""
  var best: Int?
  for count in 1..<words.count {
    let word = fromEnd ? words[words.count - count] : words[count - 1]
    joined = fromEnd ? word + joined : joined + word
    if joined.count > 12 { break }
    if affixes.contains(joined) { best = count }
  }
  return best
}

// MARK: - Level 2: proposals

/// A stored opponent that may be the one an imported name refers to. Built by `rankOpponents`.
public struct OpponentProposal: Sendable, Codable, Equatable, Hashable {
  public enum Kind: String, Sendable, Codable, CaseIterable {
    /// The names are equal under `opponentMatchKey` (level 1). Listed so that several exact matches can be put
    /// on top of the picker; never a proposal to pre-fill.
    case exact
    /// Every significant token of the side with fewer tokens is in the other side ("Alcione" → "Alcione Milano").
    /// When that side has a single token, it must have at least 7 characters ("Meda" is never contained).
    case containment
    /// The Dice score of the two token sets is at least `OpponentProposal.minimumSimilarity`.
    case similar
  }

  public var opponent: Opponent
  /// The Dice score (0…1) of the best pair of names: 2 × tokens in common ÷ tokens on both sides. 1 for `.exact`.
  public var score: Double
  public var kind: Kind

  public init(opponent: Opponent, score: Double, kind: Kind) {
    self.opponent = opponent
    self.score = score
    self.kind = kind
  }

  /// The Dice score from which two names are `.similar`.
  public static let minimumSimilarity = 0.8
}

/// Words left out of the significant tokens.
let genericMatchTokens: Set<String> = [
  "calcio", "football", "club", "fc", "cf", "ac", "as", "us", "sc", "pol", "polisportiva", "women", "femminile",
  "femm",
]

/// Abbreviations expanded before tokens are compared.
let matchAbbreviations: [String: String] = ["s": "san", "sta": "santa", "sto": "santo"]

/// The parts of a name that `rankOpponents` compares.
struct MatchTokens: Equatable {
  /// The words of `opponentMatchKey` without the squad marker and the years, abbreviations expanded, generic
  /// words removed. When that leaves nothing, the words before generic words were removed.
  var significant: [String]
  /// Four-digit numbers ("1911").
  var years: Set<String>
  /// `"b"` for `Sq. B` or a single trailing letter, `"2"` for a trailing `2`; `nil` when there is none.
  var squad: String?

  init(_ name: String) {
    var words = opponentMatchKey(name).split(separator: " ").map(String.init)
    squad = nil
    if words.count > 1, let last = words.last, last == "2" || (last.count == 1 && last.allSatisfy(\.isLetter)) {
      squad = last
      words.removeLast()
      if words.count > 1, words.last == "sq" { words.removeLast() }
    }
    let years = Set(words.filter { $0.count == 4 && $0.allSatisfy(\.isASCIIDigit) })
    self.years = years
    let named = words.filter { !years.contains($0) }.map { matchAbbreviations[$0] ?? $0 }
    let kept = named.filter { !genericMatchTokens.contains($0) }
    significant = kept.isEmpty ? named : kept
  }
}

/// `true` when two tokens are identical, or both have at least 6 characters and differ by one edit (one letter
/// added, removed or changed).
func matchTokensEqual(_ lhs: String, _ rhs: String) -> Bool {
  if lhs == rhs { return true }
  guard lhs.count >= 6, rhs.count >= 6, abs(lhs.count - rhs.count) <= 1 else { return false }
  return editDistance(lhs, rhs, limit: 1) <= 1
}

/// The Levenshtein distance between `lhs` and `rhs` in characters, or `limit + 1` as soon as it is known to be
/// larger than `limit`.
func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
  let a = Array(lhs)
  let b = Array(rhs)
  if abs(a.count - b.count) > limit { return limit + 1 }
  if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
  var previous = Array(0...b.count)
  for i in 1...a.count {
    var current = [i] + Array(repeating: 0, count: b.count)
    for j in 1...b.count {
      let cost = a[i - 1] == b[j - 1] ? 0 : 1
      current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
    }
    if (current.min() ?? 0) > limit { return limit + 1 }
    previous = current
  }
  return min(previous[b.count], limit + 1)
}

/// The fewest characters a lone significant word needs to be `.containment` in a longer name.
let minimumContainedWordLength = 7

/// How two names compare at level 2: `nil` when they are not a proposal.
func matchProposal(_ lhs: MatchTokens, _ rhs: MatchTokens) -> (score: Double, kind: OpponentProposal.Kind)? {
  if !lhs.years.isEmpty, !rhs.years.isEmpty, lhs.years != rhs.years { return nil }
  let (small, large) =
    lhs.significant.count <= rhs.significant.count
    ? (lhs.significant, rhs.significant) : (rhs.significant, lhs.significant)
  guard !small.isEmpty else { return nil }
  var unused = large
  var common = 0
  for token in small {
    if let index = unused.firstIndex(where: { matchTokensEqual(token, $0) }) {
      unused.remove(at: index)
      common += 1
    }
  }
  let score = 2 * Double(common) / Double(small.count + large.count)
  // A single word is contained only when it is distinctive enough: 7+ characters ("alcione", not "meda").
  if small.count < large.count, common == small.count, small.count >= 2 || small[0].count >= minimumContainedWordLength
  {
    return (score, .containment)
  }
  if score >= OpponentProposal.minimumSimilarity { return (score, .similar) }
  return nil
}

/// The stored opponents an imported name may refer to, best first. Every name of the fixture (`name`, then
/// `aliases`) is compared with every name of each opponent (name, short name, aliases); the best pair counts.
///
/// - `.exact` when a pair is equal under `opponentMatchKey` (score 1).
/// - Otherwise the significant tokens are compared (`opponentMatchKey` words, abbreviations `s`/`sta`/`sto`
///   expanded to `san`/`santa`/`santo`, without the generic words `calcio`, `football`, `club`, `fc`, `cf`,
///   `ac`, `as`, `us`, `sc`, `pol`, `polisportiva`, `women`, `femminile`, `femm`, without years and the squad
///   marker). Two tokens are equal when identical, or when both have 6+ characters and their edit distance is 1.
///   `.containment` when every token of the side with fewer tokens is in the other (a lone token needs 7+
///   characters); `.similar` when the Dice
///   score is at least 0.8. Four-digit years present on both sides must be equal, else the pair is no proposal.
///   A squad marker (`Sq. B`, a single trailing letter, a trailing `2`) is left out of the comparison: it never
///   blocks a proposal, and since it is part of `opponentMatchKey`, a name that differs by it is never exact.
///
/// Order: `.exact` first, then score (higher first), then name (`searchKey`), then id. Opponents that are not
/// proposals are left out; an empty name and no aliases give `[]`.
public func rankOpponents(name: String, aliases: [String], in opponents: [Opponent]) -> [OpponentProposal] {
  let fixtureNames = ([name] + aliases).filter { !opponentMatchKey($0).isEmpty }
  guard !fixtureNames.isEmpty else { return [] }
  let fixtureKeys = Set(fixtureNames.map(opponentMatchKey))
  let fixtureTokens = fixtureNames.map(MatchTokens.init)
  var proposals: [OpponentProposal] = []
  for opponent in opponents {
    let names = ([opponent.name] + [opponent.shortName].compactMap { $0 } + opponent.aliases)
      .filter { !opponentMatchKey($0).isEmpty }
    if names.contains(where: { fixtureKeys.contains(opponentMatchKey($0)) }) {
      proposals.append(OpponentProposal(opponent: opponent, score: 1, kind: .exact))
      continue
    }
    var best: (score: Double, kind: OpponentProposal.Kind)?
    for tokens in names.map(MatchTokens.init) {
      for fixture in fixtureTokens {
        guard let found = matchProposal(fixture, tokens) else { continue }
        if let current = best, current.score >= found.score { continue }
        best = found
      }
    }
    if let best { proposals.append(OpponentProposal(opponent: opponent, score: best.score, kind: best.kind)) }
  }
  return proposals.sorted { lhs, rhs in
    if (lhs.kind == .exact) != (rhs.kind == .exact) { return lhs.kind == .exact }
    if lhs.score != rhs.score { return lhs.score > rhs.score }
    let (left, right) = (searchKey(lhs.opponent.name), searchKey(rhs.opponent.name))
    if left != right { return left < right }
    return lhs.opponent.id < rhs.opponent.id
  }
}

// MARK: - Result on a review row

/// How the opponent of an `ImportCandidate` was found.
public enum OpponentMatch: String, Sendable, Codable, CaseIterable {
  /// Level 1: exactly one opponent equal under `opponentMatchKey` (`opponentsMatching`). Linked, no tag.
  case exact
  /// Level 2: no exact match and exactly one proposal; the row is pre-filled with it ("Proposto").
  case proposed
  /// The user chose the opponent (`linkedOpponentID`: "Collega a esistente…", "Cambia avversario…", "Conferma").
  case linked
  /// No exact match and no proposal: "Crea" or "Collega a esistente…" (`ReviewReason.opponentNotFound`).
  case notFound
  /// Several exact matches, or no exact match and several proposals: nothing is pre-filled
  /// (`ReviewReason.opponentAmbiguous`); the proposals go on top of the picker.
  case ambiguous
}
