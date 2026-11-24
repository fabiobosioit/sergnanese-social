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
  /// `AppError.firstTeamCannotBeDeleted` per the first-team rule. Deleting a team also deletes its stored team
  /// lists (`SourceTeamListRepository`, T4.9).
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
  /// T4.9: writes every item of `plan` in one transaction, in order, and returns the opponent each item leaves
  /// (one per item, logo-only items included). `.create` follows `create`'s rules; `.update` applies
  /// `OpponentImportPlan.Action.draft(current:)` to the opponent as stored now, then `validated()` (duplicate
  /// aliases and an alias equal to the name are dropped). All or nothing: `AppError.notFound` for an unknown
  /// opponent or `AppError.validation` for an invalid result, and nothing is written. Never deletes an opponent,
  /// never changes a short name or a logo.
  ///
  /// The default implementation (repositories written before T4.9) throws `AppError.io` and writes nothing.
  func applyImport(_ plan: OpponentImportPlan) throws -> [Opponent]
}

extension OpponentRepository {
  /// Throws `AppError.io`: this repository cannot apply an import plan. Nothing is written.
  public func applyImport(_ plan: OpponentImportPlan) throws -> [Opponent] {
    throw AppError.io(message: CoreStrings.opponentImportUnavailable)
  }
}

/// The team lists kept from source pages (T4.9): the CSI hook saves the teams of each CSI page the user reads
/// ("Importa questa pagina"), and "Scarica tutti gli avversari…" reads them back, so no CSI request is ever made
/// for it. Stored in the database (table `source_team_lists`: team id, source, read at, teams as JSON), so a
/// list survives restarts; deleting a team deletes its lists.
public protocol SourceTeamListRepository: Sendable {
  /// Stores `teams` as what `source` listed for our team `teamID` at `readAt`, as
  /// `SourceTeamList(teamID:source:readAt:teams:)` (each team's `teamID` and `source` become the arguments),
  /// replacing the list stored before for the same team and source. Throws `AppError.notFound` for an unknown
  /// team.
  func save(teamID: EntityID, source: TeamListSource, teams: [SourceTeam], readAt: Date) throws
  /// The list stored for the team and source, `nil` when none was saved. Throws `AppError.notFound` for an
  /// unknown team.
  func latest(teamID: EntityID, source: TeamListSource) throws -> SourceTeamList?
}

/// The store `AppServices` uses when none is given: `save` keeps nothing, `latest` finds nothing. Keeps the
/// containers built before T4.9 valid.
@usableFromInline
struct UnavailableSourceTeamListRepository: SourceTeamListRepository {
  @usableFromInline
  init() {}

  @usableFromInline
  func save(teamID: EntityID, source: TeamListSource, teams: [SourceTeam], readAt: Date) throws {}

  @usableFromInline
  func latest(teamID: EntityID, source: TeamListSource) throws -> SourceTeamList? { nil }
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
  /// not locked, source `.manual`; team, opponent, time, home/away, venue, competition and round are
  /// kept. `notes` (the scorers, T4.5) are cleared when the original has a `score` or a `halfTime`,
  /// kept otherwise.
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
