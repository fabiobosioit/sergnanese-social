import Foundation

// Download all opponents at once (T4.9, decision D11): "Scarica tutti gli avversari…" in Avversari fills the
// opponent list, names and logos, for every league our teams play in. The flow, driven by the UI:
//
// 1. tuttocampo: `FixtureSource.fetchLeagueTeams(for:settings:)` once per active team with a widget id (the
//    Classifica widget). CSI: `SourceTeamListRepository.latest(teamID:source: .csi)` once per active team with
//    a CSI page: the list kept from the last page the user read (`PageFixtureParser.teams(html:pageURL:for:
//    settings:)`, saved after "Importa questa pagina"). No CSI request is ever made. A CSI team with no stored
//    list is reported with `ImportIssue.csiTeamListMissing`.
// 2. `OpponentCandidate.make(found:existing:clubShortName:)` on every `SourceTeam` found and
//    `OpponentCandidate.possibleDuplicatePairs(in:existing:)`: the review sheet. The user ticks rows and picks
//    an `OpponentMergeChoice` for every pair. Nothing is written yet.
// 3. "Salva": `OpponentImportPlan.make(candidates:ticked:pairs:choices:)` turns ticks and choices into writes
//    (it throws while a choice is missing or choices conflict: "Salva" stays disabled), then
//    `OpponentRepository.applyImport(_:)` writes the whole plan in one transaction.
// 4. Logos, for each plan item with a `logo` whose opponent (as returned by `applyImport`) still has none:
//    tuttocampo through `LogoRequest(opponent:sourceTeam:)` and `FixtureSource.downloadLogos`; CSI through
//    `CSILogoRequest(opponent:sourceTeam:)`, the direct download from `CSILive.logoHost` (T4.8c) and
//    `storeCSILogos(_:in:)`; then `OpponentRepository.update` with each stored file name. A logo already
//    present is never replaced. One failing team or logo never stops the others.
//
// Rules and decisions: `docs/plan/tasks/wave-4-later.md` (T4.9) and `docs/plan/tasks/wave-4-t4.9.md`.

// MARK: - Teams a source lists

/// Where a list of league teams comes from.
public enum TeamListSource: String, Sendable, Codable, CaseIterable {
  /// The Classifica widget of tuttocampo.it, read live (T4.9a).
  case tuttocampo
  /// The CSI Live girone page the user last read in the CSI browser window (stored, never requested).
  case csi
}

/// One team of a league as a source lists it, seen in the league of one of our teams.
public struct SourceTeam: Sendable, Codable, Equatable, Hashable {
  public var source: TeamListSource
  /// Our team whose league lists this team.
  public var teamID: EntityID
  /// The name as the source writes it, trimmed, whitespace collapsed.
  public var name: String
  /// Tuttocampo: the ClubId of the logo address (`tuttocampoClubID(fromLogoURL:)`), used only to download the
  /// logo, never as a key (the same club has a different ClubId in each widget); `nil` when the address was
  /// not recognised. CSI: the 8-digit team id (`csiTeamID(fromLogoURL:)`), `nil` when the address has none.
  public var logoID: String?
  /// The absolute logo address the source shows: tuttocampo's fallback download, CSI's download. `nil` when
  /// the source shows no logo or the CSI placeholder shield (`isCSIPlaceholderLogo`).
  public var logoURL: URL?

  public init(source: TeamListSource, teamID: EntityID, name: String, logoID: String? = nil, logoURL: URL? = nil) {
    self.source = source
    self.teamID = teamID
    self.name = name
    self.logoID = logoID
    self.logoURL = logoURL
  }

  /// `true` when a download can be tried: tuttocampo with a ClubId or an address, CSI with an address.
  public var hasLogo: Bool {
    switch source {
    case .tuttocampo: return logoID != nil || logoURL != nil
    case .csi: return logoURL != nil
    }
  }
}

/// The outcome of reading one team's Classifica widget (`FixtureSource.fetchLeagueTeams`).
public enum LeagueTeamsFetch: Sendable, Equatable, Hashable {
  /// Every team of the league except ours, in table order. Empty only when the table lists nobody else.
  case teams([SourceTeam])
  /// The standings table is missing, has no rows, or a row has no name: "la sorgente potrebbe essere
  /// cambiata" (`ImportIssue.standingsChanged`).
  case structureChanged
}

/// The teams one source listed for one of our teams' leagues, as stored by `SourceTeamListRepository`.
public struct SourceTeamList: Sendable, Codable, Equatable, Hashable {
  public var teamID: EntityID
  public var source: TeamListSource
  /// When the page was read ("letto il …" in the review sheet).
  public var readAt: Date
  /// In page order. Every element has this list's `teamID` and `source`.
  public var teams: [SourceTeam]

  /// Sets every team's `teamID` and `source` to the list's.
  public init(teamID: EntityID, source: TeamListSource, readAt: Date, teams: [SourceTeam]) {
    self.teamID = teamID
    self.source = source
    self.readAt = readAt
    self.teams = teams.map { team in
      var team = team
      team.teamID = teamID
      team.source = source
      return team
    }
  }
}

// MARK: - Logos of a source team

extension LogoRequest {
  /// The tuttocampo logo of `sourceTeam` for `opponent`: `clubID` is `sourceTeam.logoID` (`nil` gives
  /// `ImportIssue.logoNotRecognised` from `downloadLogos`), `fallbackURL` is `sourceTeam.logoURL`. `nil` for a
  /// CSI team or a team without a logo.
  public init?(opponent: Opponent, sourceTeam: SourceTeam) {
    guard sourceTeam.source == .tuttocampo, sourceTeam.hasLogo else { return nil }
    self.init(
      opponentID: opponent.id, opponentName: opponent.name, clubID: sourceTeam.logoID,
      fallbackURL: sourceTeam.logoURL)
  }
}

extension CSILogoRequest {
  /// The CSI logo of `sourceTeam` for `opponent`, stored as
  /// `csiLogoFileName(id: sourceTeam.logoID ?? csiTeamID(fromLogoURL:), name: sourceTeam.name)`. `nil` for a
  /// tuttocampo team, no address, the placeholder shield, a scheme other than `https`/`http`, or no possible
  /// file name: the caller then reports `ImportIssue.csiLogoUnavailable`.
  public init?(opponent: Opponent, sourceTeam: SourceTeam) {
    guard sourceTeam.source == .csi, let url = sourceTeam.logoURL, let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http", !isCSIPlaceholderLogo(url),
      let fileName = csiLogoFileName(
        id: sourceTeam.logoID.flatMap { isCSITeamID($0) ? $0 : nil } ?? csiTeamID(fromLogoURL: url),
        name: sourceTeam.name)
    else { return nil }
    self.init(opponentID: opponent.id, opponentName: opponent.name, logoURL: url, fileName: fileName)
  }
}

// MARK: - Review

/// One row of the review sheet: a distinct name found (names compared with `importNameKey`), wherever it was
/// seen, matched to the existing opponents. Build the rows with `make(found:existing:clubShortName:)`.
public struct OpponentCandidate: Sendable, Codable, Equatable, Hashable, Identifiable {
  public enum State: String, Sendable, Codable, CaseIterable {
    /// "Nuovo": no opponent has this name, short name or alias. Ticked by default: create it with its logo.
    case new
    /// "Già presente, senza logo": exactly one opponent matches, it has no logo, and the row has one.
    /// Ticked by default: download the logo only.
    case missingLogo
    /// "Già presente": an opponent matches and has a logo, or the row has no logo to give, or several
    /// opponents match. Nothing to do; shown greyed, never ticked.
    case present
    /// "Possibile duplicato": a new name that looks like another new row or an existing opponent
    /// (`possibleDuplicatePairs`). Ticked by default; every pair needs an `OpponentMergeChoice`.
    case possibleDuplicate
  }

  /// `importNameKey(name)`: unique among the rows of one `make`.
  public var id: String
  /// The first spelling found, whitespace collapsed, cut with `truncateAtWord` to `FieldLimits.opponentName`.
  public var name: String
  /// Every place the name was seen, in the order found; never empty. The same name in two leagues is one row.
  public var sightings: [SourceTeam]
  /// The opponent the name matched (`opponentsMatching`); the first one when several matched. `nil` for
  /// `.new` and `.possibleDuplicate`.
  public var existing: Opponent?
  public var state: State

  public init(id: String, name: String, sightings: [SourceTeam], existing: Opponent?, state: State) {
    self.id = id
    self.name = name
    self.sightings = sightings
    self.existing = existing
    self.state = state
  }

  /// The sighting whose logo is downloaded: the first tuttocampo one with a ClubId, else the first CSI one with
  /// an address, else the first tuttocampo one with only an address (reported as not recognised); `nil` when
  /// no sighting has a logo.
  public var logo: SourceTeam? { preferredLogo(sightings) }

  /// The tick the row starts with: every row except `.present`.
  public var isTickedByDefault: Bool { state != .present }

  /// The review rows for `found`, ordered by `id`. Names are grouped by `importNameKey` (the first spelling is
  /// kept); empty names and the club's own name (`clubShortName`, same comparison) are left out. State: no
  /// matching opponent → `.new`, or `.possibleDuplicate` when `possibleDuplicatePairs` pairs it; exactly one
  /// matching opponent without a logo while the row has one → `.missingLogo`; otherwise `.present`.
  public static func make(found: [SourceTeam], existing: [Opponent], clubShortName: String) -> [OpponentCandidate] {
    let clubKey = importNameKey(clubShortName)
    var order: [String] = []
    var names: [String: String] = [:]
    var sightings: [String: [SourceTeam]] = [:]
    for team in found {
      let name = truncateAtWord(team.name.collapsedWhitespace, max: FieldLimits.opponentName).text
      let key = importNameKey(name)
      guard !key.isEmpty, key != clubKey else { continue }
      if names[key] == nil {
        order.append(key)
        names[key] = name
      }
      if !(sightings[key] ?? []).contains(team) { sightings[key, default: []].append(team) }
    }
    var candidates = order.sorted().map { key in
      let name = names[key] ?? key
      let seen = sightings[key] ?? []
      let matches = opponentsMatching(name: name, in: existing)
      let state: State
      if matches.isEmpty {
        state = .new
      } else if matches.count == 1, matches[0].logoFile == nil, preferredLogo(seen) != nil {
        state = .missingLogo
      } else {
        state = .present
      }
      return OpponentCandidate(id: key, name: name, sightings: seen, existing: matches.first, state: state)
    }
    let paired = Set(
      possibleDuplicatePairs(in: candidates, existing: existing).flatMap { pair in
        [pair.firstCandidateID] + [pair.second.candidateID].compactMap { $0 }
      })
    for index in candidates.indices where paired.contains(candidates[index].id) {
      candidates[index].state = .possibleDuplicate
    }
    return candidates
  }

  /// The possible duplicates among `candidates`. Each row without an existing opponent is paired with every
  /// later such row, then with every opponent in `existing` (in that order), when the names are equal under
  /// `opponentDuplicateKey`: equal after `importNameKey` and after removing one trailing age-group token (a
  /// year from 2000 to 2030, `U<n>`/`Under <n>`, or a squad letter). For an opponent its name and every alias
  /// are tried. Rows that matched an existing opponent are never paired, nor are two existing opponents.
  public static func possibleDuplicatePairs(
    in candidates: [OpponentCandidate], existing: [Opponent]
  ) -> [OpponentDuplicatePair] {
    let open = candidates.filter { $0.existing == nil }
    let openKeys = open.map { opponentDuplicateKey($0.name) }
    let opponentKeys = existing.map { opponent in Set(([opponent.name] + opponent.aliases).map(opponentDuplicateKey)) }
    var pairs: [OpponentDuplicatePair] = []
    for (index, candidate) in open.enumerated() {
      for other in index + 1..<open.count where openKeys[other] == openKeys[index] {
        pairs.append(
          OpponentDuplicatePair(
            firstCandidateID: candidate.id, firstName: candidate.name, second: .candidate(id: open[other].id),
            secondName: open[other].name))
      }
      for (opponent, keys) in zip(existing, opponentKeys) where keys.contains(openKeys[index]) {
        pairs.append(
          OpponentDuplicatePair(
            firstCandidateID: candidate.id, firstName: candidate.name, second: .opponent(opponent),
            secondName: opponent.name))
      }
    }
    return pairs
  }
}

/// Two names that may be the same club: a new review row (`first…`) and another new row or an existing
/// opponent (`second`). The sheet asks "Usa «\(firstName)»" / "Usa «\(secondName)»" / "Tieni separati".
public struct OpponentDuplicatePair: Sendable, Codable, Equatable, Hashable, Identifiable {
  public enum Other: Sendable, Codable, Equatable, Hashable {
    /// Another review row, by `OpponentCandidate.id`.
    case candidate(id: String)
    /// An existing opponent, as it was when the rows were made.
    case opponent(Opponent)

    /// The row id for `.candidate`, `nil` for `.opponent`.
    public var candidateID: String? {
      if case .candidate(let id) = self { return id }
      return nil
    }
  }

  public var firstCandidateID: String
  public var firstName: String
  public var second: Other
  /// The other row's name, or the existing opponent's current name (also when an alias made the pair).
  public var secondName: String

  public init(firstCandidateID: String, firstName: String, second: Other, secondName: String) {
    self.firstCandidateID = firstCandidateID
    self.firstName = firstName
    self.second = second
    self.secondName = secondName
  }

  /// `"<first id>|c:<row id>"` or `"<first id>|o:<opponent id>"`: the key of `OpponentImportPlan.make`'s
  /// `choices`.
  public var id: String {
    switch second {
    case .candidate(let id): return "\(firstCandidateID)|c:\(id)"
    case .opponent(let opponent): return "\(firstCandidateID)|o:\(opponent.id)"
    }
  }
}

/// The user's answer for one `OpponentDuplicatePair`.
public enum OpponentMergeChoice: String, Sendable, Codable, CaseIterable {
  /// "Usa «first»": one opponent named like the first; the second name becomes its alias. When the second is
  /// an existing opponent, that opponent is renamed and its old name becomes an alias (id, matches and logo
  /// unchanged).
  case useFirst
  /// "Usa «second»": one opponent named like the second; the first name becomes its alias.
  case useSecond
  /// "Tieni separati": two opponents.
  case keepSeparate
}

/// The writes of a "Salva", built from the review by `make(candidates:ticked:pairs:choices:)` and written in one
/// transaction by `OpponentRepository.applyImport(_:)`. Never deletes an opponent.
public struct OpponentImportPlan: Sendable, Equatable, Hashable {
  public enum Action: Sendable, Equatable, Hashable {
    /// A new opponent with `name` and `aliases`, no short name, no logo.
    case create(name: String, aliases: [String])
    /// An existing opponent: when `rename` is set, its current name becomes an alias and `rename` its name;
    /// `addAliases` are added. Short name and logo are kept. Both empty = logo only.
    case update(opponentID: EntityID, rename: String?, addAliases: [String])

    /// The draft the action writes, before `validated()`: for `.create` the new opponent's (`current` is
    /// ignored); for `.update` `current` (the opponent as stored now) with the rename and the aliases applied.
    /// `nil` for `.update` without `current`.
    public func draft(current: Opponent?) -> OpponentDraft? {
      switch self {
      case .create(let name, let aliases):
        return OpponentDraft(name: name, aliases: aliases)
      case .update(_, let rename, let addAliases):
        guard let current else { return nil }
        var draft = OpponentDraft(current)
        if let rename {
          draft.aliases.append(draft.name)
          draft.name = rename
        }
        draft.aliases += addAliases
        return draft
      }
    }
  }

  public struct Item: Sendable, Equatable, Hashable {
    public var action: Action
    /// Where to download the opponent's logo from (`OpponentCandidate.logo` rules over every row of the item,
    /// the chosen name's row first); `nil` when the existing opponent already had a logo or no row has one.
    /// Download it only if the opponent returned by `applyImport` still has no logo.
    public var logo: SourceTeam?
    /// The review rows this item covers, in candidate order (for the report).
    public var candidateIDs: [String]

    public init(action: Action, logo: SourceTeam?, candidateIDs: [String]) {
      self.action = action
      self.logo = logo
      self.candidateIDs = candidateIDs
    }
  }

  /// In the order of each item's first row in the candidates.
  public var items: [Item]

  public init(items: [Item]) { self.items = items }

  /// The writes for the ticked rows and the choices.
  ///
  /// - Rows taken: those whose id is in `ticked` and whose state is not `.present`. A `.missingLogo` row is a
  ///   logo-only update of its opponent.
  /// - Pairs taken: those whose first row is taken and whose second is an existing opponent or a taken row.
  ///   Every pair taken needs a choice in `choices` (keyed by `OpponentDuplicatePair.id`), else
  ///   `OpponentPlanError.choicesMissing`.
  /// - Each `useFirst`/`useSecond` puts both sides in one group, whose name is the side chosen; groups chain (A
  ///   into B and B into C give one opponent C with aliases A and B). The choices conflict
  ///   (`OpponentPlanError.conflictingChoices`, with every pair of the group) when a group has no single side that
  ///   was never set aside (A into B and A into C without B and C merged; choices that go round in a circle),
  ///   when two existing opponents would end up in one group, or when a "Tieni separati" pair ends up in one group
  ///   through other choices.
  /// - Each group of merged rows gives one item: with an existing opponent, `.update` (renamed when the chosen
  ///   name is a row's; the other rows' names as aliases; a logo only when it has none); without, `.create` with
  ///   the chosen name, the other names as aliases and the group's logo (tuttocampo before CSI). An update with
  ///   nothing to do is left out.
  public static func make(
    candidates: [OpponentCandidate], ticked: Set<String>, pairs: [OpponentDuplicatePair],
    choices: [String: OpponentMergeChoice]
  ) throws(OpponentPlanError) -> OpponentImportPlan {
    var planner = Planner(candidates: candidates, ticked: ticked)
    try planner.addPairs(pairs, choices: choices)
    return OpponentImportPlan(items: try planner.items())
  }
}

/// Why `OpponentImportPlan.make` cannot build the writes yet. "Salva" stays disabled; `message` explains.
public enum OpponentPlanError: Error, Sendable, Equatable, Hashable {
  /// These pairs (`OpponentDuplicatePair.id`) have no choice yet.
  case choicesMissing(pairIDs: [String])
  /// The choices of these pairs cannot all be applied; `names` are the names involved, for the message.
  case conflictingChoices(pairIDs: [String], names: [String])

  public var message: String {
    switch self {
    case .choicesMissing: return CoreStrings.opponentChoicesMissing
    case .conflictingChoices(_, let names): return CoreStrings.opponentChoicesConflict(names)
    }
  }
}

// MARK: - Pure helpers

/// `opponentMatchKey(name)` (T4.10; `importNameKey` before) without one trailing age-group token: a year from 2000 to 2030, `u<n>` or `under <n>`
/// with one or two digits, or a single letter. `"US Standard 2016"` → `"standard"`, `"Real Fontanile B"` →
/// `"real fontanile"`, `"Aurora Under 14"` → `"aurora"`, `"Riozzese 2015 S.r.l."` → `"riozzese"`. Only the last token goes, so `"Real 2016 B"` →
/// `"real 2016"`. A name of one word (two for `under <n>`) is kept whole: `"US 2016"` → `"2016"`.
func opponentDuplicateKey(_ name: String) -> String {
  var words = opponentMatchKey(name).split(separator: " ").map(String.init)
  if words.count > 2, words[words.count - 2] == "under", isAgeNumber(words[words.count - 1]) {
    words.removeLast(2)
  } else if words.count > 1, isAgeGroupToken(words[words.count - 1]) {
    words.removeLast()
  }
  return words.joined(separator: " ")
}

private func isAgeNumber(_ word: String) -> Bool {
  (1...2).contains(word.count) && word.allSatisfy(\.isASCIIDigit)
}

private func isAgeGroupToken(_ word: String) -> Bool {
  if word.count == 4, word.allSatisfy(\.isASCIIDigit), let year = Int(word) { return (2000...2030).contains(year) }
  if word.hasPrefix("u") { return isAgeNumber(String(word.dropFirst())) }
  return word.count == 1 && word.allSatisfy { $0.isASCII && $0.isLetter }
}

/// See `OpponentCandidate.logo`.
func preferredLogo(_ sightings: [SourceTeam]) -> SourceTeam? {
  sightings.first { $0.source == .tuttocampo && $0.logoID != nil }
    ?? sightings.first { $0.source == .csi && $0.hasLogo }
    ?? sightings.first { $0.source == .tuttocampo && $0.hasLogo }
}

/// The merge groups behind `OpponentImportPlan.make`: every merge choice joins its two sides in one group and
/// marks the side not chosen as a loser; a group is valid when exactly one of its sides never lost (the chosen
/// name), it holds at most one existing opponent, and no "Tieni separati" pair is inside it.
private struct Planner {
  enum Node: Hashable {
    case candidate(String)
    case opponent(EntityID)
  }

  struct TakenPair {
    var pair: OpponentDuplicatePair
    var first: Node
    var second: Node
    var choice: OpponentMergeChoice
  }

  /// Taken rows, in candidate order.
  let taken: [OpponentCandidate]
  var opponents: [EntityID: Opponent] = [:]
  var parent: [Node: Node] = [:]
  var losers = Set<Node>()
  var takenPairs: [TakenPair] = []

  init(candidates: [OpponentCandidate], ticked: Set<String>) {
    var seen = Set<String>()
    taken = candidates.filter { $0.state != .present && ticked.contains($0.id) && seen.insert($0.id).inserted }
    for candidate in taken { if let opponent = candidate.existing { opponents[opponent.id] = opponent } }
  }

  /// The node of a taken row: its opponent for a `.missingLogo` row, else the row itself.
  func node(of candidate: OpponentCandidate) -> Node {
    candidate.existing.map { .opponent($0.id) } ?? .candidate(candidate.id)
  }

  func root(of node: Node) -> Node {
    var current = node
    while let next = parent[current] { current = next }
    return current
  }

  mutating func join(_ lhs: Node, _ rhs: Node) {
    let left = root(of: lhs)
    let right = root(of: rhs)
    if left != right { parent[left] = right }
  }

  mutating func addPairs(
    _ pairs: [OpponentDuplicatePair], choices: [String: OpponentMergeChoice]
  ) throws(OpponentPlanError) {
    let open = Set(taken.filter { $0.existing == nil }.map(\.id))
    let relevant = pairs.filter { pair in
      open.contains(pair.firstCandidateID) && (pair.second.candidateID.map(open.contains) ?? true)
    }
    let missing = relevant.filter { choices[$0.id] == nil }.map(\.id)
    if !missing.isEmpty { throw .choicesMissing(pairIDs: missing) }
    for pair in relevant {
      guard let choice = choices[pair.id] else { continue }
      let first = Node.candidate(pair.firstCandidateID)
      let second: Node
      switch pair.second {
      case .candidate(let id): second = .candidate(id)
      case .opponent(let opponent):
        second = .opponent(opponent.id)
        if opponents[opponent.id] == nil { opponents[opponent.id] = opponent }
      }
      takenPairs.append(TakenPair(pair: pair, first: first, second: second, choice: choice))
      switch choice {
      case .useFirst:
        join(first, second)
        losers.insert(second)
      case .useSecond:
        join(first, second)
        losers.insert(first)
      case .keepSeparate:
        break
      }
    }
  }

  func items() throws(OpponentPlanError) -> [OpponentImportPlan.Item] {
    var groupOrder: [Node] = []
    var rows: [Node: [OpponentCandidate]] = [:]
    var members: [Node: Set<Node>] = [:]
    for candidate in taken {
      let node = node(of: candidate)
      let root = root(of: node)
      if rows[root] == nil { groupOrder.append(root) }
      rows[root, default: []].append(candidate)
      members[root, default: []].insert(node)
    }
    for taken in takenPairs where taken.choice != .keepSeparate {
      members[root(of: taken.first), default: []].formUnion([taken.first, taken.second])
    }

    var conflicts: [String] = []
    var winners: [Node: Node] = [:]
    for root in groupOrder {
      let nodes = members[root] ?? []
      let unbeaten = nodes.filter { !losers.contains($0) }
      let opponentCount = nodes.filter { if case .opponent = $0 { return true } else { return false } }.count
      let separated = takenPairs.contains { pair in
        pair.choice == .keepSeparate && self.root(of: pair.first) == root && self.root(of: pair.second) == root
      }
      if unbeaten.count == 1, opponentCount <= 1, !separated, let winner = unbeaten.first {
        winners[root] = winner
      } else {
        conflicts += takenPairs.filter { self.root(of: $0.first) == root }.map(\.pair.id)
      }
    }
    if !conflicts.isEmpty { throw conflict(conflicts) }

    var items: [OpponentImportPlan.Item] = []
    for root in groupOrder {
      let group = rows[root] ?? []
      let nodes = members[root] ?? []
      let chosen: OpponentCandidate? = {
        if case .candidate(let id)? = winners[root] { return group.first { $0.id == id } }
        return nil
      }()
      let others = group.filter { $0.id != chosen?.id && $0.existing == nil }.map(\.name)
      let ordered = (chosen.map { [$0] } ?? []) + group.filter { $0.id != chosen?.id }
      let groupLogo = preferredLogo(ordered.flatMap(\.sightings))
      let candidateIDs = group.map(\.id)
      let opponentID = nodes.lazy.compactMap { node -> EntityID? in
        if case .opponent(let id) = node { return id }
        return nil
      }.first
      if let opponentID, let opponent = opponents[opponentID] {
        let rename = chosen?.name
        let logo = opponent.logoFile == nil ? groupLogo : nil
        if rename == nil && others.isEmpty && logo == nil { continue }
        items.append(
          OpponentImportPlan.Item(
            action: .update(opponentID: opponentID, rename: rename, addAliases: others), logo: logo,
            candidateIDs: candidateIDs))
      } else if let chosen {
        items.append(
          OpponentImportPlan.Item(
            action: .create(name: chosen.name, aliases: others), logo: groupLogo, candidateIDs: candidateIDs))
      }
    }
    return items
  }

  func conflict(_ pairIDs: [String]) -> OpponentPlanError {
    let ids = Self.unique(pairIDs)
    let involved = takenPairs.map(\.pair).filter { ids.contains($0.id) }
    let names = Self.unique(involved.flatMap { [$0.firstName, $0.secondName] })
    return .conflictingChoices(pairIDs: ids, names: names)
  }

  static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }
}
