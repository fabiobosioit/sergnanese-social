import Foundation
import GRDB
import SSCore
import Testing

@testable import SSData

@Suite struct SourceTeamListTests {
  private func sample(_ team: EntityID, source: TeamListSource = .csi) -> [SourceTeam] {
    [
      SourceTeam(
        source: source, teamID: team, name: "Dell'Àquila d'Oro", logoID: "90000104",
        logoURL: URL(string: "https://example.org/logo/90000104.png?size=2&v=1")),
      SourceTeam(source: source, teamID: team, name: "Senza logo"),
    ]
  }

  @Test func saveThenLatestRoundTrips() throws {
    let f = try Fixture()
    let readAt = Date(timeIntervalSinceReferenceDate: 800_000_000.5)
    try f.db.sourceTeamLists.save(teamID: f.first.id, source: .csi, teams: sample(f.first.id), readAt: readAt)
    let list = try #require(try f.db.sourceTeamLists.latest(teamID: f.first.id, source: .csi))
    #expect(list == SourceTeamList(teamID: f.first.id, source: .csi, readAt: readAt, teams: sample(f.first.id)))
    #expect(list.teams[1].logoURL == nil && list.teams[1].logoID == nil)
    #expect(list.teams[0].logoURL?.absoluteString == "https://example.org/logo/90000104.png?size=2&v=1")
  }

  @Test func noListReadsAsNil() throws {
    let f = try Fixture()
    #expect(try f.db.sourceTeamLists.latest(teamID: f.first.id, source: .tuttocampo) == nil)
  }

  @Test func secondSaveReplacesAndSourcesAreSeparate() throws {
    let f = try Fixture()
    let t1 = Date(timeIntervalSinceReferenceDate: 1000)
    let t2 = Date(timeIntervalSinceReferenceDate: 2000)
    try f.db.sourceTeamLists.save(teamID: f.first.id, source: .csi, teams: sample(f.first.id), readAt: t1)
    try f.db.sourceTeamLists.save(
      teamID: f.first.id, source: .tuttocampo, teams: sample(f.first.id, source: .tuttocampo), readAt: t1)
    let only = [SourceTeam(source: .csi, teamID: f.first.id, name: "Solo")]
    try f.db.sourceTeamLists.save(teamID: f.first.id, source: .csi, teams: only, readAt: t2)
    let csi = try #require(try f.db.sourceTeamLists.latest(teamID: f.first.id, source: .csi))
    #expect(csi.teams == only && csi.readAt == t2)
    let tuttocampo = try #require(try f.db.sourceTeamLists.latest(teamID: f.first.id, source: .tuttocampo))
    #expect(tuttocampo.teams.count == 2 && tuttocampo.readAt == t1)
    #expect(try f.db.sourceTeamLists.latest(teamID: f.second.id, source: .csi) == nil)
  }

  @Test func unknownTeamIsNotFound() throws {
    let db = try AppDatabase.inMemory()
    #expect(throws: AppError.notFound) {
      try db.sourceTeamLists.save(teamID: "nope", source: .csi, teams: [], readAt: Date())
    }
    #expect(throws: AppError.notFound) { try db.sourceTeamLists.latest(teamID: "nope", source: .csi) }
  }

  @Test func deletingATeamDeletesItsLists() throws {
    let f = try Fixture()
    try f.db.sourceTeamLists.save(teamID: f.second.id, source: .csi, teams: sample(f.second.id), readAt: Date())
    try f.db.teams.delete(id: f.second.id)
    let count = try f.db.queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM source_team_lists") }
    #expect(count == 0)
  }

  @Test func teamWithMatchesKeepsItsLists() throws {
    let f = try Fixture()
    _ = try f.db.matches.create(f.draft(team: f.second))
    try f.db.sourceTeamLists.save(teamID: f.second.id, source: .csi, teams: sample(f.second.id), readAt: Date())
    #expect(throws: AppError.self) { try f.db.teams.delete(id: f.second.id) }
    #expect(try f.db.sourceTeamLists.latest(teamID: f.second.id, source: .csi) != nil)
  }

  @Test func corruptRowReadsAsNilAndIsOverwritten() throws {
    let f = try Fixture()
    try f.db.sourceTeamLists.save(teamID: f.first.id, source: .csi, teams: sample(f.first.id), readAt: Date())
    try f.db.queue.write { db in try db.execute(sql: "UPDATE source_team_lists SET teams = 'not json'") }
    #expect(try f.db.sourceTeamLists.latest(teamID: f.first.id, source: .csi) == nil)
    try f.db.sourceTeamLists.save(teamID: f.first.id, source: .csi, teams: sample(f.first.id), readAt: Date())
    #expect(try f.db.sourceTeamLists.latest(teamID: f.first.id, source: .csi)?.teams.count == 2)
  }

  @Test func migrationKeepsDataFromThePreviousSchema() throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("db.sqlite")
    // A database as the previous release left it: migrations up to v3 only, with data.
    do {
      let queue = try DatabaseQueue(path: url.path, configuration: AppDatabase.configuration)
      try AppDatabase.migrator.migrate(queue, upTo: "v3")
      try queue.write { db in
        try db.execute(
          sql: "INSERT INTO teams (id, name, short_label, sort_order, is_first_team) VALUES ('t', 'T', 'T', 0, 1)")
        try db.execute(sql: "INSERT INTO opponents (id, name) VALUES ('o', 'Rossi')")
        try db.execute(
          sql: """
            INSERT INTO matches (id, team_id, opponent_id, date, is_home, status, source, created_at, updated_at)
            VALUES ('m', 't', 'o', '2026-11-21', 1, 'scheduled', 'manual', 0, 0)
            """)
      }
    }
    let db = try AppDatabase.open(at: url)
    #expect(try db.teams.list().map(\.id) == ["t"])
    #expect(try db.opponents.list().map(\.id) == ["o"])
    #expect(try db.matches.count(source: nil) == 1)
    #expect(try db.queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM source_team_lists") } == 0)
    let again = try AppDatabase.open(at: url)
    #expect(
      try again.queue.read { db in try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations") }
        == ["v1", "v2", "v3", "v4"])
    #expect(try again.matches.count(source: nil) == 1)
  }
}

@Suite struct ApplyImportTests {
  private func item(_ action: OpponentImportPlan.Action) -> OpponentImportPlan.Item {
    OpponentImportPlan.Item(action: action, logo: nil, candidateIDs: [])
  }

  private func snapshot(_ db: AppDatabase) throws -> [Opponent] { try db.opponents.list() }

  @Test func createWithAliases() throws {
    let db = try AppDatabase.inMemory()
    let out = try db.opponents.applyImport(
      OpponentImportPlan(items: [
        item(.create(name: "Real Fontanile", aliases: ["Real Fontanile B", "real fontanile b", "REAL FONTANILE"]))
      ]))
    #expect(out.count == 1 && out[0].name == "Real Fontanile")
    #expect(out[0].aliases == ["Real Fontanile B"])
    #expect(out[0].shortName == nil && out[0].logoFile == nil)
    #expect(try db.opponents.get(id: out[0].id) == out[0])
  }

  @Test func logoOnlyUpdateLeavesTheRowUnchanged() throws {
    let f = try Fixture()
    let before = try snapshot(f.db)
    let out = try f.db.opponents.applyImport(
      OpponentImportPlan(items: [item(.update(opponentID: f.bianchi.id, rename: nil, addAliases: []))]))
    #expect(out == [f.bianchi])
    #expect(try snapshot(f.db) == before)
  }

  @Test func renameKeepsIdShortNameLogoAndMatches() throws {
    let f = try Fixture()
    let opponent = try f.db.opponents.create(
      OpponentDraft(name: "Valdorso 2016", shortName: "Valdorso", logoFile: "900301.png"))
    let match = try f.db.matches.create(f.draft(opponent: opponent))
    let out = try f.db.opponents.applyImport(
      OpponentImportPlan(items: [
        item(.update(opponentID: opponent.id, rename: "F.C. Valdorso", addAliases: ["Valdorso", "valdorso 2016"]))
      ]))
    let updated = try #require(out.first)
    #expect(updated.id == opponent.id && updated.name == "F.C. Valdorso")
    #expect(updated.shortName == "Valdorso" && updated.logoFile == "900301.png")
    #expect(updated.aliases == ["Valdorso 2016", "Valdorso"])
    #expect(try f.db.matches.get(id: match.id).opponent.id == opponent.id)
    #expect(try f.db.opponents.get(id: opponent.id) == updated)
  }

  @Test func resultsFollowItemOrder() throws {
    let f = try Fixture()
    let out = try f.db.opponents.applyImport(
      OpponentImportPlan(items: [
        item(.create(name: "Zeta", aliases: [])),
        item(.update(opponentID: f.rossi.id, rename: nil, addAliases: ["Rossi A"])),
        item(.create(name: "Alfa", aliases: [])),
      ]))
    #expect(out.map(\.name) == ["Zeta", "ASD Rossi", "Alfa"])
    #expect(out[1].aliases == ["Rossi A"])
  }

  @Test func unknownOpponentRollsEverythingBack() throws {
    let f = try Fixture()
    let before = try snapshot(f.db)
    #expect(throws: AppError.notFound) {
      try f.db.opponents.applyImport(
        OpponentImportPlan(items: [
          item(.create(name: "Nuovo", aliases: [])),
          item(.update(opponentID: "nope", rename: nil, addAliases: [])),
        ]))
    }
    #expect(try snapshot(f.db) == before)
  }

  @Test func tooLongAliasRollsEverythingBack() throws {
    let f = try Fixture()
    let before = try snapshot(f.db)
    do {
      _ = try f.db.opponents.applyImport(
        OpponentImportPlan(items: [
          item(.create(name: "Nuovo", aliases: [])),
          item(.update(opponentID: f.rossi.id, rename: nil, addAliases: [String(repeating: "a", count: 81)])),
        ]))
      Issue.record("expected a validation error")
    } catch let error as AppError {
      guard case .validation = error else {
        Issue.record("expected .validation, got \(error)")
        return
      }
    }
    #expect(try snapshot(f.db) == before)
  }

  @Test func tooLongNameRollsEverythingBack() throws {
    let f = try Fixture()
    let before = try snapshot(f.db)
    do {
      _ = try f.db.opponents.applyImport(
        OpponentImportPlan(items: [
          item(.create(name: "Nuovo", aliases: [])),
          item(.update(opponentID: f.rossi.id, rename: String(repeating: "n", count: 81), addAliases: [])),
        ]))
      Issue.record("expected a validation error")
    } catch let error as AppError {
      guard case .validation = error else {
        Issue.record("expected .validation, got \(error)")
        return
      }
    }
    #expect(try snapshot(f.db) == before)
  }
}
