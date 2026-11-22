import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

@MainActor
struct TeamsCSIPageTests {
  func makeModel() -> TeamsViewModel {
    let model = TeamsViewModel(services: AppServices.fake(today: try! DayDate("2026-11-18")))
    model.reload()
    return model
  }

  @Test func addressWithoutSchemeIsStoredWithIt() throws {
    let model = makeModel()
    let team = try #require(model.teams.first { $0.csiPageURL == nil })
    model.beginEdit(team)
    model.editDraft.csiPageURL = "live.centrosportivoitaliano.it/26/Calcio-a-7/Altro/G000009-girone-b/"
    #expect(model.saveEdit())
    #expect(
      model.teams.first { $0.id == team.id }?.csiPageURL
        == "https://live.centrosportivoitaliano.it/26/Calcio-a-7/Altro/G000009-girone-b/")
  }

  @Test func pageUsedByAnotherTeamShowsTheProblemUnderTheField() throws {
    let model = makeModel()
    let other = try #require(model.teams.first { $0.csiPageURL != nil })
    let team = try #require(model.teams.first { $0.csiPageURL == nil })
    model.beginEdit(team)
    model.editDraft.csiPageURL = other.csiPageURL
    #expect(!model.saveEdit())
    #expect(model.editing != nil)
    #expect(model.editProblems.message(for: .csiPageURL)?.contains(other.name) == true)
  }

  @Test func addressOfAnotherSiteShowsAProblem() throws {
    let model = makeModel()
    let team = try #require(model.teams.first { $0.csiPageURL == nil })
    model.beginEdit(team)
    model.editDraft.csiPageURL = "https://example.com/girone"
    #expect(!model.saveEdit())
    #expect(model.editProblems.message(for: .csiPageURL) != nil)
  }

  @Test func clearingTheFieldRemovesThePage() throws {
    let model = makeModel()
    let team = try #require(model.teams.first { $0.csiPageURL != nil })
    model.beginEdit(team)
    model.editDraft.csiPageURL = "  "
    #expect(model.saveEdit())
    #expect(model.teams.first { $0.id == team.id }?.csiPageURL == nil)
  }
}
