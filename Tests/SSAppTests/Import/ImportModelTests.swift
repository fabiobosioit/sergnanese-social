import Foundation
import SSCore
import SSCoreFakes
import Synchronization
import Testing

@testable import SSApp

@MainActor
struct ImportModelTests {
  static let today = try! DayDate("2026-11-18")  // a Wednesday: the coming weekend is 21-22 November

  func makeServices() -> AppServices {
    var services = AppServices.fake(today: Self.today)
    services.fixtureSource = FakeFixtureSource.scenario(
      referenceSaturday: weekend(containing: Self.today).saturday, logos: services.logos, delay: .zero)
    return services
  }

  func makeModel(_ services: AppServices? = nil) -> ImportModel {
    ImportModel(services: services ?? makeServices(), today: { Self.today })
  }

  func candidate(_ model: ImportModel, _ team: String) throws -> ImportCandidate {
    try #require(model.candidates.first { $0.team.name == team })
  }

  // MARK: Selection

  @Test func tickPresetsWorkOnATuttocampoReview() async {
    let model = makeModel()
    await model.fetch()
    let tickable = model.candidates.filter(ImportModel.isTickable)
    #expect(model.hasTickableRows)
    model.applyTickPreset(.allImportable)
    #expect(model.tickedCandidates.count == tickable.count)
    model.applyTickPreset(.onlyNew)
    #expect(model.tickedCandidates.allSatisfy { $0.state == .new })
    model.applyTickPreset(.onlyChanged)
    #expect(!model.tickedCandidates.isEmpty && model.tickedCandidates.allSatisfy { $0.state == .changed })
    model.setAllVisibleTicked(false)
    #expect(model.tickedCandidates.isEmpty)
  }

  // MARK: Fetch

  @Test func statesFollowTheScenarioTable() async throws {
    let model = makeModel()
    await model.fetch()
    #expect(model.phase == .review)
    let expected: [String: ImportCandidate.State] = [
      "Prima Squadra": .unchanged, "Juniores": .changed, "Allievi U17": .changed, "Allievi U16": .needsReview,
      "Pulcini": .changed, "Primi Calci": .locked, "Femminile": .unchanged, "Juniores Femminile": .needsReview,
      "Amatori": .new,
    ]
    #expect(model.candidates.count == expected.count)
    for (team, state) in expected {
      #expect(try candidate(model, team).state == state, "\(team)")
    }
  }

  @Test func reportHasTheThreeTeamIssues() async {
    let model = makeModel()
    await model.fetch()
    #expect(model.issues.count == 3)
    #expect(
      model.issues.contains {
        if case .sourceProblem(let team, .structureChanged, _) = $0 { return team == "Giovanissimi U15" }
        return false
      })
    let info = model.issues.first { $0 == .notYetAvailable(team: "Giovanissimi U14") }
    #expect(info?.isError == false)
    #expect(model.issues.contains { $0 == .fetchFailed(team: "Esordienti", reason: .network) })
  }

  @Test func defaultTicksAreTheComingWeekendsNewAndChangedRows() async throws {
    let model = makeModel()
    await model.fetch()
    let ticked = Set(model.candidates.filter { model.isTicked($0) }.map(\.team.name))
    #expect(ticked == ["Juniores", "Allievi U17", "Pulcini", "Amatori"])
    #expect(model.canImport)
  }

  @Test func rowsThatCannotBeImportedCannotBeTicked() async throws {
    let model = makeModel()
    await model.fetch()
    for team in ["Prima Squadra", "Primi Calci", "Allievi U16", "Juniores Femminile"] {
      let row = try candidate(model, team)
      model.setTicked(row, true)
      #expect(!model.isTicked(row), "\(team)")
    }
  }

  @Test func candidatesAreGroupedByWeekendAndSorted() async {
    let model = makeModel()
    await model.fetch()
    #expect(model.sections.count == 1)
    #expect(model.sections.first?.title == formatWeekend(weekend(containing: Self.today), currentYear: 2026))
    let rows = model.sections.flatMap(\.candidates)
    #expect(rows == rows.sorted(by: ImportModel.stagingOrder))
    #expect(rows.first?.fixture.date == weekend(containing: Self.today).saturday)
  }

  @Test func changedRowsListOldAndNew() async throws {
    let model = makeModel()
    await model.fetch()
    let changes = model.changes(for: try candidate(model, "Juniores"))
    #expect(changes.contains { $0.hasPrefix("Orario:") && $0.contains("→") && $0.contains("11:00") })
    #expect(model.changes(for: try candidate(model, "Prima Squadra")).isEmpty)
  }

  @Test func cancellingStopsAndKeepsWhatWasRead() async throws {
    var services = makeServices()
    services.fixtureSource = StallingSource(base: services.fixtureSource, stallingFromCall: 3)
    let model = makeModel(services)
    model.start()
    try await waitUntil { model.progress?.current == 3 }
    model.cancelFetch()
    try await waitUntil { model.phase == .review }
    #expect(model.wasCancelled)
    #expect(model.candidates.map(\.team.name) == ["Juniores", "Prima Squadra"])
  }

  @Test func progressNamesTheTeamBeingRead() async throws {
    var services = makeServices()
    services.fixtureSource = StallingSource(base: services.fixtureSource, stallingFromCall: 3)
    let model = makeModel(services)
    model.start()
    try await waitUntil { model.progress?.current == 3 }
    #expect(model.phase == .fetching)
    let progress = try #require(model.progress)
    #expect(progress.total == 12)
    #expect(progress.team == "Allievi U17")
    #expect(
      ImportStrings.reading(progress.team, current: progress.current, total: progress.total)
        == "Lettura di Allievi U17… 3 di 12")
    model.cancelFetch()
    try await waitUntil { model.phase == .review }
  }

  // MARK: Availability

  @Test func commandIsDisabledWithoutWidgetIDs() throws {
    let services = makeServices()
    let model = makeModel(services)
    model.refreshAvailability()
    #expect(model.canStart)
    #expect(model.unavailableReason == nil)
    for team in try services.teams.list() {
      var draft = TeamDraft(team)
      draft.tuttocampoWidgetID = nil
      _ = try services.teams.update(id: team.id, with: draft)
    }
    model.refreshAvailability()
    #expect(!model.canStart)
    #expect(model.unavailableReason == ImportStrings.noWidgetReason)
    model.present()
    #expect(!model.isPresented)
  }

  @Test func inactiveTeamsDoNotCount() throws {
    let services = makeServices()
    for team in try services.teams.list() where team.tuttocampoWidgetID != nil && !team.isFirstTeam {
      var draft = TeamDraft(team)
      draft.isActive = false
      _ = try services.teams.update(id: team.id, with: draft)
    }
    let model = makeModel(services)
    model.refreshAvailability()
    #expect(model.canStart)  // the first team is still active and has a widget id
    let first = try #require(try services.teams.list().first(where: \.isFirstTeam))
    var draft = TeamDraft(first)
    draft.isActive = false
    _ = try services.teams.update(id: first.id, with: draft)
    model.refreshAvailability()
    #expect(!model.canStart)
  }

  // MARK: Commit

  @Test func commitWritesExactlyTheTickedRows() async throws {
    let services = makeServices()
    let model = makeModel(services)
    await model.fetch()
    let before = try services.matches.count(source: nil)
    await model.commit()
    #expect(model.phase == .done)
    let summary = try #require(model.summary)
    #expect(summary == ImportSummary(inserted: 1, updated: 3, skippedLocked: 0))
    #expect(model.summaryText == "1 nuova, 3 aggiornate, 0 bloccate")
    #expect(try services.matches.count(source: nil) == before + 1)
    let imported = try services.matches.count(source: .scrape)
    #expect(imported == 4)
  }

  @Test func lockedMatchIsNeverSentAndAnImportedRowBecomesUnchanged() async throws {
    let services = makeServices()
    let model = makeModel(services)
    await model.fetch()
    let locked = try candidate(model, "Primi Calci")
    let storedTime = locked.existing?.match.time
    await model.commit()
    #expect(try services.matches.get(id: #require(locked.existing).id).match.time == storedTime)
    model.dismiss()
    await model.fetch()
    for team in ["Juniores", "Allievi U17", "Pulcini", "Amatori"] {
      #expect(try candidate(model, team).state == .unchanged, "\(team)")
    }
    #expect(try candidate(model, "Primi Calci").state == .locked)
  }

  @Test func untickingARowLeavesItOut() async throws {
    let services = makeServices()
    let model = makeModel(services)
    await model.fetch()
    model.setTicked(try candidate(model, "Amatori"), false)
    await model.commit()
    #expect(model.summary == ImportSummary(inserted: 0, updated: 3, skippedLocked: 0))
  }

  // MARK: Opponents

  @Test func createOpponentResolvesTheRowAsNewWithVenueToComplete() async throws {
    let services = makeServices()
    let model = makeModel(services)
    await model.fetch()
    let row = try candidate(model, "Juniores Femminile")
    #expect(row.reviewReasons == [.opponentNotFound])
    model.createOpponent(for: row)
    let rebuilt = try candidate(model, "Juniores Femminile")
    #expect(rebuilt.state == .new)
    #expect(rebuilt.isVenueMissing)
    #expect(rebuilt.opponent?.name == "Atletico Nuovo Borgo")
    #expect(model.isTicked(rebuilt))
    model.setVenue("Campo Comunale", for: rebuilt)
    await model.commit()
    let date = rebuilt.fixture.date
    let stored = try services.matches.list(from: date, to: date, teamID: rebuilt.team.id)
    #expect(stored.first?.match.venue == "Campo Comunale")
    #expect(stored.first?.opponent.name == "Atletico Nuovo Borgo")
  }

  @Test func linkToExistingSavesTheAlias() async throws {
    let services = makeServices()
    let model = makeModel(services)
    await model.fetch()
    let row = try candidate(model, "Juniores Femminile")
    let target = try #require(try services.opponents.list().first { $0.name == "Real Cascina Alta" })
    model.link(row, to: target)
    let rebuilt = try candidate(model, "Juniores Femminile")
    #expect(rebuilt.opponent?.id == target.id)
    #expect(rebuilt.state == .new)
    #expect(try services.opponents.get(id: target.id).aliases.contains("Atletico Nuovo Borgo"))
    #expect(model.linkChoices(matching: "cascina").map(\.id) == [target.id])
  }

  // MARK: Logos

  @Test func logosAreRequestedOnlyForOpponentsWithoutOne() async throws {
    let services = makeServices()
    let model = makeModel(services)
    await model.fetch()
    let before = try Dictionary(uniqueKeysWithValues: services.opponents.list().map { ($0.name, $0.logoFile) })
    model.createOpponent(for: try candidate(model, "Juniores Femminile"))
    await model.commit()
    let after = try Dictionary(uniqueKeysWithValues: services.opponents.list().map { ($0.name, $0) })
    // Unchanged for opponents that had a logo.
    #expect(after["Virtus Campofelice"]?.logoFile == before["Virtus Campofelice"])
    // Atletico Montesello (a locked row, no logo): the fallback copy, named after the ClubId.
    #expect(after["Atletico Montesello"]?.logoFile == "900209.png")
    #expect(
      model.issues.contains { $0 == .logoFallback(opponent: "Atletico Montesello") })
    // The created opponent has an unrecognised address: reported, no logo.
    #expect(after["Atletico Nuovo Borgo"]?.logoFile == nil)
    #expect(model.issues.contains { $0 == .logoNotRecognised(opponent: "Atletico Nuovo Borgo") })
  }

  @Test func replaceToggleDownloadsAnExistingLogoAgain() async throws {
    let services = makeServices()
    let model = makeModel(services)
    await model.fetch()
    let amatori = try candidate(model, "Amatori")
    let opponent = try #require(amatori.opponent)
    let old = try #require(opponent.logoFile)
    model.setReplaceLogo(opponent, true)
    await model.commit()
    let updated = try services.opponents.get(id: opponent.id)
    #expect(updated.logoFile == "900212.png")
    #expect(updated.logoFile != old)
  }

  @Test func dismissForgetsEverything() async {
    let model = makeModel()
    await model.fetch()
    model.dismiss()
    #expect(model.phase == .idle)
    #expect(model.candidates.isEmpty)
    #expect(model.issues.isEmpty)
    #expect(!model.isPresented)
  }

  @Test func sourceThatIsUnavailableReportsEveryTeam() async {
    var services = makeServices()
    services.fixtureSource = FakeFixtureSource(responses: [:], logos: services.logos)
    let model = makeModel(services)
    await model.fetch()
    #expect(model.phase == .review)
    #expect(model.candidates.isEmpty)
    #expect(model.issues.count == 12)
    #expect(model.issues.allSatisfy { $0.isError })
  }
}

/// Answers like `base` until call number `stallingFromCall`, then waits (until cancelled).
private final class StallingSource: FixtureSource {
  let base: any FixtureSource
  let stallingFromCall: Int
  private let calls = Counter()

  init(base: any FixtureSource, stallingFromCall: Int) {
    self.base = base
    self.stallingFromCall = stallingFromCall
  }

  func fetchFixtures(for team: Team, settings: ClubSettings) async throws -> FixtureFetch {
    if calls.next() >= stallingFromCall { try await Task.sleep(for: .seconds(60)) }
    return try await base.fetchFixtures(for: team, settings: settings)
  }

  func downloadLogos(_ requests: [LogoRequest]) async -> [LogoResult] { await base.downloadLogos(requests) }
}

private final class Counter: Sendable {
  private let value = Mutex(0)
  func next() -> Int {
    value.withLock {
      $0 += 1; return $0
    }
  }
}

/// Polls `condition` on the main actor for up to five seconds.
@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
  for _ in 0..<500 {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  Issue.record("condition not reached")
}
