import Foundation
import SSCore
import Testing

@testable import SSData

@Suite struct MatchRepositoryTests {
  @Test func createAndGetRoundTrip() throws {
    let f = try Fixture()
    var draft = f.draft()
    draft.competition = "Campionato"
    draft.round = 7
    draft.score = Score(us: 0, them: 2)
    draft.halfTime = Score(us: 0, them: 1)
    draft.status = .played
    draft.notes = "Gol: Verdi"
    let match = try f.db.matches.create(draft)
    let detail = try f.db.matches.get(id: match.id)
    #expect(detail.match == match)
    #expect(detail.team == f.first)
    #expect(detail.opponent == f.rossi)
    #expect(detail.match.score == Score(us: 0, them: 2))
    #expect(throws: AppError.notFound) { try f.db.matches.get(id: "nope") }
  }

  @Test func createRejectsUnknownReferencesAndInvalidDrafts() throws {
    let f = try Fixture()
    var draft = f.draft()
    draft.teamID = "ghost"
    #expect(throws: AppError.self) { try f.db.matches.create(draft) }
    do {
      _ = try f.db.matches.create(draft)
    } catch AppError.validation(let field, _) {
      #expect(field == .team)
    }
    draft = f.draft()
    draft.opponentID = "ghost"
    do {
      _ = try f.db.matches.create(draft)
    } catch AppError.validation(let field, _) {
      #expect(field == .opponent)
    }
    draft = f.draft()
    draft.round = 0
    #expect(throws: AppError.self) { try f.db.matches.create(draft) }
    #expect(try f.db.matches.count(source: nil) == 0)
  }

  @Test func listRangeIsInclusiveAtBothEnds() throws {
    let f = try Fixture()
    for date in ["2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23"] {
      _ = try f.db.matches.create(f.draft(date: date))
    }
    let weekend = try f.db.matches.list(from: day("2026-11-21"), to: day("2026-11-22"), teamID: nil)
    #expect(weekend.map { $0.match.date.value } == ["2026-11-21", "2026-11-22"])
    #expect(try f.db.matches.list(from: day("2026-11-22"), to: day("2026-11-22"), teamID: nil).count == 1)
    #expect(try f.db.matches.list(from: day("2026-11-22"), to: day("2026-11-21"), teamID: nil).isEmpty)
  }

  @Test func listFiltersByTeamAndOrdersByDateTimeTeam() throws {
    let f = try Fixture()
    let sundayLate = try f.db.matches.create(f.draft(date: "2026-11-22", time: "17:00"))
    let saturdayJuniores = try f.db.matches.create(f.draft(team: f.second, date: "2026-11-21", time: "15:00"))
    let saturdayPrima = try f.db.matches.create(f.draft(date: "2026-11-21", time: "15:00"))
    let saturdayNoTime = try f.db.matches.create(f.draft(opponent: f.bianchi, date: "2026-11-21", time: nil))
    let saturdayEarly = try f.db.matches.create(
      f.draft(team: f.second, opponent: f.bianchi, date: "2026-11-21", time: "10:30"))
    let all = try f.db.matches.list(from: day("2026-11-21"), to: day("2026-11-22"), teamID: nil)
    #expect(
      all.map(\.id) == [saturdayEarly.id, saturdayPrima.id, saturdayJuniores.id, saturdayNoTime.id, sundayLate.id])
    let juniores = try f.db.matches.list(from: day("2026-11-21"), to: day("2026-11-22"), teamID: f.second.id)
    #expect(juniores.map(\.id) == [saturdayEarly.id, saturdayJuniores.id])
  }

  @Test func updateKeepsIdAndCreatedAtAndWorksOnLockedMatches() throws {
    let f = try Fixture()
    var draft = f.draft()
    draft.isLocked = true
    let match = try f.db.matches.create(draft)
    draft.venue = "Altro campo"
    draft.score = Score(us: 1, them: 1)
    let updated = try f.db.matches.update(id: match.id, with: draft)
    #expect(updated.id == match.id)
    #expect(updated.createdAt == match.createdAt)
    #expect(updated.updatedAt >= match.updatedAt)
    #expect(updated.venue == "Altro campo" && updated.isLocked)
    #expect(try f.db.matches.get(id: match.id).match == updated)
    #expect(throws: AppError.notFound) { try f.db.matches.update(id: "nope", with: draft) }
  }

  @Test func deleteAndDeleteAllBySource() throws {
    let f = try Fixture()
    var seed = f.draft()
    seed.source = .seed
    seed.isLocked = true
    _ = try f.db.matches.create(seed)
    seed.date = day("2026-11-22")
    _ = try f.db.matches.create(seed)
    let manual = try f.db.matches.create(f.draft(date: "2026-11-28"))
    #expect(try f.db.matches.count(source: nil) == 3)
    #expect(try f.db.matches.count(source: .seed) == 2)
    #expect(try f.db.matches.deleteAll(source: .seed) == 2)
    #expect(try f.db.matches.count(source: .seed) == 0)
    try f.db.matches.delete(id: manual.id)
    #expect(throws: AppError.notFound) { try f.db.matches.delete(id: manual.id) }
    #expect(try f.db.matches.count(source: nil) == 0)
  }

  @Test func duplicateResetsResultAndLock() throws {
    let f = try Fixture()
    var draft = f.draft()
    draft.status = .played
    draft.score = Score(us: 2, them: 0)
    draft.halfTime = Score(us: 1, them: 0)
    draft.isLocked = true
    draft.source = .csv
    draft.round = 4
    draft.competition = "Coppa"
    draft.notes = "note"
    let original = try f.db.matches.create(draft)
    let copy = try f.db.matches.duplicate(id: original.id, to: day("2026-11-28"))
    #expect(copy.id != original.id)
    #expect(copy.date == day("2026-11-28"))
    #expect(copy.status == .scheduled && copy.score == nil && copy.halfTime == nil)
    #expect(!copy.isLocked && copy.source == .manual)
    #expect(copy.teamID == original.teamID && copy.opponentID == original.opponentID)
    #expect(copy.time == original.time && copy.venue == original.venue && copy.round == 4)
    #expect(copy.competition == "Coppa" && copy.notes == nil)
    #expect(try f.db.matches.count(source: nil) == 2)
    #expect(throws: AppError.notFound) { try f.db.matches.duplicate(id: "nope", to: day("2026-11-28")) }
  }

  @Test func duplicateKeepsNotesWhenOriginalHasNoResult() throws {
    let f = try Fixture()
    var draft = f.draft()
    draft.notes = "note"
    let original = try f.db.matches.create(draft)
    let copy = try f.db.matches.duplicate(id: original.id, to: day("2026-11-28"))
    #expect(copy.notes == "note")
    var halfOnly = f.draft(date: "2026-11-22")
    halfOnly.notes = "scorers"
    halfOnly.halfTime = Score(us: 1, them: 0)
    let o2 = try f.db.matches.create(halfOnly)
    #expect(try f.db.matches.duplicate(id: o2.id, to: day("2026-11-29")).notes == nil)
  }

  @Test func upsertInsertsUpdatesAndSkipsLocked() throws {
    let f = try Fixture()
    var lockedDraft = f.draft(date: "2026-11-21")
    lockedDraft.isLocked = true
    lockedDraft.venue = "Originale"
    let locked = try f.db.matches.create(lockedDraft)
    let open = try f.db.matches.create(f.draft(date: "2026-11-22", time: "10:00"))

    var imported = f.draft(date: "2026-11-21")
    imported.venue = "Da import"
    var updatedDraft = f.draft(date: "2026-11-22", time: "11:30")
    updatedDraft.source = .csv
    let fresh = f.draft(team: f.second, date: "2026-11-21")

    let summary = try f.db.matches.upsertFromImport([imported, updatedDraft, fresh])
    #expect(summary == ImportSummary(inserted: 1, updated: 1, skippedLocked: 1))
    #expect(try f.db.matches.get(id: locked.id).match.venue == "Originale")
    let refreshed = try f.db.matches.get(id: open.id).match
    #expect(refreshed.time == clock("11:30") && refreshed.source == .csv && refreshed.createdAt == open.createdAt)
    #expect(try f.db.matches.count(source: nil) == 3)
  }

  @Test func upsertIsAllOrNothing() throws {
    let f = try Fixture()
    var bad = f.draft(date: "2026-11-28")
    bad.opponentID = "ghost"
    #expect(throws: AppError.self) { try f.db.matches.upsertFromImport([f.draft(date: "2026-11-21"), bad]) }
    #expect(try f.db.matches.count(source: nil) == 0)
  }
}
