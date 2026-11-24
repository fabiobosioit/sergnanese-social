import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

@MainActor
struct ResultModelTests {
  static let today = try! DayDate("2026-11-18")  // the reference weekend is 21-22 November

  final class Shared {
    var shared: [[URL]] = []
  }

  @MainActor struct Rig {
    let app: AppModel
    let defaults: UserDefaults
    let shared: Shared
    var services: AppServices { app.services }
    var renderer: FakeRenderService { services.renderer as! FakeRenderService }

    func details(weekend: Weekend? = nil) throws -> [MatchDetail] {
      let weekend = weekend ?? app.weekend
      return try services.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)
    }

    func detail(team: String, home: Bool? = nil) throws -> MatchDetail {
      try #require(try details().first { $0.team.name == team && (home == nil || $0.match.isHome == home) })
    }

    @MainActor func model(for detail: MatchDetail) -> ResultModel {
      let shared = shared
      return ResultModel(detail: detail, app: app, defaults: defaults) { shared.shared.append($0) }
    }

    func stored(_ id: EntityID) throws -> Match { try services.matches.get(id: id).match }

    func records(_ templateID: String, matchID: EntityID) throws -> [RenderRecord] {
      try services.renders.list(from: nil, to: nil).filter {
        $0.templateID == templateID && $0.matchIDs.contains(matchID)
      }
    }
  }

  func rig(delay: Duration = .zero) throws -> Rig {
    let data = try Fixtures.dataSet().shifted(toWeekendOf: Self.today)
    let services = try AppServices.fake(dataSet: data, renderDelay: delay)
    let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let app = AppModel(services: services, isDemo: true, defaults: defaults, today: { Self.today })
    return Rig(app: app, defaults: defaults, shared: Shared())
  }

  // MARK: Half-time and final stories

  @Test func halfTimeStoryStoresTheResultRendersAndShares() async throws {
    let rig = try rig()
    let detail = try rig.detail(team: "Prima Squadra", home: true)
    let model = rig.model(for: detail)
    model.form.halfTimeHome = "1"
    model.form.halfTimeAway = "0"
    await model.generate(.halfTime)

    let stored = try rig.stored(detail.id)
    #expect(stored.halfTime == Score(us: 1, them: 0))
    #expect(stored.status == .scheduled)
    #expect(model.isFinished)
    let records = try rig.records("story-halftime", matchID: detail.id)
    #expect(records.count == 1)
    // The share picker opens after the sheet has closed.
    #expect(rig.shared.shared.isEmpty)
    model.sheetDidDismiss()
    #expect(rig.shared.shared == [records.map(\.fileURL)])
    model.sheetDidDismiss()
    #expect(rig.shared.shared.count == 1)
  }

  @Test func fullTimeStoryPlaysTheMatchAndKeepsTheScorers() async throws {
    let rig = try rig()
    let detail = try rig.detail(team: "Prima Squadra", home: true)
    let model = rig.model(for: detail)
    model.form.finalHome = "2"
    model.form.finalAway = "1"
    model.form.scorers = "Rossi 23', Bianchi 78'"
    await model.generate(.fullTime)

    let stored = try rig.stored(detail.id)
    #expect(stored.status == .played)
    #expect(stored.score == Score(us: 2, them: 1))
    #expect(stored.notes == "Rossi 23', Bianchi 78'")
    #expect(try rig.records("story-fulltime", matchID: detail.id).count == 1)
    model.sheetDidDismiss()
    #expect(rig.shared.shared.count == 1)
    #expect(rig.app.dataRevision > 0)
  }

  @Test func awayMatchStoresUsAndThem() async throws {
    let rig = try rig()
    let detail = try rig.detail(team: "Juniores", home: false)
    let model = rig.model(for: detail)
    model.form.finalHome = "0"
    model.form.finalAway = "3"
    #expect(model.save())
    #expect(try rig.stored(detail.id).score == Score(us: 3, them: 0))
    #expect(model.homeName != model.awayName)
    #expect(model.awayName == model.ourName)
  }

  @Test func inconsistentResultIsAFieldProblemAndNothingHappens() async throws {
    let rig = try rig()
    let detail = try rig.detail(team: "Prima Squadra", home: true)
    let model = rig.model(for: detail)
    model.form.halfTimeHome = "1"
    model.form.halfTimeAway = "0"
    model.form.finalHome = "0"
    model.form.finalAway = "1"
    await model.generate(.fullTime)
    #expect(model.problem(for: .score) == MatchesStrings.ResultEntry.finalBelowHalfTime)
    #expect(try rig.stored(detail.id) == detail.match)
    #expect(try rig.records("story-fulltime", matchID: detail.id).isEmpty)
    #expect(!model.isFinished)
  }

  @Test func generateWithoutAnyResultStillRenders() async throws {
    let rig = try rig()
    let detail = try rig.detail(team: "Prima Squadra", home: true)
    let model = rig.model(for: detail)
    await model.generate(.halfTime)
    #expect(model.isFinished)
    #expect(try rig.records("story-halftime", matchID: detail.id).count == 1)
    #expect(try rig.stored(detail.id).halfTime == nil)
  }

  // MARK: Eligibility

  @Test func postponedAndCancelledMatchesHaveNoResultEntry() throws {
    let rig = try rig()
    let vm = MatchesViewModel(app: rig.app)
    vm.reload()
    let postponed = try rig.detail(team: "Femminile")
    #expect(postponed.match.status == .postponed)
    #expect(!vm.canEnterResult([postponed.id]))
    let scheduled = try rig.detail(team: "Prima Squadra", home: true)
    #expect(vm.canEnterResult([scheduled.id]))
    #expect(!vm.canEnterResult([scheduled.id, postponed.id]))
    #expect(!vm.canEnterResult([]))
    vm.beginResult([postponed.id])
    #expect(!vm.isResultPresented && vm.resultModel == nil)
    vm.beginResult([scheduled.id])
    #expect(vm.isResultPresented && vm.resultModel?.matchID == scheduled.id)
  }

  // MARK: Cancel and failure

  @Test func cancellingARenderKeepsTheResultAndSharesNothing() async throws {
    let rig = try rig(delay: .seconds(30))
    let detail = try rig.detail(team: "Prima Squadra", home: true)
    let model = rig.model(for: detail)
    model.form.finalHome = "2"
    model.form.finalAway = "1"
    model.startGenerate(.fullTime)
    while !model.isWorking { await Task.yield() }
    model.cancelRender()
    while model.isWorking { await Task.yield() }
    await rig.renderer.waitUntilIdle()
    #expect(!model.isFinished)
    #expect(model.errorMessage == nil)
    model.sheetDidDismiss()
    #expect(rig.shared.shared.isEmpty)
    #expect(try rig.stored(detail.id).score == Score(us: 2, them: 1))
    #expect(try rig.records("story-fulltime", matchID: detail.id).isEmpty)
  }

  @Test func aFailingRenderShowsAnErrorAndSharesNothing() async throws {
    let rig = try rig()
    rig.renderer.failingTemplateIDs = ["story-fulltime"]
    let detail = try rig.detail(team: "Prima Squadra", home: true)
    let model = rig.model(for: detail)
    model.form.finalHome = "2"
    model.form.finalAway = "1"
    await model.generate(.fullTime)
    #expect(model.errorMessage != nil)
    #expect(!model.isFinished)
    model.sheetDidDismiss()
    #expect(rig.shared.shared.isEmpty)
    #expect(try rig.stored(detail.id).score == Score(us: 2, them: 1))
  }

  // MARK: Template choice

  func secondTemplate(purpose: TemplatePurpose, id: String, in rig: Rig) throws {
    let source = try rig.services.templates.get(id: purpose == .halftime ? "story-halftime" : "story-fulltime")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tpl-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var manifest = source.manifest
    manifest.id = id
    manifest.name = "Zeta \(id)"
    try Fixtures.makeEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
    try Data("<html></html>".utf8).write(to: folder.appendingPathComponent("template.html"))
    _ = try rig.services.templates.install(from: folder, replace: true)
  }

  @Test func templateChoiceWithNoneOneAndSeveral() throws {
    // One built-in each: used.
    let rig = try rig()
    let detail = try rig.detail(team: "Prima Squadra", home: true)
    var model = rig.model(for: detail)
    #expect(model.candidates(for: .halfTime).map(\.id) == ["story-halftime"])
    #expect(model.chosenTemplate(for: .fullTime)?.id == "story-fulltime")
    #expect(model.candidates(for: .recap).map(\.id) == ["story-results"] || model.candidates(for: .recap).isEmpty)

    // Several: the first built-in until another is picked; the pick is remembered per purpose.
    try secondTemplate(purpose: .halftime, id: "story-halftime-b", in: rig)
    model = rig.model(for: detail)
    #expect(model.candidates(for: .halfTime).count == 2)
    #expect(model.choice[.halfTime] == "story-halftime")
    model.choose("story-halftime-b", for: .halfTime)
    #expect(model.choice[.halfTime] == "story-halftime-b")
    #expect(model.choice[.fullTime] == "story-fulltime")
    model = rig.model(for: detail)
    #expect(model.choice[.halfTime] == "story-halftime-b")
  }

  @Test func chooseResultTemplatePrefersRememberedThenBuiltinThenFirst() {
    func template(_ id: String, builtin: Bool) -> InstalledTemplate {
      InstalledTemplate(
        manifest: TemplateManifest(
          id: id, name: id, version: "1.0.0", format: .story, width: 1080, height: 1920, kind: .single,
          purpose: .halftime),
        folder: URL(fileURLWithPath: "/tmp"), isBuiltin: builtin)
    }
    let user = template("a-user", builtin: false)
    let builtin = template("z-builtin", builtin: true)
    #expect(chooseResultTemplate(from: [], remembered: nil) == nil)
    #expect(chooseResultTemplate(from: [user], remembered: nil) == "a-user")
    #expect(chooseResultTemplate(from: [user, builtin], remembered: nil) == "z-builtin")
    #expect(chooseResultTemplate(from: [user, builtin], remembered: "a-user") == "a-user")
    #expect(chooseResultTemplate(from: [user, builtin], remembered: "gone") == "z-builtin")
  }

  // MARK: Recap

  @Test func recapOfThePreviousWeekendRendersOneImageWithEveryMatch() async throws {
    let rig = try rig()
    rig.app.goToPreviousWeekend()
    let shared = rig.shared
    let recap = RecapModel(app: rig.app, defaults: rig.defaults) { shared.shared.append($0) }
    recap.refresh()
    let everyMatch = try rig.details().map(\.id)
    #expect(everyMatch.count == 4)
    #expect(recap.isVisible && recap.canGenerate)
    #expect(
      recap.request(templateID: "story-results").selections == [
        TemplateSelection(templateID: "story-results", matchIDs: everyMatch)
      ])
    await recap.generate()
    #expect(!recap.isWorking)
    #expect(shared.shared.count == 1 && shared.shared[0].count == 1)
    let records = try rig.services.renders.list(from: rig.app.weekend.saturday, to: rig.app.weekend.sunday)
      .filter { $0.templateID == "story-results" }
    #expect(records.count == 1)
    #expect(records[0].date == rig.app.weekend.saturday)
    #expect(Set(records[0].matchIDs) == Set(everyMatch))
  }

  @Test func recapIsHiddenBeforeAnyScore() throws {
    let rig = try rig()
    let recap = RecapModel(app: rig.app, defaults: rig.defaults) { _ in }
    recap.refresh()
    #expect(!recap.isVisible && !recap.canGenerate)
    let vm = MatchesViewModel(app: rig.app)
    vm.reload()
    #expect(!vm.recap.canGenerate)
  }

  @Test func recapIgnoresPartiteScopeAndFiltersAndBecomesVisibleWithAScore() async throws {
    let rig = try rig()
    let vm = MatchesViewModel(app: rig.app)
    vm.reload()
    #expect(!vm.recap.isVisible)
    vm.scope = .all
    vm.teamFilter = try rig.detail(team: "Juniores", home: false).team.id
    #expect(vm.recap.matches.count == (try rig.details().count))
    let detail = try rig.detail(team: "Prima Squadra", home: true)
    let model = rig.model(for: detail)
    model.form.finalHome = "1"
    model.form.finalAway = "1"
    #expect(model.save())
    vm.reload()
    #expect(vm.recap.isVisible && vm.recap.canGenerate)
  }

  @Test func recapFailureGoesToTheAppAlert() async throws {
    let rig = try rig()
    rig.app.goToPreviousWeekend()
    rig.renderer.failingTemplateIDs = ["story-results"]
    let recap = RecapModel(app: rig.app, defaults: rig.defaults) { _ in Issue.record("must not share") }
    recap.refresh()
    await recap.generate()
    #expect(rig.app.errorMessage != nil)
  }
}
