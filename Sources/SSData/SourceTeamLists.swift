import Foundation
import GRDB
import SSCore

/// T4.9: the team lists read from source pages, one row per our team and source.
struct SourceTeamListStore: SourceTeamListRepository {
  let database: AppDatabase

  func save(teamID: EntityID, source: TeamListSource, teams: [SourceTeam], readAt: Date) throws {
    // The list's init stamps team and source on every element.
    let list = SourceTeamList(teamID: teamID, source: source, readAt: readAt, teams: teams)
    try database.write { db in
      _ = try TeamStore.fetch(db, id: teamID)
      try db.execute(
        sql: """
          INSERT INTO source_team_lists (team_id, source, read_at, teams) VALUES (?, ?, ?, ?)
          ON CONFLICT(team_id, source) DO UPDATE SET read_at = excluded.read_at, teams = excluded.teams
          """,
        arguments: [teamID, source.rawValue, readAt.timeIntervalSinceReferenceDate, encodeJSON(list.teams)])
    }
  }

  func latest(teamID: EntityID, source: TeamListSource) throws -> SourceTeamList? {
    try database.read { db in
      _ = try TeamStore.fetch(db, id: teamID)
      guard
        let row = try Row.fetchOne(
          db, sql: "SELECT read_at, teams FROM source_team_lists WHERE team_id = ? AND source = ?",
          arguments: [teamID, source.rawValue])
      else { return nil }
      let json: String = row["teams"]
      // A row that cannot be decoded reads as "no list"; the next save overwrites it.
      guard let teams = decodeJSON([SourceTeam].self, from: json) else { return nil }
      return SourceTeamList(
        teamID: teamID, source: source, readAt: Date(timeIntervalSinceReferenceDate: row["read_at"]), teams: teams)
    }
  }
}
