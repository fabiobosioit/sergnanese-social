import Foundation
import GRDB
import SSCore

struct SettingsStore: SettingsRepository {
  let database: AppDatabase

  func load() throws -> ClubSettings {
    try database.read { db in
      let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM settings")
      var stored: [String: String] = [:]
      for row in rows { stored[row["key"]] = row["value"] }
      let defaults = ClubSettings.defaults
      return ClubSettings(
        clubName: stored["clubName"] ?? defaults.clubName,
        clubShortName: stored["clubShortName"] ?? defaults.clubShortName,
        season: stored["season"] ?? defaults.season,
        accentColor: stored["accentColor"] ?? defaults.accentColor,
        socialHandle: stored["socialHandle"] ?? defaults.socialHandle,
        homeVenue: stored["homeVenue"] ?? defaults.homeVenue,
        outputFolder: stored["outputFolder"])
    }
  }

  func save(_ settings: ClubSettings) throws {
    let settings = try settings.validated()
    try database.write { db in
      let values: [(String, String)] = [
        ("clubName", settings.clubName), ("clubShortName", settings.clubShortName), ("season", settings.season),
        ("accentColor", settings.accentColor), ("socialHandle", settings.socialHandle),
        ("homeVenue", settings.homeVenue),
      ]
      for (key, value) in values {
        try db.execute(
          sql: "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
          arguments: [key, value])
      }
      if let folder = settings.outputFolder {
        try db.execute(
          sql:
            "INSERT INTO settings (key, value) VALUES ('outputFolder', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
          arguments: [folder])
      } else {
        try db.execute(sql: "DELETE FROM settings WHERE key = 'outputFolder'")
      }
    }
  }
}

extension RenderRecord {
  fileprivate init(row: Row) throws {
    let pageIndex: Int? = row["page_index"]
    let pageTotal: Int? = row["page_total"]
    var page: PageInfo?
    if let pageIndex, let pageTotal { page = PageInfo(index: pageIndex, total: pageTotal) }
    let matchIDs: String = row["match_ids"]
    let warnings: String = row["warnings"]
    let dateText: String = row["date"]
    self.init(
      id: row["id"], templateID: row["template_id"], templateVersion: row["template_version"],
      matchIDs: decodeJSON([String].self, from: matchIDs) ?? [], date: try DayDate(dateText), page: page,
      file: row["file"], width: row["width"], height: row["height"],
      warnings: decodeJSON([String].self, from: warnings) ?? [],
      createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"]))
  }
}

struct RenderStore: RenderRepository {
  let database: AppDatabase

  func list(from: DayDate?, to: DayDate?) throws -> [RenderRecord] {
    try database.read { db in
      var clauses: [String] = []
      var arguments: [any DatabaseValueConvertible] = []
      if let from {
        clauses.append("date >= ?")
        arguments.append(from.value)
      }
      if let to {
        clauses.append("date <= ?")
        arguments.append(to.value)
      }
      let filter = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
      let rows = try Row.fetchAll(
        db, sql: "SELECT * FROM renders\(filter) ORDER BY created_at DESC, id",
        arguments: StatementArguments(arguments))
      return try rows.map { try RenderRecord(row: $0) }
    }
  }

  func insert(_ record: RenderRecord) throws {
    try database.write { db in
      try db.execute(
        sql: """
          INSERT OR REPLACE INTO renders (id, template_id, template_version, match_ids, date, page_index,
            page_total, file, width, height, warnings, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          record.id, record.templateID, record.templateVersion, encodeJSON(record.matchIDs), record.date.value,
          record.page?.index, record.page?.total, record.file, record.width, record.height,
          encodeJSON(record.warnings), record.createdAt.timeIntervalSinceReferenceDate,
        ])
    }
  }

  func delete(id: EntityID) throws {
    try database.write { db in
      try db.execute(sql: "DELETE FROM renders WHERE id = ?", arguments: [id])
      if db.changesCount == 0 { throw AppError.notFound }
    }
  }
}
