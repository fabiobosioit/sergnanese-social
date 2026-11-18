import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

@MainActor
struct OpponentsViewModelTests {
  static let today = try! DayDate("2026-11-18")

  func makeModel() -> OpponentsViewModel {
    let model = OpponentsViewModel(services: AppServices.fake(today: Self.today))
    model.reload()
    return model
  }

  @Test func loadsOpponentsWithMatchCounts() {
    let model = makeModel()
    #expect(!model.opponents.isEmpty)
    #expect(model.loadError == nil)
    #expect(model.opponents.contains { model.matches(of: $0) > 0 })
  }

  @Test func createsAnOpponentAndSelectsIt() {
    let model = makeModel()
    let before = model.opponents.count
    model.beginCreate()
    model.newDraft.name = "  ASD   Nuova Squadra "
    #expect(model.create())
    #expect(model.opponents.count == before + 1)
    #expect(model.selectedOpponent?.name == "ASD Nuova Squadra")
    #expect(!model.isCreating)
  }

  @Test func createShowsValidationErrorAndKeepsTheSheetOpen() {
    let model = makeModel()
    let before = model.opponents.count
    model.beginCreate()
    model.newDraft.name = "   "
    #expect(!model.create())
    #expect(model.newProblems.message(for: .name) != nil)
    #expect(model.isCreating)
    #expect(model.opponents.count == before)
  }

  @Test func editSavesAndInvalidEditIsNotSaved() {
    let model = makeModel()
    let target = model.opponents[0]
    model.selection = [target.id]
    model.selectionChanged(from: [])
    model.draft.shortName = "Breve"
    model.commit()
    #expect(model.selectedOpponent?.shortName == "Breve")
    model.draft.name = ""
    model.commit()
    #expect(model.problems.message(for: .name) != nil)
    #expect(model.selectedOpponent?.name == target.name)
  }

  @Test func appearanceCutsToTheSmallestTemplateLimit() throws {
    let model = makeModel()
    let limit = try #require(model.teamNameLimit)
    var draft = OpponentDraft(name: String(repeating: "Parola ", count: 12))
    #expect(model.appearance(of: draft).wasCut)
    #expect(model.appearance(of: draft).text.count <= limit)
    draft.shortName = "Breve"
    #expect(model.appearance(of: draft) == Truncation(text: "Breve", wasCut: false))
  }

  @Test func aliasesAreAddedOnceAndRemoved() {
    let model = makeModel()
    model.selection = [model.opponents[0].id]
    model.selectionChanged(from: [])
    model.addAlias("  Alias   Uno ")
    model.addAlias("alias uno")
    #expect(model.selectedOpponent?.aliases.filter { $0 == "Alias Uno" }.count == 1)
    model.removeAlias("Alias Uno")
    #expect(model.selectedOpponent?.aliases.contains("Alias Uno") == false)
  }

  @Test func deleteIsRefusedWhenTheOpponentHasMatches() throws {
    let model = makeModel()
    let withMatches = try #require(model.opponents.first { model.matches(of: $0) > 0 })
    let before = model.opponents.count
    model.requestDelete([withMatches.id])
    #expect(model.pendingDelete.count == 1)
    model.confirmDelete()
    #expect(model.errorMessage != nil)
    #expect(model.opponents.count == before)
    #expect(model.pendingDelete.isEmpty)
  }

  @Test func deleteRemovesAnOpponentWithoutMatches() {
    let model = makeModel()
    model.beginCreate()
    model.newDraft.name = "Da eliminare"
    model.create()
    let id = model.selection.first!
    model.requestDeleteSelection()
    model.confirmDelete()
    #expect(model.errorMessage == nil)
    #expect(!model.opponents.contains { $0.id == id })
  }

  @Test func logoImportAndRemoveUpdateTheOpponent() async throws {
    let model = makeModel()
    model.beginCreate()
    model.newDraft.name = "Con logo"
    model.create()
    await model.setLogo(.data(Data([0x89, 0x50, 0x4E, 0x47])))
    #expect(model.errorMessage == nil)
    #expect(model.selectedOpponent?.logoFile != nil)
    model.removeLogo()
    #expect(model.selectedOpponent?.logoFile == nil)
  }

  @Test func searchFiltersTheList() {
    let model = makeModel()
    let first = model.opponents[0]
    model.searchText = String(first.name.prefix(4))
    model.reload()
    #expect(model.opponents.contains { $0.id == first.id })
    model.searchText = "zzzzzzzz-nessuno"
    model.reload()
    #expect(model.opponents.isEmpty)
  }
}
