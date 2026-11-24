import Foundation
import Testing

@testable import SSCore
@testable import SSCoreFakes

/// T4.9 fakes: the Classifica scenario, the stored CSI list, `applyImport` and the team-list store.
@MainActor
@Suite struct FakeOpponentDownloadTests {
  let services: AppServices

  init() throws {
    services = try AppServices.fake(dataSet: Fixtures.dataSet().shifted(toWeekendOf: .today()), renderDelay: .zero)
  }

  func team(_ name: String) throws -> Team { try #require(try services.teams.list().first { $0.name == name }) }

  /// What "Scarica tutti gli avversari…" would find: every active team's Classifica and stored CSI list.
  func download() async throws -> (found: [SourceTeam], issues: [String: ImportIssue]) {
    let settings = try services.settings.load()
    var found: [SourceTeam] = []
    var issues: [String: ImportIssue] = [:]
    for team in try services.teams.list() where team.isActive {
      if team.tuttocampoWidgetID != nil {
        do {
          switch try await services.fixtureSource.fetchLeagueTeams(for: team, settings: settings) {
          case .teams(let teams): found += teams
          case .structureChanged: issues[team.name] = .standingsChanged(team: team.name)
          }
        } catch let error as FixtureFetchError {
          issues[team.name] = .standingsReadFailed(team: team.name, reason: error)
        }
      }
      if team.csiPageURL != nil {
        if let list = try services.sourceTeamLists.latest(teamID: team.id, source: .csi) {
          found += list.teams
        } else {
          issues["CSI " + team.name] = .csiTeamListMissing(team: team.name)
        }
      }
    }
    return (found, issues)
  }

  @Test func scenarioCoversEveryRowState() async throws {
    let (found, issues) = try await download()
    #expect(
      issues == [
        "Giovanissimi U15": .standingsChanged(team: "Giovanissimi U15"),
        "Esordienti": .standingsReadFailed(team: "Esordienti", reason: .network),
      ])
    let pulcini = try team("Pulcini")
    #expect(found.filter { $0.source == .csi }.allSatisfy { $0.teamID == pulcini.id })
    #expect(
      try found.filter { $0.source == .tuttocampo && $0.name == "Real Fontanile" }.map(\.teamID) == [
        team("Prima Squadra").id
      ])

    let opponents = try services.opponents.list()
    let rows = OpponentCandidate.make(found: found, existing: opponents, clubShortName: "Sergnanese")
    let states = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0.state) })
    #expect(
      states == [
        "Atletico Montesello": .missingLogo, "Atletico Nuovo Borgo": .new, "Aurora Pianengo": .new,
        "Borgo Lucente": .missingLogo, "Polisportiva Fontanella": .new, "Novaria Bassa": .present,
        "Oratorio San Gerolamo": .present, "Prato Fiorito": .present, "Real Fontanile": .possibleDuplicate,
        "Real Fontanile B": .possibleDuplicate, "Sporting Ripalta Nuova": .present, "Valdorso 2016": .possibleDuplicate,
        "Virtus Campofelice": .present,
      ])
    #expect(rows.first { $0.name == "Aurora Pianengo" }?.sightings.count == 2)
    #expect(rows.first { $0.name == "Borgo Lucente" }?.logo?.logoID == "900301")
    let valdorso = try #require(opponents.first { $0.name == "F.C. Valdorso" })
    #expect(
      OpponentCandidate.possibleDuplicatePairs(in: rows, existing: opponents).map(\.id) == [
        "real fontanile|c:real fontanile b", "valdorso 2016|o:\(valdorso.id)",
      ])
  }

  @Test func scenarioSavesAndStoresLogos() async throws {
    let (found, _) = try await download()
    let opponents = try services.opponents.list()
    let rows = OpponentCandidate.make(found: found, existing: opponents, clubShortName: "Sergnanese")
    let pairs = OpponentCandidate.possibleDuplicatePairs(in: rows, existing: opponents)
    let plan = try OpponentImportPlan.make(
      candidates: rows, ticked: Set(rows.filter(\.isTickedByDefault).map(\.id)), pairs: pairs,
      choices: [pairs[0].id: .useFirst, pairs[1].id: .useSecond])
    let saved = try services.opponents.applyImport(plan)
    #expect(saved.count == plan.items.count)
    let after = try services.opponents.list()
    #expect(after.count == opponents.count + 4)
    #expect(after.first { $0.name == "Real Fontanile" }?.aliases == ["Real Fontanile B"])
    #expect(after.first { $0.name == "F.C. Valdorso" }?.aliases == ["Valdorso 2016"])

    // Logos: tuttocampo through the fixture source, CSI through `storeCSILogos`.
    var tuttocampo: [LogoRequest] = []
    var fromCSI: [CSILogoData] = []
    for (item, opponent) in zip(plan.items, saved) where opponent.logoFile == nil {
      guard let logo = item.logo else { continue }
      if let request = LogoRequest(opponent: opponent, sourceTeam: logo) { tuttocampo.append(request) }
      if let request = CSILogoRequest(opponent: opponent, sourceTeam: logo) {
        fromCSI.append(CSILogoData(request: request, data: FakeFixtureSource.defaultLogoData))
      }
    }
    let results = await services.fixtureSource.downloadLogos(tuttocampo)
    let stored = Dictionary(uniqueKeysWithValues: results.map { ($0.request.opponentName, $0) })
    #expect(stored["Borgo Lucente"]?.fileName == nil)  // the fixture opponent is "Pol. Borgo Lucente"
    #expect(stored["Pol. Borgo Lucente"]?.fileName == "900301.png")
    #expect(stored["Atletico Nuovo Borgo"]?.issue == .logoNotRecognised(opponent: "Atletico Nuovo Borgo"))
    #expect(stored["Real Fontanile"]?.fileName == "900302.png")
    let csiResults = await storeCSILogos(fromCSI, in: services.logos)
    #expect(
      Set(csiResults.compactMap(\.fileName)) == ["csi-90000103.png", "csi-90000104.png"])
  }

  @Test func applyImportIsAllOrNothing() throws {
    let before = try services.opponents.list()
    let unknown = OpponentImportPlan(items: [
      .init(action: .create(name: "Aurora Pianengo", aliases: []), logo: nil, candidateIDs: ["aurora pianengo"]),
      .init(action: .update(opponentID: "missing", rename: "X", addAliases: []), logo: nil, candidateIDs: ["x"]),
    ])
    #expect(throws: AppError.notFound) { try services.opponents.applyImport(unknown) }
    #expect(try services.opponents.list() == before)

    let tooLong = OpponentImportPlan(items: [
      .init(action: .create(name: "Aurora Pianengo", aliases: []), logo: nil, candidateIDs: ["aurora pianengo"]),
      .init(
        action: .update(opponentID: before[0].id, rename: nil, addAliases: [String(repeating: "x", count: 81)]),
        logo: nil, candidateIDs: ["x"]),
    ])
    #expect(throws: AppError.self) { try services.opponents.applyImport(tooLong) }
    #expect(try services.opponents.list() == before)
  }

  @Test func applyImportRenamesAndKeepsIDLogoAndShortName() throws {
    let gerolamo = try #require(try services.opponents.list().first { $0.name == "A.S.D. Oratorio San Gerolamo" })
    let plan = OpponentImportPlan(items: [
      .init(
        action: .update(
          opponentID: gerolamo.id, rename: "Oratorio San Gerolamo 2016", addAliases: ["Oratorio S. Gerolamo"]),
        logo: nil, candidateIDs: ["oratorio san gerolamo 2016"])
    ])
    let saved = try services.opponents.applyImport(plan)
    #expect(
      saved == [
        Opponent(
          id: gerolamo.id, name: "Oratorio San Gerolamo 2016", shortName: gerolamo.shortName,
          aliases: ["Oratorio S. Gerolamo", "A.S.D. Oratorio San Gerolamo"], logoFile: gerolamo.logoFile)
      ])
    #expect(try services.opponents.get(id: gerolamo.id) == saved[0])
  }

  @Test func teamListsAreKeptPerTeamAndSourceAndGoWithTheTeam() throws {
    let lists = FakeSourceTeamListRepository(database: FakeDatabase())
    let database = lists.database
    let teams = FakeTeamRepository(database: database)
    let first = try teams.create(TeamDraft(name: "Prima Squadra", shortLabel: "Prima"))
    let other = try teams.create(TeamDraft(name: "Pulcini", shortLabel: "Pulcini"))
    let readAt = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(try lists.latest(teamID: other.id, source: .csi) == nil)
    try lists.save(
      teamID: other.id, source: .csi, teams: FakePageFixtureParser.scenarioTeams(teamID: "x"), readAt: readAt)
    try lists.save(
      teamID: other.id, source: .csi, teams: [SourceTeam(source: .tuttocampo, teamID: "x", name: "Aurora")],
      readAt: readAt.addingTimeInterval(60))
    #expect(
      try lists.latest(teamID: other.id, source: .csi)
        == SourceTeamList(
          teamID: other.id, source: .csi, readAt: readAt.addingTimeInterval(60),
          teams: [SourceTeam(source: .csi, teamID: other.id, name: "Aurora")]))
    #expect(try lists.latest(teamID: other.id, source: .tuttocampo) == nil)
    #expect(try lists.latest(teamID: first.id, source: .csi) == nil)
    #expect(throws: AppError.notFound) { try lists.latest(teamID: "missing", source: .csi) }
    #expect(throws: AppError.notFound) { try lists.save(teamID: "missing", source: .csi, teams: [], readAt: readAt) }

    try teams.delete(id: other.id)
    #expect(database.read { $0.sourceTeamLists.isEmpty })
  }

  @Test func fakeSourcesForTeamLists() async throws {
    let pulcini = try team("Pulcini")
    let html = "<html></html>"
    let page = try #require(URL(string: FakePageFixtureParser.scenarioPageURL + "?j=abc"))
    let teams = services.csiPageParser.teams(html: html, pageURL: page, for: pulcini, settings: .defaults)
    #expect(teams == FakePageFixtureParser.scenarioTeams(teamID: pulcini.id))
    let other = try #require(URL(string: "https://live.centrosportivoitaliano.it/altro/girone/"))
    #expect(services.csiPageParser.teams(html: html, pageURL: other, for: pulcini, settings: .defaults).isEmpty)

    let stored = try #require(try services.sourceTeamLists.latest(teamID: pulcini.id, source: .csi))
    #expect(stored.teams == teams)

    let veterani = try team("Veterani")
    await #expect(throws: FixtureFetchError.missingWidgetID) {
      try await services.fixtureSource.fetchLeagueTeams(for: veterani, settings: .defaults)
    }
    var unknown = veterani
    unknown.tuttocampoWidgetID = "00000000-0000-4000-8000-000000000099"
    await #expect(throws: FixtureFetchError.httpStatus(404)) {
      try await services.fixtureSource.fetchLeagueTeams(for: unknown, settings: .defaults)
    }
  }
}
