import Foundation
import GRDB
import SSCore

extension Match {
  init(row: Row) throws {
    func score(_ us: String, _ them: String) -> Score? {
      guard let usValue: Int = row[us], let themValue: Int = row[them] else { return nil }
      return Score(us: usValue, them: themValue)
    }
    let time: String? = row["time"]
    let dateText: String = row["date"]
    let statusText: String = row["status"]
    let sourceText: String = row["source"]
    self.init(
      id: row["id"], teamID: row["team_id"], opponentID: row["opponent_id"], date: try DayDate(dateText),
      time: try time.map { try ClockTime($0) }, isHome: row["is_home"], venue: row["venue"],
      competition: row["competition"], round: row["round"], status: MatchStatus(rawValue: statusText) ?? .scheduled,
      score: score("score_us", "score_them"), halfTime: score("half_time_us", "half_time_them"), notes: row["notes"],
      source: MatchSource(rawValue: sourceText) ?? .manual, isLocked: row["is_locked"],
      createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"]),
      updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"]))
  }
}

struct MatchStore: MatchRepository {
  let database: AppDatabase

  private static let detailSelect = """
    SELECT m.*,
      t.id AS t_id, t.name AS t_name, t.short_label AS t_short_label, t.sort_order AS t_sort_order,
      t.is_first_team AS t_is_first_team, t.is_active AS t_is_active,
      o.id AS o_id, o.name AS o_name, o.short_name AS o_short_name, o.aliases AS o_aliases,
      o.logo_file AS o_logo_file
    FROM matches m
    JOIN teams t ON t.id = m.team_id
    JOIN opponents o ON o.id = m.opponent_id
    """

  private static func detail(_ row: Row) throws -> MatchDetail {
    MatchDetail(
      match: try Match(row: row), team: Team(row: row, prefix: "t_"), opponent: Opponent(row: row, prefix: "o_"))
  }

  func list(from: DayDate, to: DayDate, teamID: EntityID?) throws -> [MatchDetail] {
    try database.read { db in
      var sql = Self.detailSelect + " WHERE m.date >= ? AND m.date <= ?"
      var arguments: [any DatabaseValueConvertible] = [from.value, to.value]
      if let teamID {
        sql += " AND m.team_id = ?"
        arguments.append(teamID)
      }
      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
      return try rows.map(Self.detail).sorted(by: MatchDetail.scheduleOrder)
    }
  }

  func get(id: EntityID) throws -> MatchDetail {
    try database.read { db in try Self.fetchDetail(db, id: id) }
  }

  func count(source: MatchSource?) throws -> Int {
    try database.read { db in
      if let source {
        return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM matches WHERE source = ?", arguments: [source.rawValue])
          ?? 0
      }
      return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM matches") ?? 0
    }
  }

  func create(_ draft: MatchDraft) throws -> Match {
    let draft = try draft.validated()
    let now = Date()
    return try database.write { db in
      try Self.checkReferences(db, draft)
      let match = Self.makeMatch(draft, id: newEntityID(), createdAt: now, updatedAt: now)
      try Self.insert(db, match)
      return match
    }
  }

  func update(id: EntityID, with draft: MatchDraft) throws -> Match {
    let draft = try draft.validated()
    let now = Date()
    return try database.write { db in
      let existing = try Self.fetchDetail(db, id: id).match
      try Self.checkReferences(db, draft)
      let match = Self.makeMatch(draft, id: id, createdAt: existing.createdAt, updatedAt: now)
      try Self.write(db, match)
      return match
    }
  }

  func delete(id: EntityID) throws {
    try database.write { db in
      _ = try Self.fetchDetail(db, id: id)
      try db.execute(sql: "DELETE FROM matches WHERE id = ?", arguments: [id])
    }
  }

  func deleteAll(source: MatchSource) throws -> Int {
    try database.write { db in
      try db.execute(sql: "DELETE FROM matches WHERE source = ?", arguments: [source.rawValue])
      return db.changesCount
    }
  }

  func duplicate(id: EntityID, to date: DayDate) throws -> Match {
    let now = Date()
    return try database.write { db in
      let original = try Self.fetchDetail(db, id: id).match
      var draft = MatchDraft(original)
      draft.date = date
      draft.status = .scheduled
      // C4: notes hold the scorers once a result exists, so they are not carried over.
      if original.score != nil || original.halfTime != nil { draft.notes = nil }
      draft.score = nil
      draft.halfTime = nil
      draft.isLocked = false
      draft.source = .manual
      let copy = Self.makeMatch(draft, id: newEntityID(), createdAt: now, updatedAt: now)
      try Self.insert(db, copy)
      return copy
    }
  }

  func upsertFromImport(_ drafts: [MatchDraft]) throws -> ImportSummary {
    let drafts = try drafts.map { try $0.validated() }
    let now = Date()
    // One write transaction: an error rolls everything back.
    return try database.write { db in
      var summary = ImportSummary(inserted: 0, updated: 0, skippedLocked: 0)
      for draft in drafts {
        try Self.checkReferences(db, draft)
        let existing = try Row.fetchOne(
          db, sql: "SELECT * FROM matches WHERE team_id = ? AND date = ? ORDER BY created_at, id LIMIT 1",
          arguments: [draft.teamID, draft.date.value])
        if let existing {
          let current = try Match(row: existing)
          if current.isLocked {
            summary.skippedLocked += 1
          } else {
            try Self.write(db, Self.makeMatch(draft, id: current.id, createdAt: current.createdAt, updatedAt: now))
            summary.updated += 1
          }
        } else {
          try Self.insert(db, Self.makeMatch(draft, id: newEntityID(), createdAt: now, updatedAt: now))
          summary.inserted += 1
        }
      }
      return summary
    }
  }

  // MARK: Helpers

  private static func fetchDetail(_ db: Database, id: EntityID) throws -> MatchDetail {
    guard let row = try Row.fetchOne(db, sql: detailSelect + " WHERE m.id = ?", arguments: [id]) else {
      throw AppError.notFound
    }
    return try detail(row)
  }

  private static func checkReferences(_ db: Database, _ draft: MatchDraft) throws {
    let teamExists =
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM teams WHERE id = ?", arguments: [draft.teamID]) ?? 0
    if teamExists == 0 { throw AppError.validation(field: .team, message: DataStrings.unknownTeam) }
    let opponentExists =
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM opponents WHERE id = ?", arguments: [draft.opponentID]) ?? 0
    if opponentExists == 0 { throw AppError.validation(field: .opponent, message: DataStrings.unknownOpponent) }
  }

  private static func makeMatch(_ draft: MatchDraft, id: EntityID, createdAt: Date, updatedAt: Date) -> Match {
    Match(
      id: id, teamID: draft.teamID, opponentID: draft.opponentID, date: draft.date, time: draft.time,
      isHome: draft.isHome, venue: draft.venue, competition: draft.competition, round: draft.round,
      status: draft.status, score: draft.score, halfTime: draft.halfTime, notes: draft.notes,
      source: draft.source, isLocked: draft.isLocked, createdAt: createdAt, updatedAt: updatedAt)
  }

  private static func arguments(_ match: Match) -> StatementArguments {
    [
      match.id, match.teamID, match.opponentID, match.date.value, match.time?.value, match.isHome, match.venue,
      match.competition, match.round, match.status.rawValue, match.score?.us, match.score?.them,
      match.halfTime?.us, match.halfTime?.them, match.notes, match.source.rawValue, match.isLocked,
      match.createdAt.timeIntervalSinceReferenceDate, match.updatedAt.timeIntervalSinceReferenceDate,
    ]
  }

  private static func insert(_ db: Database, _ match: Match) throws {
    try db.execute(
      sql: """
        INSERT INTO matches (id, team_id, opponent_id, date, time, is_home, venue, competition, round, status,
          score_us, score_them, half_time_us, half_time_them, notes, source, is_locked, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: arguments(match))
  }

  /// Replaces every column of an existing row.
  private static func write(_ db: Database, _ match: Match) throws {
    try db.execute(
      sql: """
        UPDATE matches SET team_id = ?2, opponent_id = ?3, date = ?4, time = ?5, is_home = ?6, venue = ?7,
          competition = ?8, round = ?9, status = ?10, score_us = ?11, score_them = ?12, half_time_us = ?13,
          half_time_them = ?14, notes = ?15, source = ?16, is_locked = ?17, created_at = ?18, updated_at = ?19
        WHERE id = ?1
        """,
      arguments: arguments(match))
  }
}
