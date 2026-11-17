import CoreGraphics
import Foundation
import ImageIO
import SSCoreFakes
import Testing

@testable import SSCore

/// `true` when `body` throws `AppError.conflict`.
func isConflict(_ body: () throws -> Void) -> Bool {
  do {
    try body()
    return false
  } catch AppError.conflict {
    return true
  } catch {
    return false
  }
}

@MainActor
@Suite struct FakeServicesTests {
  let today = DayDate.today()
  let services: AppServices
  var thisWeekend: Weekend { weekend(containing: today) }

  init() {
    services = AppServices.fake(today: DayDate.today())
  }

  @Test func fakeIsFilledAroundTheCurrentWeekend() throws {
    let current = try services.matches.list(from: thisWeekend.saturday, to: thisWeekend.sunday, teamID: nil)
    #expect(current.count == 10)
    #expect(current == current.sorted(by: MatchDetail.scheduleOrder))
    #expect(try services.teams.list().first?.isFirstTeam == true)
    #expect(try services.templates.list().count == 4)
    #expect(try services.settings.load().socialHandle == "@sergnanese.demo")
    #expect(services.paths.dataFolder.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    #expect(try services.demoData.hasDemoData())
  }

  @Test func logosAreAvailable() throws {
    let withLogo = try #require(try services.opponents.list().first { $0.logoFile != nil })
    let file = try #require(withLogo.logoFile)
    #expect(FileManager.default.fileExists(atPath: services.logos.url(for: file).path))
  }

  @Test func archiveHasExistingAndMissingFiles() throws {
    let records = try services.renders.list(from: nil, to: nil)
    #expect(records.count == 4)
    #expect(records == records.sorted { $0.createdAt > $1.createdAt })
    let missing = records.filter { !FileManager.default.fileExists(atPath: $0.file) }
    #expect(missing.count == 1)
    let previous = try services.renders.list(from: thisWeekend.previous.saturday, to: thisWeekend.previous.sunday)
    #expect(previous.count == 4)
  }

  @Test func teamRules() throws {
    let created = try services.teams.create(TeamDraft(name: "Under 12", shortLabel: "U12", isFirstTeam: true))
    let teams = try services.teams.list()
    #expect(teams.last?.id == created.id)
    #expect(teams.filter(\.isFirstTeam).map(\.id) == [created.id])
    let reversed = teams.map(\.id).reversed()
    try services.teams.reorder(ids: Array(reversed))
    #expect(try services.teams.list().map(\.id) == Array(reversed))
    #expect(throws: AppError.self) { try services.teams.reorder(ids: [created.id]) }
    try services.teams.delete(id: created.id)
    let withMatches = try #require(try services.teams.list().first { $0.isActive && $0.name == "Juniores" })
    #expect(isConflict { try services.teams.delete(id: withMatches.id) })
    #expect(throws: AppError.notFound) { try services.teams.get(id: "missing") }
    #expect(throws: AppError.self) { try services.teams.create(TeamDraft()) }
  }

  @Test func opponentRules() throws {
    #expect(try services.opponents.search("citta").map(\.name) == ["G.S. Sant'Ilario Città"])
    #expect(try services.opponents.search("S. Gerolamo").count == 1)  // alias
    #expect(try services.opponents.search("").count == (try services.opponents.list().count))
    let counts = try services.opponents.matchCounts()
    #expect(counts.values.reduce(0, +) == (try services.matches.count(source: nil)))
    let new = try services.opponents.create(OpponentDraft(name: "Nuova Società", shortName: " "))
    #expect(new.shortName == nil)
    try services.opponents.delete(id: new.id)
    let busy = try #require(try services.opponents.list().first { (counts[$0.id] ?? 0) > 0 })
    #expect(isConflict { try services.opponents.delete(id: busy.id) })
  }

  @Test func matchRules() throws {
    let detail = try #require(
      try services.matches.list(from: thisWeekend.saturday, to: thisWeekend.sunday, teamID: nil).first)
    var draft = MatchDraft(detail.match)
    draft.time = try ClockTime("20:45")
    let updated = try services.matches.update(id: detail.id, with: draft)
    #expect(updated.time?.value == "20:45" && updated.createdAt == detail.match.createdAt)

    let copy = try services.matches.duplicate(id: detail.id, to: detail.match.date.adding(days: 7))
    #expect(copy.id != detail.id && copy.status == .scheduled && copy.score == nil && !copy.isLocked)
    #expect(copy.source == .manual && copy.teamID == detail.match.teamID)

    let teamOnly = try services.matches.list(from: thisWeekend.saturday, to: thisWeekend.sunday, teamID: detail.team.id)
    #expect(teamOnly.allSatisfy { $0.team.id == detail.team.id })

    var orphan = draft
    orphan.opponentID = "nobody"
    #expect(throws: AppError.validation(field: .opponent, message: "L'avversario scelto non esiste.")) {
      try services.matches.create(orphan)
    }
    try services.matches.delete(id: copy.id)
    #expect(throws: AppError.notFound) { try services.matches.get(id: copy.id) }
  }

  @Test func upsertSkipsLockedMatches() throws {
    let all = try services.matches.list(from: thisWeekend.saturday, to: thisWeekend.sunday, teamID: nil)
    let locked = try #require(all.first { $0.match.isLocked })
    let open = try #require(all.first { !$0.match.isLocked })
    var lockedDraft = MatchDraft(locked.match)
    lockedDraft.venue = "Cambiato"
    lockedDraft.source = .csv
    var openDraft = MatchDraft(open.match)
    openDraft.venue = "Cambiato"
    openDraft.source = .csv
    var newDraft = MatchDraft(open.match)
    newDraft.date = thisWeekend.next.next.saturday
    newDraft.source = .csv
    let summary = try services.matches.upsertFromImport([lockedDraft, openDraft, newDraft])
    #expect(summary == ImportSummary(inserted: 1, updated: 1, skippedLocked: 1))
    #expect(try services.matches.get(id: locked.id).match.venue != "Cambiato")
    #expect(try services.matches.get(id: open.id).match.venue == "Cambiato")
  }

  @Test func settingsRoundTripAndValidation() throws {
    var settings = try services.settings.load()
    settings.accentColor = "112233"
    try services.settings.save(settings)
    #expect(try services.settings.load().accentColor == "#112233")
    settings.season = "nope"
    #expect(throws: AppError.self) { try services.settings.save(settings) }
  }

  @Test func templateStoreRules() throws {
    #expect(isConflict { try services.templates.remove(id: "post-prematch") })
    let folder = services.paths.dataFolder.appendingPathComponent("import-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: folder.appendingPathComponent("manifest.json"))
    guard case .invalid(let problems) = try services.templates.install(from: folder, replace: false) else {
      Issue.record("expected problems")
      return
    }
    #expect(!problems.isEmpty)

    let manifest = """
      {"id":"post-prematch","name":"Mio post","version":"2.0.0","format":"post","width":1080,"height":1350,
       "kind":"single","purpose":"prematch"}
      """
    try Data(manifest.utf8).write(to: folder.appendingPathComponent("manifest.json"))
    try Data("<div></div>".utf8).write(to: folder.appendingPathComponent("template.html"))
    guard case .alreadyExists = try services.templates.install(from: folder, replace: false) else {
      Issue.record("expected a clash")
      return
    }
    guard case .installed(let installed) = try services.templates.install(from: folder, replace: true) else {
      Issue.record("expected an install")
      return
    }
    #expect(!installed.isBuiltin && installed.manifest.name == "Mio post")
    let restored = try services.templates.restoreBuiltin(id: "post-prematch")
    #expect(restored.isBuiltin && restored.manifest.version == "1.0.0")
    #expect(throws: AppError.notFound) { try services.templates.restoreBuiltin(id: "custom") }
  }

  @Test func logoStore() async throws {
    let png = try Data(contentsOf: try Fixtures.logosFolder().appendingPathComponent("fixture-lucia.png"))
    let first = try await services.logos.importLogo(data: png, replacing: nil)
    let second = try await services.logos.importLogo(data: png, replacing: first)
    #expect(first != second)
    #expect(!FileManager.default.fileExists(atPath: services.logos.url(for: first).path))
    #expect(FileManager.default.fileExists(atPath: services.logos.url(for: second).path))
    await #expect(throws: AppError.self) {
      try await services.logos.importLogo(data: Data("hello".utf8), replacing: nil)
    }
    try services.logos.remove(fileName: second)
    try services.logos.remove(fileName: second)  // removing twice is fine
  }

  @Test func demoDataLoadsTwiceAndRemoves() async throws {
    let teamCount = try services.teams.list().count
    let opponentCount = try services.opponents.list().count
    let summary = try await services.demoData.load(today: today)
    _ = try await services.demoData.load(today: today)
    #expect(try services.teams.list().count == teamCount)
    #expect(try services.opponents.list().count == opponentCount)
    #expect(try services.matches.count(source: .seed) == summary.matches)
    try services.demoData.remove()
    #expect(try !services.demoData.hasDemoData())
    // The fixture's one manual match survives, and so do its team and opponent.
    let remaining = try services.matches.list(
      from: thisWeekend.previous.saturday, to: thisWeekend.next.sunday, teamID: nil)
    #expect(remaining.map(\.match.source) == [.manual])
    #expect(try services.opponents.list().map(\.id) == remaining.map(\.opponent.id))
    #expect(try services.teams.list().map(\.id) == remaining.map(\.team.id))
  }
}

@MainActor
@Suite struct FakeRenderServiceTests {
  let today = DayDate.today()
  var thisWeekend: Weekend { weekend(containing: today) }

  func makeServices() throws -> AppServices {
    try AppServices.fake(dataSet: Fixtures.dataSet().shifted(toWeekendOf: today), renderDelay: .milliseconds(5))
  }

  @Test func defaultPlan() throws {
    let services = try makeServices()
    let plan = try services.renderer.plan(RenderRequest(weekend: thisWeekend))
    #expect(plan.selections.map(\.templateID).sorted() == ["post-prematch", "story-programme"])
    #expect(plan.skippedMatchIDs.count == 1)  // the postponed match
    let programme = plan.images.filter { $0.templateID == "story-programme" }
    #expect(programme.count == 2)  // one set per day, 4 + 5 playable matches
    let post = plan.images.filter { $0.templateID == "post-prematch" }
    #expect(post.count == 1)
    #expect(post.first?.fileName.hasPrefix("\(thisWeekend.sunday.value)_post-prematch_prima-squadra_vs_") == true)
    #expect(plan.warnings.contains { $0.kind == .missingLogo })
    #expect(plan.warnings.contains { $0.kind == .nameTruncated })
    #expect(plan.warnings.contains { $0.kind == .missingTime })
  }

  @Test func twoProgrammePagesNextWeekend() throws {
    let services = try makeServices()
    let plan = try services.renderer.plan(RenderRequest(weekend: thisWeekend.next))
    let sunday = plan.images.filter { $0.templateID == "story-programme" && $0.date == thisWeekend.next.sunday }
    #expect(sunday.map { $0.page?.label } == ["1/2", "2/2"])
    #expect(sunday.first?.matchIDs.count == 10)
  }

  @Test func explicitSelectionAndUnknownIDs() throws {
    let services = try makeServices()
    let all = try services.matches.list(from: thisWeekend.saturday, to: thisWeekend.sunday, teamID: nil)
    let postponed = try #require(all.first { $0.match.status == .postponed })
    let plan = try services.renderer.plan(
      RenderRequest(
        weekend: thisWeekend, selections: [TemplateSelection(templateID: "story-fulltime", matchIDs: [postponed.id])]))
    #expect(plan.images.count == 1 && plan.skippedMatchIDs.isEmpty)
    #expect(plan.warnings.contains { $0.kind == .matchNotScheduled })
    #expect(throws: AppError.notFound) {
      try services.renderer.plan(
        RenderRequest(weekend: thisWeekend, selections: [TemplateSelection(templateID: "nope", matchIDs: [])]))
    }
  }

  @Test func renderWritesExactSizePNGsAndRecords() async throws {
    let services = try makeServices()
    var events: [RenderEvent] = []
    for try await event in services.renderer.render(RenderRequest(weekend: thisWeekend)) { events.append(event) }
    guard case .started(let total) = events.first, case .finished(let summary) = events.last else {
      Issue.record("unexpected events \(events)")
      return
    }
    #expect(total == 3 && summary.produced == 3 && summary.failed == 0)
    let done = events.compactMap { event -> RenderedImage? in
      if case .imageDone(let image, _, _) = event { return image } else { return nil }
    }
    #expect(done.count == 3)
    for image in done {
      let source = try #require(CGImageSourceCreateWithURL(image.record.fileURL as CFURL, nil))
      let cgImage = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
      #expect(cgImage.width == image.record.width && cgImage.height == image.record.height)
    }
    let stored = try services.renders.list(from: thisWeekend.saturday, to: thisWeekend.sunday)
    #expect(stored.count == 3)

    // A second run never overwrites.
    for try await _ in services.renderer.render(RenderRequest(weekend: thisWeekend)) {}
    let files = try services.renders.list(from: thisWeekend.saturday, to: thisWeekend.sunday).map(\.file)
    #expect(Set(files).count == 6)
  }

  @Test func cancellationStopsAndKeepsImages() async throws {
    let services = try makeServices()
    let renderer = try #require(services.renderer as? FakeRenderService)
    renderer.delay = .milliseconds(200)
    let request = RenderRequest(weekend: thisWeekend)
    let (firstImage, firstImageSeen) = AsyncStream.makeStream(of: Void.self)
    let consumer = Task { @MainActor in
      var seen = 0
      for try await event in services.renderer.render(request) {
        if case .imageDone = event {
          seen += 1
          firstImageSeen.yield()
        }
      }
      return seen
    }
    for await _ in firstImage { break }
    consumer.cancel()  // what "Annulla" does
    let seen = try await consumer.value
    try await Task.sleep(for: .milliseconds(500))
    let stored = try services.renders.list(from: thisWeekend.saturday, to: thisWeekend.sunday).count
    #expect(seen == 1)
    #expect(stored == 1)
  }

  @Test func failingTemplateDoesNotStopTheRun() async throws {
    let services = try makeServices()
    let renderer = try #require(services.renderer as? FakeRenderService)
    renderer.failingTemplateIDs = ["post-prematch"]
    var failed = 0
    var summary: RenderSummary?
    for try await event in services.renderer.render(RenderRequest(weekend: thisWeekend)) {
      if case .imageFailed = event { failed += 1 }
      if case .finished(let value) = event { summary = value }
    }
    #expect(failed == 1 && summary?.produced == 2 && summary?.failed == 1)
  }

  @Test func previewWritesATemporaryPNG() async throws {
    let services = try makeServices()
    let url = try await services.renderer.preview(templateID: "story-programme", matchIDs: [])
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 1080 && image.height == 1920)
    await #expect(throws: AppError.notFound) { try await services.renderer.preview(templateID: "nope", matchIDs: []) }
  }

  @Test func emptyDataSet() throws {
    let services = try AppServices.fake(dataSet: .empty(today: today))
    #expect(try services.matches.count(source: nil) == 0)
    #expect(try services.settings.load() == .defaults)
    #expect(try services.renderer.plan(RenderRequest(weekend: thisWeekend)).images.isEmpty)
  }
}
