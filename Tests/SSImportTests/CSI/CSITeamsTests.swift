import Foundation
import SSCore
import Testing

@testable import SSImport

@Suite("CSI team list")
struct CSITeamsTests {
  private let parser = CSIPageParser()
  private let team = Team(
    id: "team-9", name: "Pulcini", shortLabel: "Pulcini", sortOrder: 1, isFirstTeam: false, isActive: true)

  private func teams(_ html: String, settings: ClubSettings = csiTestSettings) -> [SourceTeam] {
    parser.teams(html: html, pageURL: csiTestPage, for: team, settings: settings)
  }

  @Test("girone-sample: the three other teams once each, in page order; placeholder has no logo")
  func sample() throws {
    let result = teams(try csiFixture("girone-sample"))
    #expect(result.map(\.name) == ["ASD Esempio Uno", "US Esempio Due 2016", "Polisportiva Esempio Tre"])
    #expect(result.map(\.logoID) == ["90000002", nil, "90000004"])
    #expect(result[0].logoURL?.absoluteString.hasSuffix("/90000002_202601010000.jpg") == true)
    #expect(result[1].logoURL == nil)
    #expect(result[2].logoURL?.absoluteString.hasSuffix("/90000004_202601010000.jpg") == true)
    #expect(result.allSatisfy { $0.source == .csi && $0.teamID == "team-9" })
  }

  @Test("girone-no-table gives no team; girone-no-ours gives every team")
  func variants() throws {
    #expect(teams(try csiFixture("girone-no-table")).isEmpty)
    let all = teams(try csiFixture("girone-no-ours"))
    #expect(!all.isEmpty)
    #expect(!all.contains { $0.name == "Sergnanese" })
    #expect(Set(all.map(\.name)).count == all.count)
  }

  @Test("teams without an id are deduplicated by name; same id under two spellings once")
  func dedupe() {
    let noID = "https://example.invalid/logo.png"
    let html = csiPage(
      body: csiRow(code: "P1A1", home: "Club Uno", away: "Club Due", homeLogo: noID, awayLogo: noID)
        + csiRow(code: "P1A2", home: "ASD Club Uno", away: "Club Tre", homeLogo: noID, awayLogo: noID))
    let result = teams(html)
    #expect(result.map(\.name) == ["Club Uno", "Club Due", "Club Tre"])
    #expect(result.allSatisfy { $0.logoID == nil })
  }

  @Test("a page parse calls structureChanged gives no team")
  func notAGirone() {
    #expect(teams("<html><body>niente</body></html>").isEmpty)
  }
}
