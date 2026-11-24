import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

/// A store that holds no team list: every CSI team is "senza lettura".
private struct EmptyTeamLists: SourceTeamListRepository {
  func save(teamID: EntityID, source: TeamListSource, teams: [SourceTeam], readAt: Date) throws {}
  func latest(teamID: EntityID, source: TeamListSource) throws -> SourceTeamList? { nil }
}

@MainActor
struct OpponentDownloadModelTests {
  static let today = try! DayDate("2026-11-18")

  func makeModel(
    services: AppServices = AppServices.fake(today: today), csiLogos: Bool = true
  ) -> (OpponentDownloadModel, AppServices) {
    var reader: OpponentDownloadModel.CSILogoReader?
    if csiLogos { reader = { @MainActor @Sendable _ in FakeFixtureSource.defaultLogoData } }
    return (OpponentDownloadModel(services: services, csiLogoReader: reader), services)
  }

  func candidate(_ model: OpponentDownloadModel, _ name: String) throws -> OpponentCandidate {
    try #require(model.candidates.first { $0.name == name }, "\(name)")
  }

  func pair(_ model: OpponentDownloadModel, _ first: String, _ second: String) throws -> OpponentDuplicatePair {
    try #require(model.pairs.first { $0.firstName == first && $0.secondName == second }, "\(first) / \(second)")
  }

  // MARK: Reading

  @Test func rowsAndStatesFollowTheScenario() async throws {
    let (model, _) = makeModel()
    await model.read()
    #expect(model.phase == .review)
    let expected: [String: OpponentCandidate.State] = [
      "Aurora Pianengo": .new, "Polisportiva Fontanella": .new, "Atletico Nuovo Borgo": .new,
      "Borgo Lucente": .missingLogo, "Atletico Montesello": .missingLogo,
      "Real Fontanile": .possibleDuplicate, "Real Fontanile B": .possibleDuplicate,
      "Valdorso 2016": .possibleDuplicate,
    ]
    for (name, state) in expected {
      #expect(try candidate(model, name).state == state, "\(name)")
    }
    #expect(model.pairs.count == 2)
    let aurora = try candidate(model, "Aurora Pianengo")
    #expect(aurora.sightings.count == 2)
    #expect(model.sightingLines(aurora) == ["Tuttocampo · Prima Squadra", "Tuttocampo · Juniores"])
    let montesello = try candidate(model, "Atletico Montesello")
    #expect(model.sightingLines(montesello).first?.hasPrefix("CSI · Pulcini, letto il ") == true)
    #expect(model.rowLogo(aurora) == .available)
  }

  @Test func presentRowsAreGreyedAndCannotBeTicked() async throws {
    let (model, _) = makeModel()
    await model.read()
    let present = try #require(model.candidates.first { $0.state == .present })
    #expect(!model.isTickable(present))
    model.setTicked(present, true)
    #expect(!model.isTicked(present))
    #expect(!model.ticked.contains(present.id))
    #expect(model.tickedCount == model.candidates.filter { $0.state != .present }.count)
  }

  @Test func reportListsTheTeamsThatCouldNotBeRead() async throws {
    let (model, _) = makeModel()
    await model.read()
    #expect(model.readingIssues.contains(.standingsChanged(team: "Giovanissimi U15")))
    #expect(model.readingIssues.contains(.standingsReadFailed(team: "Esordienti", reason: .network)))
    #expect(!model.readingIssues.contains { if case .csiTeamListMissing = $0 { true } else { false } })
  }

  @Test func aCSITeamWithoutAStoredListIsReported() async throws {
    var services = AppServices.fake(today: Self.today)
    services.sourceTeamLists = EmptyTeamLists()
    let (model, _) = makeModel(services: services)
    await model.read()
    #expect(model.readingIssues.contains(.csiTeamListMissing(team: "Pulcini")))
    #expect(model.candidates.allSatisfy { candidate in candidate.sightings.allSatisfy { $0.source == .tuttocampo } })
  }

  @Test func cancellingTheReadingWritesNothing() async throws {
    let (model, services) = makeModel()
    let before = try services.opponents.list()
    let task = Task { await model.read() }
    task.cancel()
    await task.value
    #expect(model.phase == .idle)
    #expect(model.candidates.isEmpty)
    #expect(try services.opponents.list() == before)
  }

  @Test func nothingIsWrittenBeforeSave() async throws {
    let (model, services) = makeModel()
    let before = try services.opponents.list()
    await model.read()
    try model.setAllChoices()
    #expect(try services.opponents.list() == before)
  }

  // MARK: Choices

  @Test func saveWaitsForBothChoices() async throws {
    let (model, _) = makeModel()
    await model.read()
    #expect(!model.canSave)
    #expect(model.planMessage == OpponentPlanError.choicesMissing(pairIDs: []).message)
    let fontanile = try pair(model, "Real Fontanile", "Real Fontanile B")
    model.setChoice(.useFirst, for: fontanile)
    #expect(!model.canSave)
    let valdorso = try #require(model.pairs.first { $0.firstName == "Valdorso 2016" })
    model.setChoice(.useSecond, for: valdorso)
    #expect(model.canSave)
    #expect(model.planMessage == nil)
  }

  @Test func untickingTheSecondRowRemovesTheNeedForItsChoice() async throws {
    let (model, _) = makeModel()
    await model.read()
    let fontanile = try pair(model, "Real Fontanile", "Real Fontanile B")
    #expect(model.needsChoice(fontanile))
    model.setTicked(try candidate(model, "Real Fontanile B"), false)
    #expect(!model.needsChoice(fontanile))
    let valdorso = try #require(model.pairs.first { $0.firstName == "Valdorso 2016" })
    model.setChoice(.useSecond, for: valdorso)
    #expect(model.canSave)
  }

  @Test func conflictingChoicesKeepSaveDisabled() async throws {
    let services = AppServices.fake(today: Self.today)
    let pulcini = try #require(try services.teams.list().first { $0.name == "Pulcini" })
    var teams = FakePageFixtureParser.scenarioTeams(teamID: pulcini.id)
    teams.append(SourceTeam(source: .csi, teamID: pulcini.id, name: "Real Fontanile C"))
    try services.sourceTeamLists.save(teamID: pulcini.id, source: .csi, teams: teams, readAt: Date())
    let (model, _) = makeModel(services: services)
    await model.read()
    let valdorso = try #require(model.pairs.first { $0.firstName == "Valdorso 2016" })
    model.setChoice(.useSecond, for: valdorso)
    model.setChoice(.useFirst, for: try pair(model, "Real Fontanile", "Real Fontanile B"))
    model.setChoice(.useSecond, for: try pair(model, "Real Fontanile", "Real Fontanile C"))
    model.setChoice(.keepSeparate, for: try pair(model, "Real Fontanile B", "Real Fontanile C"))
    #expect(!model.canSave)
    if case .failure(.conflictingChoices) = model.plan {} else { Issue.record("expected a conflict") }
    #expect(model.planMessage?.isEmpty == false)
  }

  // MARK: Save

  @Test func savingCreatesMergesAndStoresTheLogos() async throws {
    let (model, services) = makeModel()
    let before = try services.opponents.list()
    await model.read()
    model.setChoice(.useFirst, for: try pair(model, "Real Fontanile", "Real Fontanile B"))
    let valdorso = try #require(model.pairs.first { $0.firstName == "Valdorso 2016" })
    model.setChoice(.useSecond, for: valdorso)
    await model.save()
    #expect(model.phase == .done)

    let after = try services.opponents.list()
    #expect(after.count == before.count + 4)
    func opponent(_ name: String) throws -> Opponent { try #require(after.first { $0.name == name }, "\(name)") }
    #expect(try opponent("Real Fontanile").aliases == ["Real Fontanile B"])
    #expect(try opponent("Real Fontanile").logoFile == "900302.png")
    #expect(try opponent("Aurora Pianengo").logoFile == "900303.png")
    #expect(try opponent("Polisportiva Fontanella").logoFile == "csi-90000103.png")
    #expect(try opponent("Atletico Nuovo Borgo").logoFile == nil)
    let valdorsoOpponent = try #require(after.first { $0.name.contains("Valdorso") })
    #expect(valdorsoOpponent.aliases.contains("Valdorso 2016"))
    let borgo = try #require(after.first { $0.name.contains("Borgo Lucente") })
    #expect(borgo.logoFile == "900301.png")
    let montesello = try #require(after.first { $0.name.contains("Montesello") })
    #expect(montesello.logoFile == "csi-90000104.png")

    // Every opponent that had a logo keeps exactly that logo.
    for old in before where old.logoFile != nil {
      #expect(after.first { $0.id == old.id }?.logoFile == old.logoFile)
    }
    let summary = try #require(model.summary)
    #expect(summary.created == 4)
    #expect(summary.logos == 5)
    #expect(model.reportIssues.contains(.logoNotRecognised(opponent: "Atletico Nuovo Borgo")))
    if let firstWarning = model.reportIssues.firstIndex(where: { !$0.isError }),
      let lastError = model.reportIssues.lastIndex(where: { $0.isError })
    {
      #expect(lastError < firstWarning)
    }
  }

  @Test func withoutDirectDownloadCSILogosAreReportedUnavailable() async throws {
    let (model, services) = makeModel(csiLogos: false)
    await model.read()
    try model.setAllChoices()
    await model.save()
    let after = try services.opponents.list()
    #expect(after.first { $0.name == "Polisportiva Fontanella" }?.logoFile == nil)
    #expect(model.reportIssues.contains(.csiLogoUnavailable(opponent: "Polisportiva Fontanella")))
    #expect(after.first { $0.name == "Aurora Pianengo" }?.logoFile == "900303.png")
  }

  // MARK: The screen

  @Test func theCommandNeedsASource() throws {
    let withSources = OpponentsViewModel(services: AppServices.fake(today: Self.today))
    withSources.reload()
    #expect(withSources.downloadUnavailableReason == nil)
    #expect(withSources.canDownload)

    let empty = OpponentsViewModel(services: try AppServices.fake(dataSet: FakeDataSet.empty()))
    empty.reload()
    #expect(empty.downloadUnavailableReason == OpponentsStrings.downloadUnavailable)
    #expect(!empty.canDownload)
  }

  @Test func closingTheSheetReloadsTheList() async throws {
    let vm = OpponentsViewModel(services: AppServices.fake(today: Self.today))
    vm.reload()
    vm.beginDownload()
    let model = try #require(vm.download)
    #expect(!vm.canDownload)
    model.cancelReading()
    #expect(vm.download == nil)
  }
}

extension OpponentDownloadModel {
  /// Picks "first name" for every pair that needs a choice.
  func setAllChoices() throws {
    for pair in pairs { setChoice(.useFirst, for: pair) }
  }
}
