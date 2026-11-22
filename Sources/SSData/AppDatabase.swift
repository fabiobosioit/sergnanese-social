import Foundation
import GRDB
import SSCore

/// The SQLite database of the app. All SQL and every GRDB import of the project live in this target.
///
/// `DatabaseQueue` is `Sendable` and serialises access, so the repositories below are safe to call
/// from any isolation.
public final class AppDatabase: Sendable {
  let queue: DatabaseQueue

  init(queue: DatabaseQueue) throws {
    self.queue = queue
    try Self.migrator.migrate(queue)
  }

  /// An empty in-memory database with the schema applied (tests, tools).
  public static func inMemory() throws -> AppDatabase {
    do {
      return try AppDatabase(queue: DatabaseQueue(configuration: configuration))
    } catch let error as AppError {
      throw error
    } catch {
      throw AppError.io(message: DataStrings.databaseError)
    }
  }

  /// Opens (creating when missing) the database file, with foreign keys on and migrations applied.
  /// When `backupsFolder` is given, writes an automatic backup if the newest one is older than 7 days
  /// and keeps the last 5 (see `backUpIfNeeded`).
  public static func open(at url: URL, backupsFolder: URL? = nil, now: Date = Date()) throws -> AppDatabase {
    let database: AppDatabase
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      database = try AppDatabase(queue: DatabaseQueue(path: url.path, configuration: configuration))
    } catch let error as AppError {
      throw error
    } catch {
      throw AppError.io(message: DataStrings.cannotOpenDatabase(url.path))
    }
    if let backupsFolder { try database.backUpIfNeeded(into: backupsFolder, now: now) }
    return database
  }

  /// Opens the database at `paths.database` and backs up into `paths.backups`.
  public static func open(paths: AppPaths, now: Date = Date()) throws -> AppDatabase {
    try paths.createFolders()
    return try open(at: paths.database, backupsFolder: paths.backups, now: now)
  }

  static var configuration: Configuration {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    return configuration
  }

  // MARK: Repositories

  public var teams: any TeamRepository { TeamStore(database: self) }
  public var opponents: any OpponentRepository { OpponentStore(database: self) }
  public var matches: any MatchRepository { MatchStore(database: self) }
  public var settings: any SettingsRepository { SettingsStore(database: self) }
  public var renders: any RenderRepository { RenderStore(database: self) }

  // MARK: Migrations

  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
      try db.execute(
        sql: """
          CREATE TABLE teams (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            short_label TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            is_first_team INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1
          );
          CREATE TABLE opponents (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            short_name TEXT,
            aliases TEXT NOT NULL DEFAULT '[]',
            logo_file TEXT
          );
          CREATE TABLE matches (
            id TEXT PRIMARY KEY NOT NULL,
            team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE RESTRICT,
            opponent_id TEXT NOT NULL REFERENCES opponents(id) ON DELETE RESTRICT,
            date TEXT NOT NULL,
            time TEXT,
            is_home INTEGER NOT NULL,
            venue TEXT NOT NULL DEFAULT '',
            competition TEXT,
            round INTEGER,
            status TEXT NOT NULL,
            score_us INTEGER,
            score_them INTEGER,
            half_time_us INTEGER,
            half_time_them INTEGER,
            notes TEXT,
            source TEXT NOT NULL,
            is_locked INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
          );
          CREATE INDEX matches_date ON matches(date);
          CREATE INDEX matches_team_date ON matches(team_id, date);
          CREATE INDEX matches_opponent ON matches(opponent_id);
          CREATE TABLE settings (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
          );
          CREATE TABLE renders (
            id TEXT PRIMARY KEY NOT NULL,
            template_id TEXT NOT NULL,
            template_version TEXT NOT NULL,
            match_ids TEXT NOT NULL DEFAULT '[]',
            date TEXT NOT NULL,
            page_index INTEGER,
            page_total INTEGER,
            file TEXT NOT NULL,
            width INTEGER NOT NULL,
            height INTEGER NOT NULL,
            warnings TEXT NOT NULL DEFAULT '[]',
            created_at REAL NOT NULL
          );
          CREATE INDEX renders_created_at ON renders(created_at);
          CREATE INDEX renders_date ON renders(date);
          """)
    }
    // T4.2: the tuttocampo.it widget of a team. Unique ignoring case; many teams may have none.
    migrator.registerMigration("v2") { db in
      try db.execute(
        sql: """
          ALTER TABLE teams ADD COLUMN tuttocampo_widget_id TEXT;
          CREATE UNIQUE INDEX teams_tuttocampo_widget_id
            ON teams(tuttocampo_widget_id COLLATE NOCASE) WHERE tuttocampo_widget_id IS NOT NULL;
          """)
    }
    return migrator
  }

  // MARK: Access helpers

  /// Runs `body` in a write transaction. Any error that is not an `AppError` becomes one.
  func write<T>(_ body: (Database) throws -> T) throws -> T {
    do {
      return try queue.write { db in try body(db) }
    } catch let error as AppError {
      throw error
    } catch {
      throw AppError.io(message: DataStrings.databaseError)
    }
  }

  func read<T>(_ body: (Database) throws -> T) throws -> T {
    do {
      return try queue.read { db in try body(db) }
    } catch let error as AppError {
      throw error
    } catch {
      throw AppError.io(message: DataStrings.databaseError)
    }
  }

  // MARK: Backup

  /// Maximum age of the newest backup before a new one is written.
  static let backupInterval: TimeInterval = 7 * 24 * 3600
  static let backupsKept = 5

  /// Writes a backup with GRDB's backup API when `folder` has no backup newer than 7 days, then keeps
  /// the 5 newest files. Returns the new backup's URL, or `nil` when none was needed.
  @discardableResult
  public func backUpIfNeeded(into folder: URL, now: Date = Date()) throws -> URL? {
    let fileManager = FileManager.default
    do {
      try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
      throw AppError.io(message: DataStrings.cannotWrite(folder.path))
    }
    if let newest = Self.backupFiles(in: folder).first, now.timeIntervalSince(newest.date) < Self.backupInterval {
      return nil
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    var target = folder.appendingPathComponent("db-\(formatter.string(from: now)).sqlite")
    var counter = 1
    while fileManager.fileExists(atPath: target.path) {
      target = folder.appendingPathComponent("db-\(formatter.string(from: now))-\(counter).sqlite")
      counter += 1
    }
    do {
      let destination = try DatabaseQueue(path: target.path)
      try queue.backup(to: destination)
    } catch {
      try? fileManager.removeItem(at: target)
      throw AppError.io(message: DataStrings.cannotWrite(target.path))
    }
    // Stamp with `now` so retention is consistent even with an injected clock.
    try? fileManager.setAttributes([.modificationDate: now], ofItemAtPath: target.path)

    for old in Self.backupFiles(in: folder).dropFirst(Self.backupsKept) {
      try? fileManager.removeItem(at: old.url)
    }
    return target
  }

  /// Regular files in `folder`, newest first.
  static func backupFiles(in folder: URL) -> [(url: URL, date: Date)] {
    let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
    else { return [] }
    return files.compactMap { url -> (URL, Date)? in
      guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
        let date = values.contentModificationDate
      else { return nil }
      return (url, date)
    }.sorted { $0.1 > $1.1 }
  }
}
