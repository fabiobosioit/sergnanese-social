import SSCore
import Testing

@testable import SSData

@Suite struct TeamRepositoryTests {
  @Test func firstTeamEverCreatedGetsTheFlagAndSortOrderCountsUp() throws {
    let db = try AppDatabase.inMemory()
    let a = try db.teams.create(TeamDraft(name: "A", shortLabel: "A"))
    let b = try db.teams.create(TeamDraft(name: "B", shortLabel: "B"))
    #expect(a.isFirstTeam && !b.isFirstTeam)
    #expect(a.sortOrder == 0 && b.sortOrder == 1)
    #expect(try db.teams.list() == [a, b])
  }

  @Test func sortOrderIsMaxPlusOneAfterDeletions() throws {
    let db = try AppDatabase.inMemory()
    let a = try db.teams.create(TeamDraft(name: "A", shortLabel: "A"))
    let b = try db.teams.create(TeamDraft(name: "B", shortLabel: "B"))
    let c = try db.teams.create(TeamDraft(name: "C", shortLabel: "C"))
    try db.teams.delete(id: b.id)
    let d = try db.teams.create(TeamDraft(name: "D", shortLabel: "D"))
    #expect(c.sortOrder == 2 && d.sortOrder == 3)
    #expect(try db.teams.list().map(\.id) == [a.id, c.id, d.id])
  }

  @Test func createWithFirstFlagMovesIt() throws {
    let f = try Fixture()
    let third = try f.db.teams.create(TeamDraft(name: "Under 15", shortLabel: "U15", isFirstTeam: true))
    #expect(third.isFirstTeam)
    let teams = try f.db.teams.list()
    #expect(teams.filter(\.isFirstTeam).map(\.id) == [third.id])
  }

  @Test func updateMovesFlagAndRejectsClearingIt() throws {
    let f = try Fixture()
    #expect(throws: AppError.firstTeamRequired) {
      try f.db.teams.update(id: f.first.id, with: TeamDraft(name: "Prima", shortLabel: "P", isFirstTeam: false))
    }
    let moved = try f.db.teams.update(
      id: f.second.id, with: TeamDraft(name: "Juniores", shortLabel: "Jun", isFirstTeam: true))
    #expect(moved.isFirstTeam && moved.sortOrder == f.second.sortOrder && moved.shortLabel == "Jun")
    let teams = try f.db.teams.list()
    #expect(teams.filter(\.isFirstTeam).map(\.id) == [f.second.id])
    // Now the former first team can be updated without the flag.
    _ = try f.db.teams.update(id: f.first.id, with: TeamDraft(name: "Prima", shortLabel: "P"))
  }

  @Test func updateUnknownAndInvalid() throws {
    let f = try Fixture()
    #expect(throws: AppError.notFound) {
      try f.db.teams.update(id: "nope", with: TeamDraft(name: "X", shortLabel: "X"))
    }
    #expect(throws: AppError.self) { try f.db.teams.update(id: f.first.id, with: TeamDraft(name: "", shortLabel: "X")) }
    #expect(throws: AppError.notFound) { try f.db.teams.get(id: "nope") }
  }

  @Test func deleteRules() throws {
    let f = try Fixture()
    #expect(throws: AppError.firstTeamCannotBeDeleted) { try f.db.teams.delete(id: f.first.id) }
    _ = try f.db.matches.create(f.draft(team: f.second))
    do {
      try f.db.teams.delete(id: f.second.id)
      Issue.record("expected conflict")
    } catch AppError.conflict(let message) {
      #expect(message.contains("partite"))
    }
    #expect(throws: AppError.notFound) { try f.db.teams.delete(id: "nope") }
    let spare = try f.db.teams.create(TeamDraft(name: "Spare", shortLabel: "S"))
    try f.db.teams.delete(id: spare.id)
    #expect(try f.db.teams.list().count == 2)
  }

  @Test func deletingTheOnlyTeamIsAllowed() throws {
    let db = try AppDatabase.inMemory()
    let only = try db.teams.create(TeamDraft(name: "A", shortLabel: "A"))
    try db.teams.delete(id: only.id)
    #expect(try db.teams.list().isEmpty)
    let next = try db.teams.create(TeamDraft(name: "B", shortLabel: "B"))
    #expect(next.isFirstTeam && next.sortOrder == 0)
  }

  @Test func reorder() throws {
    let f = try Fixture()
    try f.db.teams.reorder(ids: [f.second.id, f.first.id])
    let teams = try f.db.teams.list()
    #expect(teams.map(\.id) == [f.second.id, f.first.id])
    #expect(teams.map(\.sortOrder) == [0, 1])
    #expect(throws: AppError.self) { try f.db.teams.reorder(ids: [f.first.id]) }
    #expect(throws: AppError.self) { try f.db.teams.reorder(ids: [f.first.id, f.first.id]) }
  }
}
