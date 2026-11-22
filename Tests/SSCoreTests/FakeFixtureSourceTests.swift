import Foundation
import SSCoreFakes
import Testing

@testable import SSCore

@MainActor
@Suite struct FakeFixtureSourceTests {
  let services: AppServices

  init() throws {
    services = try AppServices.fake(dataSet: Fixtures.dataSet().shifted(toWeekendOf: .today()), renderDelay: .zero)
  }

  func team(_ name: String) throws -> Team { try #require(try services.teams.list().first { $0.name == name }) }

  /// What the staging review would show for every active team with a widget id.
  func stage() async throws -> (candidates: [String: ImportCandidate], issues: [String: ImportIssue]) {
    let settings = try services.settings.load()
    let opponents = try services.opponents.list()
    var candidates: [String: ImportCandidate] = [:]
    var issues: [String: ImportIssue] = [:]
    for team in try services.teams.list() where team.isActive && team.tuttocampoWidgetID != nil {
      do {
        switch try await services.fixtureSource.fetchFixtures(for: team, settings: settings) {
        case .fixtures(let fixtures):
          for fixture in fixtures {
            let existing = try services.matches.list(from: fixture.date, to: fixture.date, teamID: team.id)
            candidates[team.name] = ImportCandidate.make(
              fixture: fixture, team: team, opponents: opponents, existingMatches: existing,
              homeVenue: settings.homeVenue)
          }
        case .notYetAvailable:
          issues[team.name] = .notYetAvailable(team: team.name)
        case .sourceProblem(let problem):
          issues[team.name] = .sourceProblem(team: team.name, problem: problem, clubShortName: settings.clubShortName)
        }
      } catch let error as FixtureFetchError {
        issues[team.name] = .fetchFailed(team: team.name, reason: error)
      }
    }
    return (candidates, issues)
  }

  @Test func scenarioCoversEveryState() async throws {
    let (candidates, issues) = try await stage()
    let states = candidates.mapValues(\.state)
    #expect(
      states == [
        "Prima Squadra": .unchanged, "Juniores": .changed, "Allievi U17": .changed, "Allievi U16": .needsReview,
        "Pulcini": .changed, "Primi Calci": .locked, "Femminile": .unchanged, "Juniores Femminile": .needsReview,
        "Amatori": .new,
      ])
    #expect(candidates["Allievi U16"]?.reviewReasons == [.unknownStatus])
    #expect(candidates["Juniores Femminile"]?.reviewReasons == [.opponentNotFound])
    #expect(candidates["Allievi U17"]?.draft?.score == Score(us: 3, them: 1))
    #expect(candidates["Amatori"]?.draft?.venue == "Campo Comunale")
    #expect(
      issues == [
        "Giovanissimi U15": .sourceProblem(
          team: "Giovanissimi U15", problem: .structureChanged, clubShortName: "Sergnanese"),
        "Giovanissimi U14": .notYetAvailable(team: "Giovanissimi U14"),
        "Esordienti": .fetchFailed(team: "Esordienti", reason: .network),
      ])
  }

  @Test func committingTheScenarioWritesTheDrafts() async throws {
    let (candidates, _) = try await stage()
    let drafts = candidates.values.filter { [.new, .changed].contains($0.state) }.compactMap(\.draft)
    let summary = try services.matches.upsertFromImport(drafts)
    #expect(summary == ImportSummary(inserted: 1, updated: 3, skippedLocked: 0))
    let (again, _) = try await stage()
    #expect(again.values.filter { [.new, .changed].contains($0.state) }.isEmpty)
  }

  @Test func errorsForTeamsWithoutAnswers() async throws {
    let settings = try services.settings.load()
    var stranger = try team("Veterani")
    await #expect(throws: FixtureFetchError.missingWidgetID) {
      try await services.fixtureSource.fetchFixtures(for: stranger, settings: settings)
    }
    stranger.tuttocampoWidgetID = "00000000-0000-4000-8000-000000000099"
    await #expect(throws: FixtureFetchError.httpStatus(404)) {
      try await services.fixtureSource.fetchFixtures(for: stranger, settings: settings)
    }
  }

  @Test func logoDownloads() async throws {
    let source = services.fixtureSource
    let montesello = LogoRequest(
      opponentID: "a", opponentName: "Atletico Montesello", clubID: FakeFixtureSource.scenarioFallbackClubID,
      fallbackURL: URL(string: "https://b2-content.tuttocampo.it/Teams/40/900209.png?v=1"))
    let first = LogoRequest(opponentID: "b", opponentName: "Uno", clubID: "900301", fallbackURL: nil)
    let twin = LogoRequest(opponentID: "c", opponentName: "Due", clubID: "900301", fallbackURL: nil)
    let unknown = LogoRequest(opponentID: "d", opponentName: "Tre", clubID: nil, fallbackURL: nil)
    let results = await source.downloadLogos([montesello, first, twin, unknown])
    #expect(results.map(\.request) == [montesello, first, twin, unknown])
    #expect(results.map(\.fileName) == ["900209.png", "900301.png", "900301.png", nil])
    #expect(
      results.map(\.issue) == [
        .logoFallback(opponent: "Atletico Montesello"), nil, nil, .logoNotRecognised(opponent: "Tre"),
      ])
    let files = try FileManager.default.contentsOfDirectory(atPath: services.paths.logos.path)
    #expect(files.contains("900209.png") && files.contains("900301.png"))
  }

  @Test func failingLogosAndCancellation() async throws {
    let paths = try AppPaths.temporary()
    let source = FakeFixtureSource(logos: FakeLogoStore(folder: paths.logos), failingClubIDs: ["1"])
    let request = LogoRequest(opponentID: "a", opponentName: "Uno", clubID: "1", fallbackURL: nil)
    #expect(await source.downloadLogos([request]).first?.issue == .logoFailed(opponent: "Uno"))

    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await source.downloadLogos([
        LogoRequest(opponentID: "b", opponentName: "Due", clubID: "2", fallbackURL: nil)
      ])
    }
    let cancelled = await task.value
    #expect(cancelled.first?.fileName == nil && cancelled.first?.issue == nil)
  }

  @Test func scenarioWidgetIDsAreTheFixtureTeams() throws {
    let data = try Fixtures.dataSet()
    let ids = data.teams.compactMap(\.tuttocampoWidgetID)
    #expect(ids == (1...12).map(FakeFixtureSource.scenarioWidgetID))
    #expect(ids.allSatisfy(isValidTuttocampoWidgetID))
    #expect(data.teams.first { $0.name == "Veterani" }?.tuttocampoWidgetID == nil)
  }
}

@MainActor
@Suite struct FakeTeamWidgetIDTests {
  @Test func widgetIDsAreStoredAndUnique() throws {
    let services = try AppServices.fake(dataSet: .empty())
    let id = "00000000-0000-4000-8000-0000000000aa"
    let first = try services.teams.create(
      TeamDraft(
        name: "Prima", shortLabel: "Prima", tuttocampoWidgetID: "https://www.tuttocampo.it/WidgetV2/Risultati/\(id)"))
    #expect(first.tuttocampoWidgetID == id)
    #expect(throws: AppError.widgetIDInUse(by: "Prima")) {
      try services.teams.create(TeamDraft(name: "Altra", shortLabel: "Altra", tuttocampoWidgetID: id.uppercased()))
    }
    let second = try services.teams.create(TeamDraft(name: "Altra", shortLabel: "Altra"))
    var draft = TeamDraft(second)
    draft.tuttocampoWidgetID = id
    #expect(throws: AppError.widgetIDInUse(by: "Prima")) { try services.teams.update(id: second.id, with: draft) }
    // A team may keep its own id; clearing it frees the id.
    #expect(try services.teams.update(id: first.id, with: TeamDraft(first)).tuttocampoWidgetID == id)
    var cleared = TeamDraft(first)
    cleared.tuttocampoWidgetID = ""
    #expect(try services.teams.update(id: first.id, with: cleared).tuttocampoWidgetID == nil)
    #expect(try services.teams.update(id: second.id, with: draft).tuttocampoWidgetID == id)
    #expect(throws: AppError.self) {
      try services.teams.create(TeamDraft(name: "X", shortLabel: "X", tuttocampoWidgetID: "sbagliato"))
    }
  }
}
