import Foundation
import SSCore
import Synchronization

/// Shared in-memory state behind the fake repositories. Thread-safe through a `Mutex`, so the
/// repositories are `Sendable` without `@unchecked`.
public final class FakeDatabase: Sendable {
  struct State {
    var settings: ClubSettings?
    var teams: [Team]
    var opponents: [Opponent]
    var matches: [Match]
    var renders: [RenderRecord]
    /// T4.9: the stored team lists (`FakeSourceTeamListRepository`), at most one per team and source.
    var sourceTeamLists: [SourceTeamList] = []
  }

  let state: Mutex<State>
  /// Clock used for `createdAt` / `updatedAt`; tests may fix it.
  let now: @Sendable () -> Date

  /// `settings` stays "not stored" (so `load()` returns `ClubSettings.defaults`) when `nil`.
  public init(
    settings: ClubSettings? = nil, teams: [Team] = [], opponents: [Opponent] = [], matches: [Match] = [],
    renders: [RenderRecord] = [], now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.state = Mutex(
      State(settings: settings, teams: teams, opponents: opponents, matches: matches, renders: renders))
    self.now = now
  }

  /// A database filled with a data set. Render `file` paths are used as given.
  public convenience init(_ dataSet: FakeDataSet, now: @escaping @Sendable () -> Date = { Date() }) {
    self.init(
      settings: dataSet.settings, teams: dataSet.teams, opponents: dataSet.opponents, matches: dataSet.matches,
      renders: dataSet.renders, now: now)
  }

  func read<Result>(_ body: (State) throws -> Result) rethrows -> Result {
    try state.withLock { try body($0) }
  }

  func write<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
    try state.withLock { try body(&$0) }
  }
}

extension FakeDatabase.State {
  func detail(for match: Match) throws -> MatchDetail {
    guard let team = teams.first(where: { $0.id == match.teamID }),
      let opponent = opponents.first(where: { $0.id == match.opponentID })
    else { throw AppError.notFound }
    return MatchDetail(match: match, team: team, opponent: opponent)
  }

  func checkReferences(_ draft: MatchDraft) throws {
    guard teams.contains(where: { $0.id == draft.teamID }) else {
      throw AppError.validation(field: .team, message: FakeStrings.unknownTeam)
    }
    guard opponents.contains(where: { $0.id == draft.opponentID }) else {
      throw AppError.validation(field: .opponent, message: FakeStrings.unknownOpponent)
    }
  }
}

func sortedOpponents(_ opponents: [Opponent]) -> [Opponent] {
  opponents.sorted { lhs, rhs in
    let left = searchKey(lhs.name)
    let right = searchKey(rhs.name)
    return left == right ? lhs.id < rhs.id : left < right
  }
}

func makeMatch(_ draft: MatchDraft, id: EntityID, createdAt: Date, updatedAt: Date) -> Match {
  Match(
    id: id, teamID: draft.teamID, opponentID: draft.opponentID, date: draft.date, time: draft.time,
    isHome: draft.isHome, venue: draft.venue, competition: draft.competition, round: draft.round,
    status: draft.status, score: draft.score, halfTime: draft.halfTime, notes: draft.notes, source: draft.source,
    isLocked: draft.isLocked, createdAt: createdAt, updatedAt: updatedAt)
}

// MARK: - Teams

public struct FakeTeamRepository: TeamRepository {
  public let database: FakeDatabase
  public init(database: FakeDatabase) { self.database = database }

  public func list() throws -> [Team] {
    database.read { $0.teams.sorted { $0.sortOrder < $1.sortOrder } }
  }

  public func get(id: EntityID) throws -> Team {
    try database.read { state in
      guard let team = state.teams.first(where: { $0.id == id }) else { throw AppError.notFound }
      return team
    }
  }

  public func create(_ draft: TeamDraft) throws -> Team {
    let draft = try draft.validated()
    return try database.write { state in
      try checkWidgetID(draft.tuttocampoWidgetID, of: nil, in: state)
      try checkCSIPage(draft.csiPageURL, of: nil, in: state)
      let isFirstTeam = draft.isFirstTeam || !state.teams.contains(where: \.isFirstTeam)
      if isFirstTeam { clearFirstTeam(in: &state) }
      let team = Team(
        id: newEntityID(), name: draft.name, shortLabel: draft.shortLabel,
        sortOrder: (state.teams.map(\.sortOrder).max() ?? -1) + 1, isFirstTeam: isFirstTeam,
        isActive: draft.isActive, tuttocampoWidgetID: draft.tuttocampoWidgetID, csiPageURL: draft.csiPageURL)
      state.teams.append(team)
      return team
    }
  }

  public func update(id: EntityID, with draft: TeamDraft) throws -> Team {
    let draft = try draft.validated()
    return try database.write { state in
      guard let index = state.teams.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
      if state.teams[index].isFirstTeam && !draft.isFirstTeam { throw AppError.firstTeamRequired }
      try checkWidgetID(draft.tuttocampoWidgetID, of: id, in: state)
      try checkCSIPage(draft.csiPageURL, of: id, in: state)
      if draft.isFirstTeam { clearFirstTeam(in: &state) }
      state.teams[index].name = draft.name
      state.teams[index].shortLabel = draft.shortLabel
      state.teams[index].isFirstTeam = draft.isFirstTeam
      state.teams[index].isActive = draft.isActive
      state.teams[index].tuttocampoWidgetID = draft.tuttocampoWidgetID
      state.teams[index].csiPageURL = draft.csiPageURL
      return state.teams[index]
    }
  }

  public func delete(id: EntityID) throws {
    try database.write { state in
      guard let index = state.teams.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
      if state.matches.contains(where: { $0.teamID == id }) {
        throw AppError.conflict(message: FakeStrings.teamHasMatches)
      }
      if state.teams[index].isFirstTeam && state.teams.count > 1 { throw AppError.firstTeamCannotBeDeleted }
      state.teams.remove(at: index)
      state.sourceTeamLists.removeAll { $0.teamID == id }
    }
  }

  public func reorder(ids: [EntityID]) throws {
    try database.write { state in
      guard Set(ids) == Set(state.teams.map(\.id)), ids.count == state.teams.count else {
        throw AppError.conflict(message: FakeStrings.reorderMismatch)
      }
      for (order, id) in ids.enumerated() {
        if let index = state.teams.firstIndex(where: { $0.id == id }) { state.teams[index].sortOrder = order }
      }
    }
  }

  private func clearFirstTeam(in state: inout FakeDatabase.State) {
    for index in state.teams.indices { state.teams[index].isFirstTeam = false }
  }

  /// The widget-id rule: no other team may use the same id (ignoring case).
  private func checkWidgetID(_ widgetID: String?, of teamID: EntityID?, in state: FakeDatabase.State) throws {
    guard let widgetID else { return }
    if let other = state.teams.first(where: {
      $0.id != teamID && $0.tuttocampoWidgetID?.caseInsensitiveCompare(widgetID) == .orderedSame
    }) {
      throw AppError.widgetIDInUse(by: other.name)
    }
  }

  /// The CSI-page rule: no other team may store a page with the same `csiPageKey`.
  private func checkCSIPage(_ pageURL: String?, of teamID: EntityID?, in state: FakeDatabase.State) throws {
    guard let key = pageURL.flatMap(csiPageKey) else { return }
    if let other = state.teams.first(where: { $0.id != teamID && $0.csiPageURL.flatMap(csiPageKey) == key }) {
      throw AppError.csiPageURLInUse(by: other.name)
    }
  }
}

// MARK: - Opponents

public struct FakeOpponentRepository: OpponentRepository {
  public let database: FakeDatabase
  public init(database: FakeDatabase) { self.database = database }

  public func list() throws -> [Opponent] { database.read { sortedOpponents($0.opponents) } }

  public func get(id: EntityID) throws -> Opponent {
    try database.read { state in
      guard let opponent = state.opponents.first(where: { $0.id == id }) else { throw AppError.notFound }
      return opponent
    }
  }

  public func create(_ draft: OpponentDraft) throws -> Opponent {
    let draft = try draft.validated()
    let opponent = Opponent(
      id: newEntityID(), name: draft.name, shortName: draft.shortName, aliases: draft.aliases,
      logoFile: draft.logoFile)
    database.write { $0.opponents.append(opponent) }
    return opponent
  }

  public func update(id: EntityID, with draft: OpponentDraft) throws -> Opponent {
    let draft = try draft.validated()
    return try database.write { state in
      guard let index = state.opponents.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
      state.opponents[index] = Opponent(
        id: id, name: draft.name, shortName: draft.shortName, aliases: draft.aliases, logoFile: draft.logoFile)
      return state.opponents[index]
    }
  }

  public func delete(id: EntityID) throws {
    try database.write { state in
      guard let index = state.opponents.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
      if state.matches.contains(where: { $0.opponentID == id }) {
        throw AppError.conflict(message: FakeStrings.opponentHasMatches)
      }
      state.opponents.remove(at: index)
    }
  }

  public func search(_ query: String) throws -> [Opponent] {
    try list().filter { opponent in
      textMatches(query: query, in: [opponent.name, opponent.shortName ?? ""] + opponent.aliases)
    }
  }

  public func matchCounts() throws -> [EntityID: Int] {
    database.read { state in
      state.matches.reduce(into: [:]) { counts, match in counts[match.opponentID, default: 0] += 1 }
    }
  }

  /// All or nothing: the items are applied to a copy of the opponents, which replaces them only at the end.
  public func applyImport(_ plan: OpponentImportPlan) throws -> [Opponent] {
    try database.write { state in
      var working = state.opponents
      var results: [Opponent] = []
      for item in plan.items {
        let index: Int?
        switch item.action {
        case .create: index = nil
        case .update(let id, _, _):
          guard let found = working.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
          index = found
        }
        guard let draft = try item.action.draft(current: index.map { working[$0] })?.validated() else {
          throw AppError.notFound
        }
        let opponent = Opponent(
          id: index.map { working[$0].id } ?? newEntityID(), name: draft.name, shortName: draft.shortName,
          aliases: draft.aliases, logoFile: draft.logoFile)
        if let index { working[index] = opponent } else { working.append(opponent) }
        results.append(opponent)
      }
      state.opponents = working
      return results
    }
  }
}

// MARK: - Source team lists

public struct FakeSourceTeamListRepository: SourceTeamListRepository {
  public let database: FakeDatabase
  public init(database: FakeDatabase) { self.database = database }

  public func save(teamID: EntityID, source: TeamListSource, teams: [SourceTeam], readAt: Date) throws {
    try database.write { state in
      guard state.teams.contains(where: { $0.id == teamID }) else { throw AppError.notFound }
      state.sourceTeamLists.removeAll { $0.teamID == teamID && $0.source == source }
      state.sourceTeamLists.append(SourceTeamList(teamID: teamID, source: source, readAt: readAt, teams: teams))
    }
  }

  public func latest(teamID: EntityID, source: TeamListSource) throws -> SourceTeamList? {
    try database.read { state in
      guard state.teams.contains(where: { $0.id == teamID }) else { throw AppError.notFound }
      return state.sourceTeamLists.first { $0.teamID == teamID && $0.source == source }
    }
  }
}

// MARK: - Matches

public struct FakeMatchRepository: MatchRepository {
  public let database: FakeDatabase
  public init(database: FakeDatabase) { self.database = database }

  public func list(from: DayDate, to: DayDate, teamID: EntityID?) throws -> [MatchDetail] {
    try database.read { state in
      try state.matches
        .filter { $0.date >= from && $0.date <= to && (teamID == nil || $0.teamID == teamID) }
        .map { try state.detail(for: $0) }
        .sorted(by: MatchDetail.scheduleOrder)
    }
  }

  public func get(id: EntityID) throws -> MatchDetail {
    try database.read { state in
      guard let match = state.matches.first(where: { $0.id == id }) else { throw AppError.notFound }
      return try state.detail(for: match)
    }
  }

  public func count(source: MatchSource?) throws -> Int {
    database.read { state in state.matches.filter { source == nil || $0.source == source }.count }
  }

  public func create(_ draft: MatchDraft) throws -> Match {
    let draft = try draft.validated()
    let now = database.now()
    return try database.write { state in
      try state.checkReferences(draft)
      let match = makeMatch(draft, id: newEntityID(), createdAt: now, updatedAt: now)
      state.matches.append(match)
      return match
    }
  }

  public func update(id: EntityID, with draft: MatchDraft) throws -> Match {
    let draft = try draft.validated()
    let now = database.now()
    return try database.write { state in
      guard let index = state.matches.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
      try state.checkReferences(draft)
      state.matches[index] = makeMatch(draft, id: id, createdAt: state.matches[index].createdAt, updatedAt: now)
      return state.matches[index]
    }
  }

  public func delete(id: EntityID) throws {
    try database.write { state in
      guard let index = state.matches.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
      state.matches.remove(at: index)
    }
  }

  public func deleteAll(source: MatchSource) throws -> Int {
    database.write { state in
      let before = state.matches.count
      state.matches.removeAll { $0.source == source }
      return before - state.matches.count
    }
  }

  public func duplicate(id: EntityID, to date: DayDate) throws -> Match {
    let now = database.now()
    return try database.write { state in
      guard let original = state.matches.first(where: { $0.id == id }) else { throw AppError.notFound }
      var draft = MatchDraft(original)
      draft.date = date
      draft.status = .scheduled
      draft.score = nil
      draft.halfTime = nil
      draft.isLocked = false
      draft.source = .manual
      let copy = makeMatch(draft, id: newEntityID(), createdAt: now, updatedAt: now)
      state.matches.append(copy)
      return copy
    }
  }

  public func upsertFromImport(_ drafts: [MatchDraft]) throws -> ImportSummary {
    let drafts = try drafts.map { try $0.validated() }
    let now = database.now()
    return try database.write { state in
      for draft in drafts { try state.checkReferences(draft) }
      var working = state.matches
      var summary = ImportSummary(inserted: 0, updated: 0, skippedLocked: 0)
      for draft in drafts {
        if let index = working.firstIndex(where: { MatchDraft($0).importKey == draft.importKey }) {
          if working[index].isLocked {
            summary.skippedLocked += 1
          } else {
            working[index] = makeMatch(
              draft, id: working[index].id, createdAt: working[index].createdAt, updatedAt: now)
            summary.updated += 1
          }
        } else {
          working.append(makeMatch(draft, id: newEntityID(), createdAt: now, updatedAt: now))
          summary.inserted += 1
        }
      }
      state.matches = working
      return summary
    }
  }
}

// MARK: - Settings and renders

public struct FakeSettingsRepository: SettingsRepository {
  public let database: FakeDatabase
  public init(database: FakeDatabase) { self.database = database }

  public func load() throws -> ClubSettings { database.read { $0.settings ?? .defaults } }

  public func save(_ settings: ClubSettings) throws {
    let settings = try settings.validated()
    database.write { $0.settings = settings }
  }
}

public struct FakeRenderRepository: RenderRepository {
  public let database: FakeDatabase
  public init(database: FakeDatabase) { self.database = database }

  public func list(from: DayDate?, to: DayDate?) throws -> [RenderRecord] {
    database.read { state in
      state.renders
        .filter { record in (from.map { record.date >= $0 } ?? true) && (to.map { record.date <= $0 } ?? true) }
        .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
    }
  }

  public func insert(_ record: RenderRecord) throws {
    database.write { state in
      state.renders.removeAll { $0.id == record.id }
      state.renders.append(record)
    }
  }

  public func delete(id: EntityID) throws {
    try database.write { state in
      guard let index = state.renders.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
      state.renders.remove(at: index)
    }
  }
}
