import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

/// A stand-in for the browser window: the page it "shows", its logos, and what was asked of it.
@MainActor
final class StubCSIPage: CSIPageProvider {
  var isOnTeamPage = true
  var result: Result<CSIPageSnapshot, CSIPageReadError>
  var logos = FakePageLogoSource()
  private(set) var requestedLogos: [CSILogoRequest] = []

  init(url: String = FakePageFixtureParser.scenarioPageURL) {
    result = .success(CSIPageSnapshot(html: "<html></html>", pageURL: URL(string: url)!))
  }

  func readPage() async -> Result<CSIPageSnapshot, CSIPageReadError> { result }

  func fetchLogos(_ requests: [CSILogoRequest]) async -> [CSILogoData] {
    requestedLogos += requests
    return await logos.fetchLogos(requests)
  }
}

@MainActor
struct ImportModelCSITests {
  static let today = try! DayDate("2026-11-18")  // a Wednesday: the coming weekend is 21-22 November

  func makeModel(page: StubCSIPage = StubCSIPage()) throws -> (ImportModel, AppServices, StubCSIPage) {
    let services = AppServices.fake(today: Self.today)
    let team = try #require(try services.teams.list().first { $0.name == "Pulcini" })
    let model = ImportModel(services: services, source: .csi(team: team, page: page), today: { Self.today })
    return (model, services, page)
  }

  func candidate(_ model: ImportModel, _ opponent: String) throws -> ImportCandidate {
    try #require(model.candidates.first { $0.fixture.opponentName == opponent })
  }

  @Test func statesFollowTheScenarioTable() async throws {
    let (model, _, _) = try makeModel()
    await model.readCSIPage()
    #expect(model.phase == .review)
    #expect(model.issues.isEmpty)
    #expect(model.title == ImportStrings.titleCSI)
    // T4.10: "Valdorso 2016" is proposed (F.C. Valdorso) and pre-filled, so it is .changed (time).
    let expected: [String: ImportCandidate.State] = [
      "Borgo Lucente": .new, "Prato Fiorito": .changed, "Valdorso 2016": .changed,
      "Polisportiva Fontanella": .needsReview, "Atletico Montesello": .new,
    ]
    #expect(model.candidates.count == expected.count)
    for (name, state) in expected {
      #expect(try candidate(model, name).state == state, "\(name)")
    }
  }

  @Test func linkingValdorsoSavesTheAliasAndTheRowBecomesChanged() async throws {
    let (model, services, _) = try makeModel()
    await model.readCSIPage()
    let row = try candidate(model, "Valdorso 2016")
    let valdorso = try #require(try services.opponents.list().first { $0.name == "F.C. Valdorso" })
    model.link(row, to: valdorso)
    #expect(try candidate(model, "Valdorso 2016").state == .changed)
    #expect(try services.opponents.get(id: valdorso.id).aliases.contains("Valdorso 2016"))
  }

  @Test func creatingFontanellaGivesANewRowWithTheCSIVenue() async throws {
    let (model, _, _) = try makeModel()
    await model.readCSIPage()
    model.createOpponent(for: try candidate(model, "Polisportiva Fontanella"))
    let row = try candidate(model, "Polisportiva Fontanella")
    #expect(row.state == .new)
    #expect(row.draft?.venue == "Centro Sportivo Fontanella Via Verdi 5 - 26000 Fontanella CR")
    #expect(model.isTicked(row))
  }

  @Test func commitWritesTheTickedRowsAndStoresTheLogos() async throws {
    let (model, services, page) = try makeModel()
    await model.readCSIPage()
    let valdorso = try #require(try services.opponents.list().first { $0.name == "F.C. Valdorso" })
    model.link(try candidate(model, "Valdorso 2016"), to: valdorso)
    model.createOpponent(for: try candidate(model, "Polisportiva Fontanella"))
    for row in model.candidates where ImportModel.isTickable(row) { model.setTicked(row, true) }
    let ticked = model.tickedCandidates.count
    #expect(ticked == 5)
    await model.commit()
    #expect(model.phase == .done)
    #expect(model.summary?.inserted == 3)
    #expect(model.summary?.updated == 2)

    let team = try #require(try services.teams.list().first { $0.name == "Pulcini" })
    let stored = try services.matches.list(
      from: DayDate("2026-11-01"), to: DayDate("2026-12-31"), teamID: team.id)
    let importedNames = Set(["Borgo Lucente", "Polisportiva Fontanella", "Atletico Montesello"])
    for item in stored where importedNames.contains(item.opponent.name) {
      #expect(item.match.source == .scrape)
    }
    let montesello = try #require(try services.opponents.list().first { $0.name == "Atletico Montesello" })
    #expect(montesello.logoFile == "csi-90000104.png")
    // Prato Fiorito already has a logo: not requested. Borgo Lucente has the placeholder: reported.
    #expect(!page.requestedLogos.contains { $0.opponentName == "Prato Fiorito" })
    #expect(model.issues.contains(.csiLogoUnavailable(opponent: "Pol. Borgo Lucente")))
  }

  @Test func anotherPageIsNotAGirone() async throws {
    let page = StubCSIPage(url: "https://live.centrosportivoitaliano.it/26/Altro/G000099-altro/")
    let (model, _, _) = try makeModel(page: page)
    await model.readCSIPage()
    #expect(model.issues == [.csiNotAGirone(team: "Pulcini")])
    #expect(model.candidates.isEmpty)
    #expect(model.phase == .review)
  }

  @Test func readFailureIsReported() async throws {
    let page = StubCSIPage()
    page.result = .failure(.tooLarge)
    let (model, _, _) = try makeModel(page: page)
    await model.readCSIPage()
    #expect(model.issues == [.csiPageReadFailed(team: "Pulcini", reason: .tooLarge)])
    #expect(model.candidates.isEmpty)
  }

  @Test func otherPageAsksBeforeImporting() throws {
    let page = StubCSIPage()
    page.isOnTeamPage = false
    let (model, _, _) = try makeModel(page: page)
    model.beginCSIImport()
    #expect(model.confirmsOtherPage)
    #expect(!model.isPresented)
    model.confirmOtherPage()
    #expect(!model.confirmsOtherPage)
    #expect(model.isPresented)
    model.dismiss()
  }

  @Test func teamPageStartsWithoutAsking() throws {
    let (model, _, _) = try makeModel()
    model.beginCSIImport()
    #expect(!model.confirmsOtherPage)
    #expect(model.isPresented)
    model.dismiss()
  }
}

@MainActor
struct CSIImportLauncherTests {
  func make() -> (CSIImportLauncher, AppServices) {
    let services = AppServices.fake(today: try! DayDate("2026-11-18"))
    return (CSIImportLauncher(services: services), services)
  }

  @Test func onlyActiveTeamsWithAPageCount() throws {
    let (launcher, _) = make()
    launcher.refresh()
    #expect(launcher.teams.map(\.name) == ["Pulcini"])
    #expect(launcher.canStart)
    #expect(launcher.unavailableReason == nil)
  }

  @Test func disabledWithoutAPageAndSaysWhy() throws {
    let (launcher, services) = make()
    let pulcini = try #require(try services.teams.list().first { $0.name == "Pulcini" })
    var draft = TeamDraft(pulcini)
    draft.csiPageURL = nil
    _ = try services.teams.update(id: pulcini.id, with: draft)
    launcher.refresh()
    #expect(!launcher.canStart)
    #expect(launcher.unavailableReason == ImportStrings.noCSIPageReason)
    var opened: [EntityID] = []
    launcher.begin { opened.append($0) }
    #expect(opened.isEmpty && !launcher.isPickerPresented)
  }

  @Test func oneTeamOpensDirectlySeveralAskInSortOrder() throws {
    let (launcher, services) = make()
    var opened: [EntityID] = []
    launcher.begin { opened.append($0) }
    #expect(opened.count == 1)
    #expect(!launcher.isPickerPresented)

    let other = try #require(try services.teams.list().first { $0.csiPageURL == nil && $0.isActive })
    var draft = TeamDraft(other)
    draft.csiPageURL = "https://live.centrosportivoitaliano.it/26/Calcio-a-7/Altro/G000009-girone-b/"
    _ = try services.teams.update(id: other.id, with: draft)
    launcher.begin { opened.append($0) }
    #expect(opened.count == 1)
    #expect(launcher.isPickerPresented)
    #expect(launcher.teams.map(\.sortOrder) == launcher.teams.map(\.sortOrder).sorted())
    launcher.pickedTeamID = other.id
    launcher.confirmPick { opened.append($0) }
    #expect(opened.last == other.id)
    #expect(!launcher.isPickerPresented)
  }
}
