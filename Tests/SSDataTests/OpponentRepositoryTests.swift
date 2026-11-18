import SSCore
import Testing

@testable import SSData

@Suite struct OpponentRepositoryTests {
  @Test func createGetUpdate() throws {
    let db = try AppDatabase.inMemory()
    let created = try db.opponents.create(
      OpponentDraft(name: "  ASD  Rossi ", shortName: "Rossi", aliases: ["Rossi A.", "rossi a."], logoFile: "x.png"))
    #expect(created.name == "ASD Rossi")
    #expect(created.aliases == ["Rossi A."])
    #expect(try db.opponents.get(id: created.id) == created)
    let updated = try db.opponents.update(id: created.id, with: OpponentDraft(name: "Rossi FC"))
    #expect(
      updated.name == "Rossi FC" && updated.shortName == nil && updated.aliases.isEmpty && updated.logoFile == nil)
    #expect(throws: AppError.notFound) { try db.opponents.get(id: "nope") }
    #expect(throws: AppError.notFound) { try db.opponents.update(id: "nope", with: OpponentDraft(name: "X")) }
    #expect(throws: AppError.self) { try db.opponents.create(OpponentDraft(name: "")) }
  }

  @Test func listIsOrderedIgnoringCaseAndAccents() throws {
    let db = try AppDatabase.inMemory()
    for name in ["zeta", "Àquila", "Bruno", "alfa"] { _ = try db.opponents.create(OpponentDraft(name: name)) }
    #expect(try db.opponents.list().map(\.name) == ["alfa", "Àquila", "Bruno", "zeta"])
  }

  @Test func searchByNameShortNameAndAlias() throws {
    let f = try Fixture()
    #expect(try f.db.opponents.search("rossi").map(\.id) == [f.rossi.id])
    #expect(try f.db.opponents.search("aquila").map(\.id) == [f.bianchi.id])
    #expect(try f.db.opponents.search("aquila b").map(\.id) == [f.bianchi.id])
    #expect(try f.db.opponents.search("").count == 2)
    #expect(try f.db.opponents.search("zzz").isEmpty)
  }

  @Test func deleteGuardAndMatchCounts() throws {
    let f = try Fixture()
    _ = try f.db.matches.create(f.draft())
    _ = try f.db.matches.create(f.draft(date: "2026-11-22"))
    #expect(try f.db.opponents.matchCounts() == [f.rossi.id: 2])
    do {
      try f.db.opponents.delete(id: f.rossi.id)
      Issue.record("expected conflict")
    } catch AppError.conflict(let message) {
      #expect(message.contains("partite"))
    }
    try f.db.opponents.delete(id: f.bianchi.id)
    #expect(try f.db.opponents.list().map(\.id) == [f.rossi.id])
    #expect(throws: AppError.notFound) { try f.db.opponents.delete(id: f.bianchi.id) }
  }
}
