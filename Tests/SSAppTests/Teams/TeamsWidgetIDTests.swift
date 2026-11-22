import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

@MainActor
struct TeamsWidgetIDTests {
  func makeModel() -> TeamsViewModel {
    let model = TeamsViewModel(services: AppServices.fake(today: try! DayDate("2026-11-18")))
    model.reload()
    return model
  }

  @Test func pastedAddressIsStoredAsTheBareID() throws {
    let model = makeModel()
    let team = try #require(model.teams.first { $0.tuttocampoWidgetID == nil })
    let id = "11111111-2222-4333-8444-555555555555"
    model.beginEdit(team)
    model.editDraft.tuttocampoWidgetID = "https://www.tuttocampo.it/WidgetV2/Risultati/\(id)"
    #expect(model.saveEdit())
    #expect(model.editing == nil)
    #expect(model.teams.first { $0.id == team.id }?.tuttocampoWidgetID == id)
  }

  @Test func idUsedByAnotherTeamShowsTheProblemUnderTheField() throws {
    let model = makeModel()
    let other = try #require(model.teams.first { $0.tuttocampoWidgetID != nil })
    let team = try #require(model.teams.first { $0.tuttocampoWidgetID == nil })
    model.beginEdit(team)
    model.editDraft.tuttocampoWidgetID = other.tuttocampoWidgetID
    #expect(!model.saveEdit())
    #expect(model.editing != nil)
    #expect(model.editProblems.message(for: .tuttocampoWidgetID)?.contains(other.name) == true)
  }

  @Test func invalidIDShowsAProblem() throws {
    let model = makeModel()
    let team = try #require(model.teams.first)
    model.beginEdit(team)
    model.editDraft.tuttocampoWidgetID = "non-un-id"
    #expect(!model.saveEdit())
    #expect(model.editProblems.message(for: .tuttocampoWidgetID) != nil)
  }

  @Test func emptyFieldClearsTheID() throws {
    let model = makeModel()
    let team = try #require(model.teams.first { $0.tuttocampoWidgetID != nil })
    model.beginEdit(team)
    model.editDraft.tuttocampoWidgetID = "  "
    #expect(model.saveEdit())
    #expect(model.teams.first { $0.id == team.id }?.tuttocampoWidgetID == nil)
  }

  @Test func aTeamMaySaveItsOwnIDAgain() throws {
    let model = makeModel()
    let team = try #require(model.teams.first { $0.tuttocampoWidgetID != nil })
    model.beginEdit(team)
    #expect(model.saveEdit())
  }

  @Test func newTeamCanHaveAnID() {
    let model = makeModel()
    model.beginCreate()
    model.newDraft = TeamDraft(
      name: "Under 18", shortLabel: "U18", tuttocampoWidgetID: "11111111-2222-4333-8444-555555555555")
    #expect(model.create())
    #expect(model.teams.last?.tuttocampoWidgetID == "11111111-2222-4333-8444-555555555555")
  }
}
