import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

/// T4.11b: the season run of "Importa da Tuttocampo" against the fake source (Primi Calci has the 10-matchday season).
@MainActor
struct ImportModelSeasonTests {
  static let today = try! DayDate("2026-11-18")  // a Wednesday: the current matchday (5) is on Sunday 22 November

  func makeServices(delay: Duration = .zero) -> AppServices {
    var services = AppServices.fake(today: Self.today)
    services.fixtureSource = FakeFixtureSource.scenario(
      referenceSaturday: weekend(containing: Self.today).saturday, logos: services.logos, delay: delay)
    return services
  }

  func makeDefaults() -> UserDefaults {
    let name = "ImportModelSeasonTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  func makeModel(
    _ services: AppServices? = nil, scope: ImportScope, only teamName: String? = nil,
    maxPages: Int = SeasonLimits.maxPagesPerRun,
    defaults: UserDefaults? = nil
  ) throws -> ImportModel {
    let services = services ?? makeServices()
    let model = ImportModel(
      services: services, today: { Self.today }, maxPagesPerRun: maxPages, defaults: defaults ?? makeDefaults())
    model.present()
    model.scope = scope
    if let teamName {
      let team = try #require(try services.teams.list().first { $0.name == teamName })
      model.chosenTeamIDs = [team.id]
    }
    return model
  }

  func rows(_ model: ImportModel) -> [Int: ImportCandidate] {
    Dictionary(
      model.candidates.compactMap { candidate in candidate.fixture.round.map { ($0, candidate) } },
      uniquingKeysWith: { first, _ in first })
  }

  // MARK: Start panel

  @Test func presentOpensTheStartPanelWithoutReading() throws {
    let model = try makeModel(scope: .weekend)
    #expect(model.phase == .choosing)
    #expect(model.isPresented)
    #expect(model.estimate == nil)
    let withWidget = try makeServices().teams.list().filter { $0.isActive && $0.tuttocampoWidgetID != nil }
    #expect(model.startableTeams.count == withWidget.count)  // active teams with a widget id; all ticked
    #expect(model.chosenTeamIDs.count == model.startableTeams.count)
    #expect(model.candidates.isEmpty)
    #expect(model.canStartRun)
  }

  @Test func atLeastOneTeamMustBeTicked() throws {
    let model = try makeModel(scope: .wholeSeason)
    model.chosenTeamIDs = []
    #expect(!model.canStartRun)
    model.startRun()
    #expect(model.phase == .choosing)
  }

  @Test func weekendScopeIsTodaysFlow() async throws {
    let model = try makeModel(scope: .weekend)
    await model.fetch()
    #expect(model.phase == .review)
    #expect(!model.isSeasonRun)
    #expect(model.seasonSummaryText == nil)
    #expect(model.candidates.count == 9)
  }

  // MARK: Estimate

  @Test func estimateUsesAssumedThenKnownLengths() async throws {
    let defaults = makeDefaults()
    let model = try makeModel(scope: .fromCurrentMatchday, only: "Primi Calci", defaults: defaults)
    #expect(model.estimate?.message == "circa 30 richieste, circa 1 minuto")
    await model.fetch()
    model.dismiss()
    model.present()
    model.scope = .fromCurrentMatchday
    model.chosenTeamIDs = [try #require(model.startableTeams.first { $0.name == "Primi Calci" }).id]
    #expect(model.estimate?.message == "circa 6 richieste, circa 1 minuto")
    model.scope = .wholeSeason
    #expect(model.estimate?.message == "circa 10 richieste, circa 1 minuto")

    // The next launch has it too.
    let next = ImportModel(services: makeServices(), today: { Self.today }, defaults: defaults)
    next.present()
    next.scope = .fromCurrentMatchday
    next.chosenTeamIDs = model.chosenTeamIDs
    #expect(next.estimate?.message == "circa 6 richieste, circa 1 minuto")
  }

  // MARK: Whole season

  @Test func wholeSeasonOnPrimiCalci() async throws {
    let model = try makeModel(scope: .wholeSeason, only: "Primi Calci")
    await model.fetch()
    #expect(model.phase == .review)
    let rows = rows(model)
    #expect(rows.keys.sorted() == [1, 2, 4, 5, 6, 8, 9, 10])
    #expect(model.candidates.count == 8)
    #expect(rows[5]?.state == .locked)
    #expect(rows[6]?.state == .changed)
    #expect(rows[9]?.state == .needsReview)
    #expect(rows[10]?.state == .new)
    #expect(rows[10]?.fixture.time == nil)
    for matchday in [1, 2, 4, 8, 10] { #expect(rows[matchday]?.state == .new, "matchday \(matchday)") }
    // Past new rows are ticked with the whole season; locked and needs-review rows are not.
    let ticked = Set(model.ticked.compactMap { id in model.candidates.first { $0.id == id }?.fixture.round })
    #expect(ticked == [1, 2, 4, 6, 8, 10])
    #expect(
      model.issues == [
        .seasonMatchdayFailed(team: "Primi Calci", matchday: 3, reason: .timeout),
        .seasonBye(team: "Primi Calci", matchday: 7),
      ])
    #expect(model.issues.first?.message.contains("giornata 3") == true)
    #expect(model.seasonSummaryText == "8 partite in 8 giornate, 1 squadra; 1 riposo; 1 giornata non letta")
  }

  @Test func pastWeekendsAreCollapsedUntilOpened() async throws {
    let model = try makeModel(scope: .wholeSeason, only: "Primi Calci")
    await model.fetch()
    let sections = model.sections
    #expect(sections.count == 8)
    let collapsed = sections.filter(model.isCollapsed)
    #expect(collapsed.count == 3)  // matchdays 1, 2 and 4
    #expect(sections.filter { !model.isCollapsed($0) }.count == 5)
    #expect(model.visibleCandidates.count == 5)
    model.toggleCollapsed(collapsed[0])
    #expect(!model.isCollapsed(collapsed[0]))
    #expect(model.visibleCandidates.count == 6)
    model.toggleCollapsed(collapsed[0])
    #expect(model.isCollapsed(collapsed[0]))
  }

  // MARK: From today

  @Test func fromCurrentMatchdayHasNoPastRows() async throws {
    let model = try makeModel(scope: .fromCurrentMatchday, only: "Primi Calci")
    await model.fetch()
    #expect(rows(model).keys.sorted() == [5, 6, 8, 9, 10])
    #expect(model.sections.allSatisfy { !model.isCollapsed($0) })
    let ticked = Set(model.ticked.compactMap { id in model.candidates.first { $0.id == id }?.fixture.round })
    #expect(ticked == [6, 8, 10])
    #expect(model.issues == [.seasonBye(team: "Primi Calci", matchday: 7)])
    #expect(model.seasonSummaryText == "5 partite in 5 giornate, 1 squadra; 1 riposo; 0 giornate non lette")
  }

  // MARK: All teams

  @Test func allTeamsWholeSeasonMatchTheWeekendScenario() async throws {
    let model = try makeModel(scope: .wholeSeason)
    await model.fetch()
    #expect(model.phase == .review)
    #expect(model.issues.contains { $0 == .fetchFailed(team: "Esordienti", reason: .network) })
    #expect(model.issues.contains { $0 == .notYetAvailable(team: "Giovanissimi U14") })
    let changed = model.issues.first { $0 == .seasonMatchdayChanged(team: "Giovanissimi U15", matchday: 1) }
    #expect(changed?.message.contains("potrebbe essere cambiata") == true)
    let perTeam = Dictionary(grouping: model.candidates, by: \.team.name).mapValues(\.count)
    #expect(perTeam["Primi Calci"] == 8)
    for team in [
      "Prima Squadra", "Juniores", "Allievi U17", "Allievi U16", "Pulcini", "Femminile", "Juniores Femminile",
      "Amatori",
    ] {
      #expect(perTeam[team] == 1, "\(team)")
    }
    #expect(perTeam["Esordienti"] == nil)
  }

  // MARK: Filter and selection

  @Test func teamFilterNarrowsTheVisibleRows() async throws {
    let model = try makeModel(scope: .wholeSeason)
    await model.fetch()
    #expect(model.filterTeams.count == 9)
    let primi = try #require(model.filterTeams.first { $0.name == "Primi Calci" })
    model.teamFilter = primi.id
    #expect(model.sections.flatMap(\.candidates).allSatisfy { $0.team.id == primi.id })
    #expect(model.sections.count == 8)
    model.teamFilter = nil
    #expect(model.sections.flatMap(\.candidates).count == model.candidates.count)
  }

  @Test func selectAllAndNoneActOnVisibleRows() async throws {
    let model = try makeModel(scope: .wholeSeason, only: "Primi Calci")
    await model.fetch()
    model.setAllVisibleTicked(false)
    // The collapsed past rows were not visible, so they keep their ticks.
    let remaining = model.ticked.compactMap { id in model.candidates.first { $0.id == id }?.fixture.round }
    #expect(Set(remaining) == [1, 2, 4])
    model.setAllVisibleTicked(true)
    let all = Set(model.ticked.compactMap { id in model.candidates.first { $0.id == id }?.fixture.round })
    #expect(all == [1, 2, 4, 6, 8, 10])  // locked and needs-review rows can never be ticked
    model.setAllVisibleTicked(false)
    model.teamFilter = nil
    #expect(model.canImport == true)  // the collapsed rows are still ticked
  }

  // MARK: Cancellation and cap

  @Test func cancellingKeepsRowsReadAndStartsNoOtherTeam() async throws {
    let model = try makeModel(makeServices(delay: .milliseconds(40)), scope: .wholeSeason)
    model.startRun()
    #expect(model.phase == .fetching)
    while model.seasonProgress == nil { try await Task.sleep(for: .milliseconds(5)) }
    model.cancelFetch()
    while model.phase == .fetching { try await Task.sleep(for: .milliseconds(5)) }
    #expect(model.phase == .review)
    #expect(model.wasCancelled)
    // The rows of the teams read before Annulla stay; the others were never started.
    #expect(!model.candidates.isEmpty)
    #expect(model.candidates.count < 9)
    #expect(model.progress == nil)
    #expect(!model.issues.contains { if case .seasonStopped = $0 { true } else { false } })
  }

  @Test func cancellingInTheMiddleOfASeasonKeepsItsPages() async throws {
    let model = try makeModel(
      makeServices(delay: .milliseconds(30)), scope: .wholeSeason, only: "Primi Calci")
    model.startRun()
    while (model.seasonProgress?.pagesRead ?? 0) < 3 { try await Task.sleep(for: .milliseconds(5)) }
    model.cancelFetch()
    while model.phase == .fetching { try await Task.sleep(for: .milliseconds(5)) }
    #expect(model.wasCancelled)
    #expect(model.candidates.count >= 2)
    #expect(model.candidates.count < 8)
    #expect(!model.issues.contains { if case .seasonStopped = $0 { true } else { false } })
  }

  @Test func perRunCapStopsTheTeamAndNamesTheUnreadTeams() async throws {
    // Cap of 3 pages: Prima Squadra (1 page), then Juniores (1), then Allievi U17 (1) reach it.
    let model = try makeModel(scope: .wholeSeason, maxPages: 3)
    await model.fetch()
    #expect(model.phase == .review)
    #expect(model.runPagesRead <= 3)
    #expect(!model.wasCancelled)
    let teams = Set(model.candidates.map(\.team.name))
    #expect(teams == ["Prima Squadra", "Juniores", "Allievi U17"])
    // The last team was read in full (its season has one page), so only the teams after it are named.
    let note = try #require(model.notes.first)
    #expect(note.contains("limite di 3 richieste"))
    #expect(!note.contains("Allievi U17"))
    #expect(note.contains("Primi Calci"))
  }

  @Test func perRunCapCutsASeasonInTheMiddle() async throws {
    let model = try makeModel(scope: .wholeSeason, only: "Primi Calci", maxPages: 4)
    await model.fetch()
    #expect(model.candidates.count == 3)  // pages 5, 1 and 2 (3 is a failed page; the 4th page hits the cap)
    #expect(model.notes.first?.contains("Primi Calci") == true)
    #expect(!model.issues.contains { if case .seasonStopped = $0 { true } else { false } })
  }

  // MARK: Commit

  @Test func importWritesTheTickedSeasonRows() async throws {
    let services = makeServices()
    let model = try makeModel(services, scope: .wholeSeason, only: "Primi Calci")
    await model.fetch()
    let before = try services.matches.count(source: nil)
    await model.commit()
    #expect(model.phase == .done)
    // 5 new (matchdays 1, 2, 4, 8, 10) and 1 changed (6); the locked row is never written.
    #expect(model.summary == ImportSummary(inserted: 5, updated: 1, skippedLocked: 0))
    #expect(try services.matches.count(source: nil) == before + 5)
  }
}
