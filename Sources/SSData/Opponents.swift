import Foundation
import GRDB
import SSCore

func encodeJSON<T: Encodable>(_ value: T) -> String {
  guard let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else {
    return "[]"
  }
  return text
}

func decodeJSON<T: Decodable>(_ type: T.Type, from text: String) -> T? {
  try? JSONDecoder().decode(type, from: Data(text.utf8))
}

extension Opponent {
  init(row: Row, prefix: String = "") {
    let aliases: String = row[prefix + "aliases"]
    self.init(
      id: row[prefix + "id"], name: row[prefix + "name"], shortName: row[prefix + "short_name"],
      aliases: decodeJSON([String].self, from: aliases) ?? [], logoFile: row[prefix + "logo_file"])
  }
}

struct OpponentStore: OpponentRepository {
  let database: AppDatabase

  func list() throws -> [Opponent] {
    try database.read { db in try Self.all(db) }
  }

  func get(id: EntityID) throws -> Opponent {
    try database.read { db in try Self.fetch(db, id: id) }
  }

  func create(_ draft: OpponentDraft) throws -> Opponent {
    let draft = try draft.validated()
    return try database.write { db in
      let opponent = Opponent(
        id: newEntityID(), name: draft.name, shortName: draft.shortName, aliases: draft.aliases,
        logoFile: draft.logoFile)
      try db.execute(
        sql: "INSERT INTO opponents (id, name, short_name, aliases, logo_file) VALUES (?, ?, ?, ?, ?)",
        arguments: [opponent.id, opponent.name, opponent.shortName, encodeJSON(opponent.aliases), opponent.logoFile])
      return opponent
    }
  }

  func update(id: EntityID, with draft: OpponentDraft) throws -> Opponent {
    let draft = try draft.validated()
    return try database.write { db in
      _ = try Self.fetch(db, id: id)
      try db.execute(
        sql: "UPDATE opponents SET name = ?, short_name = ?, aliases = ?, logo_file = ? WHERE id = ?",
        arguments: [draft.name, draft.shortName, encodeJSON(draft.aliases), draft.logoFile, id])
      return try Self.fetch(db, id: id)
    }
  }

  func delete(id: EntityID) throws {
    try database.write { db in
      _ = try Self.fetch(db, id: id)
      let matches =
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM matches WHERE opponent_id = ?", arguments: [id]) ?? 0
      if matches > 0 { throw AppError.conflict(message: DataStrings.opponentHasMatches) }
      try db.execute(sql: "DELETE FROM opponents WHERE id = ?", arguments: [id])
    }
  }

  func applyImport(_ plan: OpponentImportPlan) throws -> [Opponent] {
    try database.write { db in
      var result: [Opponent] = []
      for item in plan.items {
        switch item.action {
        case .create:
          guard let draft = try item.action.draft(current: nil)?.validated() else { throw AppError.notFound }
          let opponent = Opponent(
            id: newEntityID(), name: draft.name, shortName: draft.shortName, aliases: draft.aliases,
            logoFile: draft.logoFile)
          try db.execute(
            sql: "INSERT INTO opponents (id, name, short_name, aliases, logo_file) VALUES (?, ?, ?, ?, ?)",
            arguments: [
              opponent.id, opponent.name, opponent.shortName, encodeJSON(opponent.aliases), opponent.logoFile,
            ])
          result.append(opponent)
        case .update(let id, _, _):
          let current = try Self.fetch(db, id: id)
          guard let draft = try item.action.draft(current: current)?.validated() else { throw AppError.notFound }
          // Name and aliases only: short name and logo stay as stored.
          try db.execute(
            sql: "UPDATE opponents SET name = ?, aliases = ? WHERE id = ?",
            arguments: [draft.name, encodeJSON(draft.aliases), id])
          result.append(try Self.fetch(db, id: id))
        }
      }
      return result
    }
  }

  func search(_ query: String) throws -> [Opponent] {
    // Matching is accent- and case-insensitive in Swift (`textMatches`); the table is tiny.
    try list().filter { textMatches(query: query, in: [$0.name, $0.shortName ?? ""] + $0.aliases) }
  }

  func matchCounts() throws -> [EntityID: Int] {
    try database.read { db in
      let rows = try Row.fetchAll(
        db, sql: "SELECT opponent_id, COUNT(*) AS n FROM matches GROUP BY opponent_id")
      return Dictionary(uniqueKeysWithValues: rows.map { (String($0["opponent_id"] as String), $0["n"] as Int) })
    }
  }

  static func all(_ db: Database) throws -> [Opponent] {
    let all = try Row.fetchAll(db, sql: "SELECT * FROM opponents").map { Opponent(row: $0) }
    // Case- and accent-insensitive by name; id keeps the order total.
    return all.sorted { lhs, rhs in
      let (left, right) = (searchKey(lhs.name), searchKey(rhs.name))
      return left == right ? lhs.id < rhs.id : left < right
    }
  }

  static func fetch(_ db: Database, id: EntityID) throws -> Opponent {
    guard let row = try Row.fetchOne(db, sql: "SELECT * FROM opponents WHERE id = ?", arguments: [id]) else {
      throw AppError.notFound
    }
    return Opponent(row: row)
  }
}
