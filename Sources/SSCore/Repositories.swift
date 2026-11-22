import Foundation

// Repository protocols: Sendable, synchronous, throwing. The data is tiny and the database queue is
// thread-safe, so callers may use them from any isolation, including the main actor.
//
// Common rules for every implementation (the real one in SSData and the fakes in SSCoreFakes):
// - Inputs are drafts; the repository calls `validated()` and throws `AppError.validation` for the
//   first problem, so a repository never stores an invalid value.
// - `get` and every method taking an id throw `AppError.notFound` for an unknown id.
// - Errors are always `AppError`.

/// First-team rule: whenever at least one team exists, **exactly one** team has `isFirstTeam == true`.
/// - `create` with `isFirstTeam == true` moves the flag to the new team; the first team ever created
///   gets the flag even when the draft does not ask for it.
/// - `update` with `isFirstTeam == true` moves the flag to that team (every other team loses it).
/// - `update` with `isFirstTeam == false` on the current first team throws
///   `AppError.firstTeamRequired`: choose another first team instead.
/// - `delete` of the first team throws `AppError.firstTeamCannotBeDeleted` while other teams exist
///   (deleting the only team is allowed).
///
/// Widget-id rule (T4.2): `create` and `update` throw `AppError.validation(field: .tuttocampoWidgetID, …)`
/// with `AppError.widgetIDInUse(by:)` when another team already has the same `tuttocampoWidgetID`
/// (compared ignoring case).
///
/// CSI-page rule (T4.8): `create` and `update` throw `AppError.validation(field: .csiPageURL, …)` with
/// `AppError.csiPageURLInUse(by:)` when another team already has a `csiPageURL` with the same
/// `csiPageKey` (the query and the case are ignored). A team may save its own page again.
public protocol TeamRepository: Sendable {
  /// All teams, ordered by `sortOrder`.
  func list() throws -> [Team]
  func get(id: EntityID) throws -> Team
  /// Appends the team at the end: `sortOrder` = highest existing `sortOrder` + 1 (0 for the first
  /// team). Follows the first-team rule.
  func create(_ draft: TeamDraft) throws -> Team
  /// Keeps `id` and `sortOrder`. Follows the first-team rule.
  func update(id: EntityID, with draft: TeamDraft) throws -> Team
  /// Throws `AppError.conflict` (Italian message) when the team has matches, and
  /// `AppError.firstTeamCannotBeDeleted` per the first-team rule.
  func delete(id: EntityID) throws
  /// `ids` in the new order; each team's `sortOrder` becomes its index. Must list every team.
  func reorder(ids: [EntityID]) throws
}

public protocol OpponentRepository: Sendable {
  /// All opponents, ordered by name (case- and accent-insensitive).
  func list() throws -> [Opponent]
  func get(id: EntityID) throws -> Opponent
  func create(_ draft: OpponentDraft) throws -> Opponent
  func update(id: EntityID, with draft: OpponentDraft) throws -> Opponent
  /// Throws `AppError.conflict` (Italian message) when the opponent has matches. Does not remove the
  /// logo file: the caller does that through `LogoStore.remove` after a successful delete.
  func delete(id: EntityID) throws
  /// Opponents whose name, short name or an alias matches `query` per `textMatches(query:in:)`,
  /// ordered like `list()`. An empty query returns every opponent.
  func search(_ query: String) throws -> [Opponent]
  /// Number of matches per opponent id. Opponents with no matches may be absent (read as 0).
  func matchCounts() throws -> [EntityID: Int]
}

/// Result of `MatchRepository.upsertFromImport`.
public struct ImportSummary: Sendable, Equatable, Hashable {
  public var inserted: Int
  public var updated: Int
  /// Drafts that matched a locked match and were left alone.
  public var skippedLocked: Int

  public init(inserted: Int, updated: Int, skippedLocked: Int) {
    self.inserted = inserted
    self.updated = updated
    self.skippedLocked = skippedLocked
  }
}

public protocol MatchRepository: Sendable {
  /// Matches with `from <= date <= to` (both inclusive), optionally for one team, as `MatchDetail`
  /// values ordered by `MatchDetail.scheduleOrder`.
  func list(from: DayDate, to: DayDate, teamID: EntityID?) throws -> [MatchDetail]
  func get(id: EntityID) throws -> MatchDetail
  /// Number of matches, optionally only those from one source (`nil` = all). Used for "the database
  /// has no matches at all" and for "demo data is loaded".
  func count(source: MatchSource?) throws -> Int
  /// Throws `AppError.validation(field: .team / .opponent, …)` when the team or opponent does not exist.
  func create(_ draft: MatchDraft) throws -> Match
  /// Keeps `id` and `createdAt`, sets `updatedAt`. Works on locked matches too.
  func update(id: EntityID, with draft: MatchDraft) throws -> Match
  func delete(id: EntityID) throws
  /// Deletes every match from `source`, locked ones included. Returns how many were deleted.
  func deleteAll(source: MatchSource) throws -> Int
  /// A copy of the match on `date` with a new id: status `.scheduled`, no score, no half-time score,
  /// not locked, source `.manual`; team, opponent, time, home/away, venue, competition, round and
  /// notes are kept.
  func duplicate(id: EntityID, to date: DayDate) throws -> Match
  /// For each draft: a match with the same `importKey` (team + date) is updated unless it is locked,
  /// otherwise a new match is inserted. All or nothing: on error nothing is written.
  func upsertFromImport(_ drafts: [MatchDraft]) throws -> ImportSummary
}

public protocol SettingsRepository: Sendable {
  /// The stored settings, or `ClubSettings.defaults` when nothing is stored.
  func load() throws -> ClubSettings
  /// Validates (`validated()`) and stores the normalized settings.
  func save(_ settings: ClubSettings) throws
}

public protocol RenderRepository: Sendable {
  /// Records whose `date` is within the range (each bound inclusive; `nil` = unbounded), newest
  /// `createdAt` first.
  func list(from: DayDate?, to: DayDate?) throws -> [RenderRecord]
  func insert(_ record: RenderRecord) throws
  /// Removes the record only; the PNG file is left on disk (the UI decides about the file).
  func delete(id: EntityID) throws
}
