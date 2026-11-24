import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

/// T4.9: "Importa questa pagina" also keeps the list of every team on the page.
@MainActor
struct ImportModelCSITeamListTests {
  static let today = try! DayDate("2026-11-18")

  func makeModel(page: StubCSIPage = StubCSIPage()) throws -> (ImportModel, AppServices, Team) {
    let services = AppServices.fake(today: Self.today)
    let team = try #require(try services.teams.list().first { $0.name == "Pulcini" })
    let model = ImportModel(services: services, source: .csi(team: team, page: page), today: { Self.today })
    return (model, services, team)
  }

  @Test func readingThePageStoresItsTeams() async throws {
    let (model, services, team) = try makeModel()
    // The fake already holds a list; replace it by a different one to see the hook write.
    try services.sourceTeamLists.save(teamID: team.id, source: .csi, teams: [], readAt: .distantPast)
    await model.readCSIPage()
    let list = try #require(try services.sourceTeamLists.latest(teamID: team.id, source: .csi))
    #expect(list.teams == FakePageFixtureParser.scenarioTeams(teamID: team.id))
    #expect(list.readAt > .distantPast)
  }

  @Test func aPageThatIsNotAGironeStoresNothing() async throws {
    let page = StubCSIPage(url: "https://live.centrosportivoitaliano.it/26/Altro/G000099-altro/")
    let (model, services, team) = try makeModel(page: page)
    let before = try services.sourceTeamLists.latest(teamID: team.id, source: .csi)
    await model.readCSIPage()
    #expect(model.issues.count == 1)
    #expect(try services.sourceTeamLists.latest(teamID: team.id, source: .csi) == before)
  }
}
