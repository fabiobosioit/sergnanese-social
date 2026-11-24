import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSImport

private let classificaPage = URL(
  string: "https://www.tuttocampo.it/WidgetV2/Classifica/00000000-0000-4000-8000-000000000001")!

private func parse(_ html: String) -> LeagueTeamsFetch {
  parseClassifica(
    html: html, pageURL: classificaPage, team: testTeam(widgetID: nil), clubShortName: testSettings.clubShortName)
}

private func teams(_ html: String) throws -> [SourceTeam] {
  guard case .teams(let teams) = parse(html) else {
    Issue.record("expected teams")
    return []
  }
  return teams
}

private func row(
  _ name: String?, logo: String? = "https://b2-content.tuttocampo.it/Teams/40/900001.png?v=1", selected: Bool = false
) -> String {
  """
  <tr class="playoff \(selected ? "selected" : "")">
  <td class="team_logo">\(logo.map { "<img alt='x' src='\($0)' srcset='https://example.invalid/2x.png 2x'/>" } ?? "")</td>
  <td class="team">\(name.map { "<a class=\"ext_link\" href=\"https://www.tuttocampo.it/s\">\($0)</a>" } ?? "")</td>
  <td class="points pt">1</td></tr>
  """
}

private func page(_ rows: String, table: Bool = true) -> String {
  table
    ? "<html><body><table class=\"tc-table table_ranking\"><thead><tr><th>x</th></tr></thead><tbody>\(rows)</tbody></table></body></html>"
    : "<html><body><p>niente</p></body></html>"
}

@Suite("Tuttocampo Classifica parser")
struct TuttocampoClassificaParserTests {
  @Test("classifica-normal: 15 teams in table order, ours absent, ClubIds and logo addresses read")
  func normal() throws {
    let result = try teams(try tuttocampoFixture("classifica-normal"))
    #expect(result.count == 15)
    #expect(result.first?.name == "Alba Rossa")
    #expect(result.first?.logoID == "900113")
    #expect(result.first?.logoURL?.absoluteString == "https://b2-content.tuttocampo.it/Teams/40/900113.png?v=9")
    #expect(
      result.map(\.logoID)
        == [
          900113, 900120, 900127, 900134, 900141, 900148, 900155, 900162, 900169, 900176, 900183, 900190, 900197,
          900204, 900211,
        ].map { String($0) })
    #expect(!result.contains { $0.name == "Sergnanese" })
    #expect(result.allSatisfy { $0.source == .tuttocampo && $0.teamID == "team-1" })
    #expect(result.allSatisfy { $0.logoURL?.path.hasPrefix("/Teams/40/") == true })
  }

  @Test("no table, empty tbody, a row without a name are structureChanged")
  func structure() throws {
    #expect(parse(page("", table: false)) == .structureChanged)
    #expect(parse(page("")) == .structureChanged)
    #expect(parse(page(row("Uno") + row(nil))) == .structureChanged)
    #expect(parse(page(row("   "))) == .structureChanged)
  }

  @Test("a row without an image has no logo; an unrecognised address keeps the URL")
  func logos() throws {
    let result = try teams(page(row("Senza", logo: nil) + row("Strano", logo: "https://example.invalid/x/logo.png")))
    #expect(result[0].logoID == nil && result[0].logoURL == nil)
    #expect(result[1].logoID == nil)
    #expect(result[1].logoURL?.absoluteString == "https://example.invalid/x/logo.png")
  }

  @Test("a relative logo address is made absolute against the page")
  func relative() throws {
    let result = try teams(page(row("Uno", logo: "/Teams/40/900001.png?v=1")))
    #expect(result[0].logoURL?.absoluteString == "https://www.tuttocampo.it/Teams/40/900001.png?v=1")
    #expect(result[0].logoID == nil)  // only the logo host's addresses carry a ClubId
  }

  @Test("our row is left out by name even without the selected class")
  func oursByName() throws {
    let result = try teams(page(row("Uno") + row("ASD Sergnanese") + row("Due")))
    #expect(result.map(\.name) == ["Uno", "Due"])
    let plain = try teams(page(row("Sergnanese") + row("Uno")))
    #expect(plain.map(\.name) == ["Uno"])
  }

  @Test("our row missing is not an error: every row is returned")
  func oursMissing() throws {
    let fixture = try tuttocampoFixture("classifica-normal").replacingOccurrences(
      of: "playoff  selected", with: "playoff "
    ).replacingOccurrences(of: ">Sergnanese<", with: ">Altro Club<")
    #expect(try teams(fixture).count == 16)
  }

  @Test("a name seen twice is returned once; whitespace is collapsed")
  func duplicates() throws {
    let result = try teams(page(row("Borgo  Verde") + row("Borgo Verde") + row(" BORGO\n Verde ")))
    #expect(result.map(\.name) == ["Borgo Verde"])
  }
}

@Suite("Tuttocampo Classifica fetch")
struct TuttocampoClassificaFetchTests {
  private let widgetID = "00000000-0000-4000-8000-000000000001"

  private func run(_ reply: StubReply, widget: String? = "00000000-0000-4000-8000-000000000001") async throws
    -> (LeagueTeamsFetch, StubServer)
  {
    let path = "/WidgetV2/Classifica/\(widgetID)"
    let server = StubServer { request in request.url?.path == path ? reply : nil }
    let folder = try TempFolder()
    defer { folder.cleanup() }
    let source = TuttocampoWidgetSource(
      logos: FakeLogoStore(folder: folder.url), configuration: server.configuration(), minimumInterval: .zero)
    let result = try await source.fetchLeagueTeams(for: testTeam(widgetID: widget), settings: testSettings)
    return (result, server)
  }

  @Test("one GET of the Classifica address; teams parsed")
  func ok() async throws {
    let (result, server) = try await run(.html(try tuttocampoFixture("classifica-normal")))
    guard case .teams(let teams) = result else {
      Issue.record("expected teams")
      return
    }
    #expect(teams.count == 15)
    #expect(server.requestedURLs == ["https://www.tuttocampo.it/WidgetV2/Classifica/\(widgetID)"])
    #expect(server.unexpected.isEmpty)
  }

  @Test("a page without a table is structureChanged")
  func changed() async throws {
    let (result, _) = try await run(.html("<html><body>x</body></html>"))
    #expect(result == .structureChanged)
  }

  @Test("404 is httpStatus(404)")
  func notFound() async throws {
    await #expect(throws: FixtureFetchError.httpStatus(404)) { try await run(.notFound) }
  }

  @Test("a redirect off the allowlist is notAllowed and never followed")
  func redirect() async throws {
    await #expect(throws: FixtureFetchError.notAllowed) { try await run(.redirect(to: "https://evil.example/x")) }
  }

  @Test("no widget id is missingWidgetID and makes no request")
  func missing() async throws {
    await #expect(throws: FixtureFetchError.missingWidgetID) { try await run(.notFound, widget: nil) }
  }
}
