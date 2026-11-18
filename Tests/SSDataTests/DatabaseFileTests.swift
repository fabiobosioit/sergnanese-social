import Foundation
import GRDB
import SSCore
import Testing

@testable import SSData

@Suite struct DatabaseFileTests {
  @Test func openingAnEmptyFileCreatesTheSchemaAndReopeningChangesNothing() throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("db.sqlite")

    let first = try AppDatabase.open(at: url)
    let team = try first.teams.create(TeamDraft(name: "A", shortLabel: "A"))
    let tables = try first.queue.read { db in
      try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
    }
    #expect(Set(tables).isSuperset(of: ["teams", "opponents", "matches", "settings", "renders"]))
    let indexes = try first.queue.read { db in
      try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'")
    }
    #expect(indexes.contains("matches_date") && indexes.contains("matches_team_date"))
    #expect(indexes.contains("renders_created_at"))
    let schemaBefore = try first.queue.read { db in
      try String.fetchAll(db, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name")
    }
    let migrationsBefore = try first.queue.read { db in
      try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
    }
    #expect(migrationsBefore == ["v1"])

    let second = try AppDatabase.open(at: url)
    let schemaAfter = try second.queue.read { db in
      try String.fetchAll(db, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name")
    }
    #expect(schemaAfter == schemaBefore)
    #expect(try second.teams.list() == [team])
    #expect(
      try second.queue.read { db in try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations") } == ["v1"])
  }

  @Test func foreignKeysAreOn() throws {
    let db = try AppDatabase.inMemory()
    let enabled = try db.queue.read { db in try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") }
    #expect(enabled == true)
    // Direct SQL bypassing the repository guard is still refused by the database.
    let f = try Fixture()
    _ = try f.db.matches.create(f.draft())
    #expect(throws: (any Error).self) {
      try f.db.queue.write { db in try db.execute(sql: "DELETE FROM teams WHERE id = ?", arguments: [f.first.id]) }
    }
  }

  @Test func backupIsWrittenWhenMissingOrOldAndPruned() throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let backups = folder.appendingPathComponent("backups")
    let db = try AppDatabase.open(at: folder.appendingPathComponent("db.sqlite"))
    _ = try db.teams.create(TeamDraft(name: "A", shortLabel: "A"))

    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let first = try #require(try db.backUpIfNeeded(into: backups, now: start))
    // The backup is a real database with the data in it.
    let copy = try DatabaseQueue(path: first.path)
    #expect(try copy.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM teams") } == 1)

    // Six days later: still fresh, nothing new.
    #expect(try db.backUpIfNeeded(into: backups, now: start.addingTimeInterval(6 * 86400)) == nil)
    #expect(AppDatabase.backupFiles(in: backups).count == 1)

    // Eight days after each previous backup: a new one every time, only 5 kept.
    var now = start
    for _ in 0..<7 {
      now = now.addingTimeInterval(8 * 86400)
      #expect(try db.backUpIfNeeded(into: backups, now: now) != nil)
    }
    #expect(AppDatabase.backupFiles(in: backups).count == 5)
    #expect(AppDatabase.backupFiles(in: backups).first?.date == now)
  }

  @Test func openWithPathsBacksUpOnFirstOpenOnly() throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let paths = AppPaths(dataFolder: folder, resources: folder, defaultOutputFolder: folder)
    _ = try AppDatabase.open(paths: paths)
    #expect(AppDatabase.backupFiles(in: paths.backups).count == 1)
    _ = try AppDatabase.open(paths: paths)
    #expect(AppDatabase.backupFiles(in: paths.backups).count == 1)
    #expect(paths.latestBackupDate() != nil)
  }
}
