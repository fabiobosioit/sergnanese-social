import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

@MainActor
struct TeamsViewModelTests {
  static let today = try! DayDate("2026-11-18")

  func makeModel() -> TeamsViewModel {
    let model = TeamsViewModel(services: AppServices.fake(today: Self.today))
    model.reload()
    return model
  }

  @Test func exactlyOneFirstTeam() {
    let model = makeModel()
    #expect(model.teams.filter(\.isFirstTeam).count == 1)
  }

  @Test func createAppendsATeam() {
    let model = makeModel()
    let before = model.teams.count
    model.beginCreate()
    model.newDraft = TeamDraft(name: "Under 17", shortLabel: "U17")
    #expect(model.create())
    #expect(model.teams.count == before + 1)
    #expect(model.teams.last?.name == "Under 17")
    #expect(model.selection == model.teams.last?.id)
  }

  @Test func createValidationErrorKeepsTheSheetOpen() {
    let model = makeModel()
    model.beginCreate()
    model.newDraft = TeamDraft(name: "", shortLabel: "")
    #expect(!model.create())
    #expect(model.newProblems.message(for: .name) != nil)
    #expect(model.newProblems.message(for: .shortLabel) != nil)
    #expect(model.isCreating)
  }

  @Test func renameInline() throws {
    let model = makeModel()
    let team = try #require(model.teams.last)
    #expect(model.rename(team, name: "Nome nuovo", shortLabel: team.shortLabel))
    #expect(model.teams.last?.name == "Nome nuovo")
    #expect(!model.rename(model.teams.last!, name: "", shortLabel: "X"))
    #expect(model.errorMessage != nil)
    #expect(model.teams.last?.name == "Nome nuovo")
  }

  @Test func choosingAnotherFirstTeamMovesTheMarker() throws {
    let model = makeModel()
    let other = try #require(model.teams.first { !$0.isFirstTeam })
    model.makeFirst(other)
    #expect(model.teams.filter(\.isFirstTeam).map(\.id) == [other.id])
  }

  @Test func firstTeamCannotBeDeleted() throws {
    let model = makeModel()
    // A new team without matches, made first team: only the first-team rule can refuse its deletion.
    model.beginCreate()
    model.newDraft = TeamDraft(name: "Nuova prima", shortLabel: "NP")
    model.create()
    model.makeFirst(try #require(model.teams.last))
    let first = try #require(model.teams.first { $0.isFirstTeam })
    #expect(first.name == "Nuova prima")
    let before = model.teams.count
    model.requestDelete(first)
    model.confirmDelete()
    #expect(model.errorMessage == AppError.firstTeamCannotBeDeleted.localizedDescription)
    #expect(model.teams.count == before)
  }

  @Test func deleteGuardForATeamWithMatchesAndDeleteOfAnEmptyOne() throws {
    let model = makeModel()
    let used = try model.services.matches.list(
      from: DayDate("2000-01-01"), to: DayDate("2100-12-31"), teamID: nil
    ).map(\.team.id)
    let withMatches = try #require(model.teams.first { !$0.isFirstTeam && used.contains($0.id) })
    model.requestDelete(withMatches)
    model.confirmDelete()
    #expect(model.errorMessage != nil)
    #expect(model.teams.contains { $0.id == withMatches.id })

    model.errorMessage = nil
    model.beginCreate()
    model.newDraft = TeamDraft(name: "Vuota", shortLabel: "V")
    model.create()
    let created = try #require(model.teams.last)
    model.requestDelete(created)
    model.confirmDelete()
    #expect(model.errorMessage == nil)
    #expect(!model.teams.contains { $0.id == created.id })
  }

  @Test func reorderPersistsSortOrder() throws {
    let model = makeModel()
    let ids = model.teams.map(\.id)
    #expect(ids.count >= 2)
    model.move(fromOffsets: IndexSet(integer: 0), toOffset: ids.count)
    let expected = Array(ids.dropFirst()) + [ids[0]]
    #expect(model.teams.map(\.id) == expected)
    #expect(model.teams.map(\.sortOrder) == Array(0..<ids.count))
    let stored = try model.services.teams.list()
    #expect(stored.map(\.id) == expected)
  }

  @Test func activeToggleSaves() throws {
    let model = makeModel()
    let team = try #require(model.teams.first)
    model.setActive(team, !team.isActive)
    #expect(model.teams.first?.isActive == !team.isActive)
  }
}
