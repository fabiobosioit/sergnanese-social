import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSRender

/// Planning (dry run) on the fake repositories and the four built-in manifests of `FakeTemplateStore`.
@MainActor
@Suite struct RenderPlanTests {
  func service(_ database: FakeDatabase) throws -> TemplateRenderService {
    let paths = try AppPaths.temporary()
    return TemplateRenderService(
      templates: FakeTemplateStore(folder: paths.templates), matches: FakeMatchRepository(database: database),
      renders: FakeRenderRepository(database: database), settings: FakeSettingsRepository(database: database),
      paths: paths)
  }

  @Test func defaultPlanOnTheFixtureData() throws {
    let dataSet = try Fixtures.dataSet()
    let database = FakeDatabase(dataSet)
    let weekend = Weekend(saturday: dataSet.referenceSaturday)
    let plan = try service(database).plan(RenderRequest(weekend: weekend))

    let inRange = try FakeMatchRepository(database: database).list(
      from: weekend.saturday, to: weekend.sunday, teamID: nil)
    let excluded = inRange.filter { $0.match.status == .postponed || $0.match.status == .cancelled }
    #expect(!excluded.isEmpty)
    #expect(plan.skippedMatchIDs == excluded.map(\.id))
    #expect(Set(plan.selections.map(\.templateID)) == ["story-programme", "post-prematch"])

    let programme = plan.images.filter { $0.templateID == "story-programme" }
    let plannedMatches = Set(programme.flatMap(\.matchIDs))
    #expect(plannedMatches == Set(inRange.map(\.id)).subtracting(excluded.map(\.id)))
    #expect(Set(programme.map(\.date)).count == Set(inRange.filter { !excluded.contains($0) }.map(\.match.date)).count)

    let posts = plan.images.filter { $0.templateID == "post-prematch" }
    let firstTeamIDs = inRange.filter { $0.team.isFirstTeam && !excluded.contains($0) }.map(\.id)
    #expect(posts.flatMap(\.matchIDs) == firstTeamIDs)
    #expect(posts.allSatisfy { $0.width == 1080 && $0.height == 1350 && $0.page == nil })
    #expect(posts.allSatisfy { $0.fileName.hasPrefix("\($0.date.value)_post-prematch_prima-squadra_vs_") })
    // Every warning of every image, without duplicates.
    #expect(Set(plan.warnings).count == plan.warnings.count)
    #expect(Set(plan.warnings) == Set(plan.images.flatMap(\.warnings)))
  }

  // MARK: Results recap (T4.5a)

  /// `count` matches: the first `saturdayCount` on Saturday, the rest on Sunday.
  func recapMatches(saturday saturdayCount: Int, sunday sundayCount: Int) -> [Match] {
    TestData.manyMatches(saturdayCount, date: TestData.saturday).map {
      var m = $0; m.id = "s" + m.id; return m
    }
      + TestData.manyMatches(sundayCount)
  }

  func recapPlan(_ matches: [Match], template: String = "story-results") throws -> RenderPlan {
    try service(TestData.database(matches: matches)).plan(
      RenderRequest(
        from: TestData.saturday, to: TestData.sunday,
        selections: [TemplateSelection(templateID: template, matchIDs: matches.map(\.id))]))
  }

  @Test func recapIsOneSetOfPagesForTheWholeWeekend() throws {
    let plan = try recapPlan(recapMatches(saturday: 3, sunday: 5))
    #expect(plan.images.count == 1)
    #expect(plan.images[0].date == TestData.saturday)
    #expect(plan.images[0].fileName == "2026-11-21_story-results_1of1.png")
    #expect(plan.images[0].matchIDs.count == 8)
  }

  @Test func recapWith13MatchesGivesTwoPagesBothDatedSaturday() throws {
    let plan = try recapPlan(recapMatches(saturday: 6, sunday: 7))
    #expect(plan.images.map { $0.page?.label } == ["1/2", "2/2"])
    #expect(plan.images.allSatisfy { $0.date == TestData.saturday })
    #expect(plan.images.map(\.fileName) == ["2026-11-21_story-results_1of2.png", "2026-11-21_story-results_2of2.png"])
  }

  @Test func programmeStillGivesOneSetPerDay() throws {
    let plan = try recapPlan(recapMatches(saturday: 3, sunday: 5), template: "story-programme")
    #expect(plan.images.count == 2)
    #expect(Set(plan.images.map(\.date)) == [TestData.saturday, TestData.sunday])
  }

  @Test func defaultPlanNeverIncludesARecap() throws {
    let played = recapMatches(saturday: 2, sunday: 2).map {
      var m = $0; m.score = Score(us: 1, them: 0); return m
    }
    let plan = try service(TestData.database(matches: played)).plan(
      RenderRequest(from: TestData.saturday, to: TestData.sunday))
    #expect(!plan.selections.contains { $0.templateID == "story-results" })
    #expect(!plan.images.contains { $0.templateID == "story-results" })
  }

  @Test func standardFixtureFollowsTheManifest() {
    let fixtures = URL(fileURLWithPath: "/f")
    func name(_ id: String) -> String {
      let manifest = FakeTemplateStore.builtinManifests.first { $0.id == id }!
      return FixtureContexts.standardFile(for: manifest, in: fixtures).lastPathComponent
    }
    #expect(name("story-results") == "list-results.context.json")
    #expect(name("story-programme") == "list.context.json")
    #expect(name("post-prematch") == "single.context.json")
  }

  @Test func previewOfARecapWithoutMatchesUsesTheResultsFixture() async throws {
    let paths = try AppPaths.temporary()
    let database = TestData.database(matches: [])
    let builder = TemplateRenderService(
      templates: FakeTemplateStore(folder: paths.templates), matches: FakeMatchRepository(database: database),
      renders: FakeRenderRepository(database: database), settings: FakeSettingsRepository(database: database),
      paths: paths)
    let manifest = FakeTemplateStore.builtinManifests.first { $0.id == "story-results" }!
    let context = try FixtureContexts.load(
      FixtureContexts.standardFile(for: manifest, in: paths.fixtures), for: manifest)
    guard case .list(let list) = context else { Issue.record("not a list"); return }
    #expect(list.title == "Risultati del weekend")
    _ = builder
  }

  @Test func nextFixtureWeekendNeedsTwoProgrammePages() throws {
    let dataSet = try Fixtures.dataSet()
    let plan = try service(FakeDatabase(dataSet)).plan(
      RenderRequest(weekend: Weekend(saturday: dataSet.referenceSaturday).next))
    let sundayPages = plan.images.filter { $0.templateID == "story-programme" && $0.date.isoWeekday == 7 }
    #expect(sundayPages.map { $0.page?.label } == ["1/2", "2/2"])
    #expect(sundayPages.map(\.fileName).last?.hasSuffix("_story-programme_2of2.png") == true)
  }

  @Test func listPagination23RowsGivesThreeImages() throws {
    let database = TestData.database(matches: TestData.manyMatches(23))
    let request = RenderRequest(
      from: TestData.saturday, to: TestData.sunday,
      selections: [TemplateSelection(templateID: "story-programme", matchIDs: TestData.manyMatches(23).map(\.id))])
    let plan = try service(database).plan(request)
    #expect(plan.images.count == 3)
    #expect(plan.images.map { $0.page?.label } == ["1/3", "2/3", "3/3"])
    #expect(plan.images.map(\.matchIDs.count) == [10, 10, 3])
    #expect(plan.skippedMatchIDs.isEmpty)
  }

  @Test func explicitSelectionsKeepPostponedMatchesWithAWarning() throws {
    let postponed = TestData.match("p", status: .postponed)
    let database = TestData.database(matches: [postponed])
    let request = RenderRequest(
      from: TestData.saturday, to: TestData.sunday,
      selections: [TemplateSelection(templateID: "post-prematch", matchIDs: ["p"])])
    let plan = try service(database).plan(request)
    #expect(plan.images.count == 1)
    #expect(plan.warnings.contains { $0.kind == .matchNotScheduled && $0.matchID == "p" })

    let defaultPlan = try service(database).plan(RenderRequest(from: TestData.saturday, to: TestData.sunday))
    #expect(defaultPlan.images.isEmpty)
    #expect(defaultPlan.skippedMatchIDs == ["p"])
  }

  @Test func unknownTemplateOrMatchIsNotFound() throws {
    let database = TestData.database(matches: [TestData.match("x")])
    let renderService = try service(database)
    #expect(throws: AppError.notFound) {
      _ = try renderService.plan(
        RenderRequest(
          from: TestData.saturday, to: TestData.sunday,
          selections: [TemplateSelection(templateID: "nope", matchIDs: ["x"])]))
    }
    #expect(throws: AppError.notFound) {
      _ = try renderService.plan(
        RenderRequest(
          from: TestData.saturday, to: TestData.sunday,
          selections: [TemplateSelection(templateID: "post-prematch", matchIDs: ["missing"])]))
    }
  }
}
