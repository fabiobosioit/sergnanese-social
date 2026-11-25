import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

@MainActor
struct GenerateViewModelTests {
  static let today = try! DayDate("2026-11-18")  // a Wednesday; the coming weekend is 21-22 November

  final class Probe {
    var updates: [(Int, Int)] = []
    var finished = 0
    /// Called after each progress update; lets a test wait for "image n is in the model" without polling.
    var onUpdate: ((Int, Int) -> Void)?
  }

  func makeModel(
    dataSet: FakeDataSet? = nil, delay: Duration = .milliseconds(2), probe: Probe = Probe()
  ) throws -> (GenerateViewModel, AppModel) {
    let data = try dataSet ?? Fixtures.dataSet().shifted(toWeekendOf: Self.today)
    let services = try AppServices.fake(dataSet: data, renderDelay: delay)
    let app = AppModel(
      services: services, isDemo: true, defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!,
      today: { Self.today })
    let model = GenerateViewModel(
      app: app,
      progress: {
        probe.updates.append(($0, $1))
        probe.onUpdate?($0, $1)
      },
      progressDone: { probe.finished += 1 })
    model.reload()
    return (model, app)
  }

  // MARK: Plan and selection

  @Test func defaultSelectionFollowsThePlan() throws {
    let (model, _) = try makeModel()
    #expect(model.load == .loaded)
    #expect(model.details.count == 10)
    // The postponed match is skipped and starts unchecked.
    #expect(model.skippedMatchIDs.count == 1)
    #expect(model.checkedMatchIDs.count == 9)
    #expect(model.checkedTemplateIDs == ["story-programme", "post-prematch"])
    #expect(model.totalImages > 0)
    #expect(model.canGenerate)
    let programme = model.templateRows.first { $0.id == "story-programme" }
    #expect(programme?.imageCount == 2)
    #expect(programme?.matchCount == 9)
  }

  @Test func zeroMatchesDisablesGenerate() throws {
    let (model, _) = try makeModel(dataSet: .empty(today: Self.today))
    #expect(model.details.isEmpty)
    #expect(model.totalImages == 0)
    #expect(!model.canGenerate)
    #expect(model.disabledReason == GenerateStrings.reasonNoMatch)
  }

  @Test func oneMatchGivesOneImagePerSelectedTemplate() throws {
    var data = try Fixtures.dataSet().shifted(toWeekendOf: Self.today)
    let firstTeam = try #require(data.teams.first { $0.isFirstTeam })
    let sunday = data.referenceSaturday.adding(days: 1)
    let one = try #require(data.matches.first { $0.date == sunday && $0.teamID == firstTeam.id })
    data.matches = [one]
    let (model, _) = try makeModel(dataSet: data)
    #expect(model.details.count == 1)
    #expect(model.checkedMatchIDs.count == 1)
    // programme (one page) + pre-match post
    #expect(model.totalImages == 2)
    #expect(model.canGenerate)
  }

  @Test func twelveMatchesPaginateTheProgramme() throws {
    let (model, app) = try makeModel()
    app.select(app.weekend.next)
    model.reload()
    let sunday = model.details.filter { $0.match.date == app.weekend.sunday }
    #expect(sunday.count == 11)
    let programme = model.plan?.images.filter { $0.templateID == "story-programme" } ?? []
    // Saturday: one page; Sunday: 12 rows over two pages.
    #expect(programme.count == 3)
    #expect(programme.contains { $0.page == PageInfo(index: 2, total: 2) })
  }

  @Test func togglingChoicesUpdatesTheSummary() throws {
    let (model, _) = try makeModel()
    let before = model.totalImages
    model.toggleTemplate("post-prematch")
    #expect(model.totalImages < before)
    model.toggleTemplate("story-programme")
    #expect(model.totalImages == 0)
    #expect(model.disabledReason == GenerateStrings.reasonNoTemplate)
    model.toggleTemplate("story-programme")
    model.setAllMatches(false)
    #expect(model.disabledReason == GenerateStrings.reasonNoMatch)
    model.setAllMatches(true)
    // An explicitly checked postponed match renders, with a warning, and never blocks.
    #expect(model.canGenerate)
    #expect(model.planWarnings.contains { $0.kind == .matchNotScheduled })
  }

  @Test func preMatchPostTakesEveryCheckedMatch() throws {
    let (model, _) = try makeModel()
    model.setAllMatches(true)
    let selection = model.selections.first { $0.templateID == "post-prematch" }
    #expect(Set(selection?.matchIDs ?? []) == Set(model.checkedMatchIDs))
    #expect(model.details.contains { !$0.team.isFirstTeam && selection?.matchIDs.contains($0.id) == true })
  }

  @Test func changingWeekendReloadsAndResets() throws {
    let (model, app) = try makeModel()
    app.goToNextWeekend()
    model.reload()
    #expect(model.details.allSatisfy { app.weekend.contains($0.match.date) })
    #expect(model.results.isEmpty)
  }

  // MARK: Run

  @Test func fullRunFillsTheGalleryAndReportsProgress() async throws {
    let probe = Probe()
    let (model, _) = try makeModel(probe: probe)
    let total = model.totalImages
    await model.generate()
    #expect(model.results.count == total)
    #expect(model.run == .finished(produced: total, failed: 0))
    #expect(probe.updates.last?.0 == total)
    #expect(probe.updates.last?.1 == total)
    #expect(probe.finished == 1)
    #expect(model.galleryImages.count == total)
    #expect(model.results.allSatisfy { FileManager.default.fileExists(atPath: $0.record.file) })
  }

  @Test func cancellingKeepsTheImagesAlreadyMade() async throws {
    let probe = Probe()
    let (model, app) = try makeModel(probe: probe)
    let renderer = try #require(app.services.renderer as? FakeRenderService)
    let total = model.totalImages
    #expect(total > 1)
    // Images after the first wait on a gate that opens only after the cancel, so the outcome does
    // not depend on how fast the machine is.
    let (gate, openGate) = AsyncStream.makeStream(of: Void.self)
    renderer.beforeEachImage = { index in
      guard index > 1 else { return }
      for await _ in gate {}
    }
    let (firstImage, firstImageSeen) = AsyncStream.makeStream(of: Void.self)
    probe.onUpdate = { done, _ in if done == 1 { firstImageSeen.yield() } }
    model.startGenerating()
    for await _ in firstImage { break }
    model.cancel()
    openGate.finish()  // if cancellation did not reach the run, it would now go on and make more images
    await model.waitForRun()
    await renderer.waitUntilIdle()
    #expect(model.results.count == 1)
    #expect(model.results.count < total)
    #expect(model.run == .cancelled(produced: 1))
    #expect(probe.finished == 1)
    // The record of the finished image is stored; no more arrive afterwards.
    let stored = try app.services.renders.list(from: nil, to: nil)
    let newOnes = stored.filter { record in model.results.contains { $0.id == record.id } }
    #expect(newOnes.count == 1)
    #expect(model.canGenerate)
  }

  @Test func failedImagesAreReportedAndTheRunGoesOn() async throws {
    let (model, app) = try makeModel()
    let renderer = try #require(app.services.renderer as? FakeRenderService)
    renderer.failingTemplateIDs = ["post-prematch"]
    let total = model.totalImages
    await model.generate()
    #expect(!model.failures.isEmpty)
    guard case .finished(let produced, let failed) = model.run else {
      Issue.record("expected a finished run")
      return
    }
    #expect(failed == model.failures.count)
    #expect(produced + failed == total)
  }

  @Test func regenerateReplacesTheImageInPlace() async throws {
    let (model, _) = try makeModel()
    await model.generate()
    let target = try #require(model.results.first)
    let count = model.results.count
    await model.regenerate([target.id])
    #expect(model.results.first?.id != target.id)
    #expect(model.results.count == count)
  }

  @Test func recapSelectionHoldsEveryCheckedMatch() throws {
    let (model, _) = try makeModel()
    model.setAllMatches(true)
    if !model.checkedTemplateIDs.contains("story-results") { model.toggleTemplate("story-results") }
    let selection = try #require(model.selections.first { $0.templateID == "story-results" })
    #expect(Set(selection.matchIDs) == model.checkedMatchIDs)
    #expect(selection.matchIDs.count == model.details.count)
  }

  @Test func editJumpsToMatchesOnTheSameWeekend() throws {
    let (model, app) = try makeModel()
    app.open(.generate)
    let weekend = app.weekend
    model.edit()
    #expect(app.section == .matches)
    #expect(app.weekend == weekend)
  }
}
