import Foundation
import GRDB
import SSCore

extension Team {
  init(row: Row, prefix: String = "") {
    self.init(
      id: row[prefix + "id"], name: row[prefix + "name"], shortLabel: row[prefix + "short_label"],
      sortOrder: row[prefix + "sort_order"], isFirstTeam: row[prefix + "is_first_team"],
      isActive: row[prefix + "is_active"],
      tuttocampoWidgetID: row[prefix + "tuttocampo_widget_id"])
  }
}

struct TeamStore: TeamRepository {
  let database: AppDatabase

  func list() throws -> [Team] {
    try database.read { db in try Self.all(db) }
  }

  func get(id: EntityID) throws -> Team {
    try database.read { db in try Self.fetch(db, id: id) }
  }

  func create(_ draft: TeamDraft) throws -> Team {
    let draft = try draft.validated()
    return try database.write { db in
      try Self.checkWidgetID(db, draft.tuttocampoWidgetID, excluding: nil)
      let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM teams") ?? 0
      let maxOrder = try Int.fetchOne(db, sql: "SELECT MAX(sort_order) FROM teams")
      // The first team ever created is the first team, whatever the draft says.
      let isFirst = draft.isFirstTeam || count == 0
      if isFirst { try db.execute(sql: "UPDATE teams SET is_first_team = 0") }
      let team = Team(
        id: newEntityID(), name: draft.name, shortLabel: draft.shortLabel, sortOrder: (maxOrder ?? -1) + 1,
        isFirstTeam: isFirst, isActive: draft.isActive, tuttocampoWidgetID: draft.tuttocampoWidgetID)
      try db.execute(
        sql: """
          INSERT INTO teams (id, name, short_label, sort_order, is_first_team, is_active, tuttocampo_widget_id)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          team.id, team.name, team.shortLabel, team.sortOrder, team.isFirstTeam, team.isActive,
          team.tuttocampoWidgetID,
        ])
      return team
    }
  }

  func update(id: EntityID, with draft: TeamDraft) throws -> Team {
    let draft = try draft.validated()
    return try database.write { db in
      let existing = try Self.fetch(db, id: id)
      if existing.isFirstTeam && !draft.isFirstTeam { throw AppError.firstTeamRequired }
      try Self.checkWidgetID(db, draft.tuttocampoWidgetID, excluding: id)
      if draft.isFirstTeam {
        try db.execute(sql: "UPDATE teams SET is_first_team = 0 WHERE id <> ?", arguments: [id])
      }
      try db.execute(
        sql: """
          UPDATE teams SET name = ?, short_label = ?, is_first_team = ?, is_active = ?, tuttocampo_widget_id = ?
          WHERE id = ?
          """,
        arguments: [
          draft.name, draft.shortLabel, draft.isFirstTeam, draft.isActive, draft.tuttocampoWidgetID, id,
        ])
      return try Self.fetch(db, id: id)
    }
  }

  func delete(id: EntityID) throws {
    try database.write { db in
      let existing = try Self.fetch(db, id: id)
      let matches = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM matches WHERE team_id = ?", arguments: [id]) ?? 0
      if matches > 0 { throw AppError.conflict(message: DataStrings.teamHasMatches) }
      let others = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM teams WHERE id <> ?", arguments: [id]) ?? 0
      if existing.isFirstTeam && others > 0 { throw AppError.firstTeamCannotBeDeleted }
      try db.execute(sql: "DELETE FROM teams WHERE id = ?", arguments: [id])
    }
  }

  func reorder(ids: [EntityID]) throws {
    try database.write { db in
      let existing = Set(try String.fetchAll(db, sql: "SELECT id FROM teams"))
      guard ids.count == existing.count, Set(ids) == existing else {
        throw AppError.conflict(message: DataStrings.reorderMismatch)
      }
      for (order, id) in ids.enumerated() {
        try db.execute(sql: "UPDATE teams SET sort_order = ? WHERE id = ?", arguments: [order, id])
      }
    }
  }

  /// Throws `AppError.widgetIDInUse(by:)` when another team has `widgetID` (ignoring case). The unique
  /// index is only the safety net.
  static func checkWidgetID(_ db: Database, _ widgetID: String?, excluding id: EntityID?) throws {
    guard let widgetID else { return }
    let owner = try String.fetchOne(
      db, sql: "SELECT name FROM teams WHERE tuttocampo_widget_id = ? COLLATE NOCASE AND id IS NOT ?",
      arguments: [widgetID, id])
    if let owner { throw AppError.widgetIDInUse(by: owner) }
  }

  static func all(_ db: Database) throws -> [Team] {
    try Row.fetchAll(db, sql: "SELECT * FROM teams ORDER BY sort_order, id").map { Team(row: $0) }
  }

  static func fetch(_ db: Database, id: EntityID) throws -> Team {
    guard let row = try Row.fetchOne(db, sql: "SELECT * FROM teams WHERE id = ?", arguments: [id]) else {
      throw AppError.notFound
    }
    return Team(row: row)
  }
}
