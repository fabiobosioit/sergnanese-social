import Foundation
import SSCore
import SSCoreFakes
import SSTemplates
import Testing

@testable import SSRender

/// End to end: fixture templates installed in a `FileTemplateStore`, fake repositories, real WebKit.
@MainActor
@Suite(.serialized)
struct RenderServiceTests {
  struct Setup {
    let paths: AppPaths
    let database: FakeDatabase
    let service: TemplateRenderService
  }

  func setup(matches: [Match]) throws -> Setup {
    let root = try makeTemporaryFolder("RenderServiceTests")
    let paths = AppPaths(
      dataFolder: root.appendingPathComponent("data", isDirectory: true),
      resources: try #require(AppPaths.resolveResources()),
      defaultOutputFolder: root.appendingPathComponent("output", isDirectory: true))
    try paths.createFolders()
    let store = FileTemplateStore(paths: paths)
    let folders = try FixtureTemplates.install(in: root.appendingPathComponent("sources"))
    for folder in [folders.single, folders.list] {
      guard case .installed = try store.install(from: folder, replace: false) else {
        throw AppError.render(message: "fixture template not installed")
      }
    }
    try FileManager.default.copyItem(
      at: try Fixtures.logosFolder().appendingPathComponent("fixture-gerolamo.png"),
      to: paths.logos.appendingPathComponent("fixture-gerolamo.png"))
    let database = TestData.database(matches: matches)
    let service = TemplateRenderService(
      templates: store, matches: FakeMatchRepository(database: database),
      renders: FakeRenderRepository(database: database), settings: FakeSettingsRepository(database: database),
      paths: paths, renderer: WebRendererTests.renderer)
    return Setup(paths: paths, database: database, service: service)
  }

  func collect(_ stream: AsyncThrowingStream<RenderEvent, any Error>) async throws -> [RenderEvent] {
    var events: [RenderEvent] = []
    for try await event in stream { events.append(event) }
    return events
  }

  @Test func defaultRenderWritesFilesAndRecords() async throws {
    let matches = [
      TestData.match("first"), TestData.match("junior", team: TestData.juniors, time: "10:00"),
      TestData.match("off", team: TestData.juniors, status: .cancelled),
    ]
    let setup = try setup(matches: matches)
    let events = try await collect(setup.service.render(RenderRequest(from: TestData.saturday, to: TestData.sunday)))

    #expect(events.first == .started(total: 2))
    let done = events.compactMap { event -> RenderedImage? in
      if case .imageDone(let image, _, _) = event { return image }
      return nil
    }
    #expect(done.count == 2)
    guard case .finished(let summary) = events.last else {
      Issue.record("no finished event")
      return
    }
    #expect(summary.produced == 2 && summary.failed == 0)

    let records = try FakeRenderRepository(database: setup.database).list(from: nil, to: nil)
    #expect(records.count == 2)
    let names = Set(done.map { URL(fileURLWithPath: $0.record.file).lastPathComponent })
    #expect(
      names == [
        "2026-11-22_test-list_1of1.png",
        "2026-11-22_test-single_prima-squadra_vs_san-gerolamo.png",
      ])
    for image in done {
      let data = try Data(contentsOf: image.record.fileURL)
      let size = try #require(ExactImage.pixelSize(of: data))
      #expect(size.width == image.record.width && size.height == image.record.height)
      #expect(image.record.fileURL.deletingLastPathComponent().lastPathComponent == "2026-11-22")
      #expect(!image.record.matchIDs.contains("off"))
    }
    let single = try #require(done.first { $0.record.templateID == "test-single" })
    let pixels = try Pixels(png: Data(contentsOf: single.record.fileURL))
    #expect(pixels.centreHex == "#CF3326")
    #expect(pixels.hex(x: 960, y: 1180) != "#CF3326")  // the opponent logo from _logos/ is drawn there
  }

  @Test func neverOverwritesAndPaginates() async throws {
    let matches = TestData.manyMatches(23)
    let setup = try setup(matches: matches)
    let request = RenderRequest(
      from: TestData.saturday, to: TestData.sunday,
      selections: [TemplateSelection(templateID: "test-list", matchIDs: matches.map(\.id))])
    _ = try await collect(setup.service.render(request))
    let events = try await collect(setup.service.render(request))
    let files = events.compactMap { event -> String? in
      if case .imageDone(let image, _, _) = event { return URL(fileURLWithPath: image.record.file).lastPathComponent }
      return nil
    }
    #expect(
      files == [
        "2026-11-22_test-list_1of3-2.png", "2026-11-22_test-list_2of3-2.png", "2026-11-22_test-list_3of3-2.png",
      ])
    let folder = setup.paths.defaultOutputFolder.appendingPathComponent("2026-11-22")
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 6)
  }

  @Test func failingImageDoesNotStopTheRun() async throws {
    let setup = try setup(matches: [TestData.match("a"), TestData.match("b", time: "18:00")])
    // Break the single template's root size after installing it.
    let template = try FileTemplateStore(paths: setup.paths).get(id: "test-single")
    let html = template.folder.appendingPathComponent("template.html")
    let source = try String(contentsOf: html, encoding: .utf8)
    try Data(source.replacingOccurrences(of: "height: 1350px", with: "height: 1000px").utf8).write(to: html)
    let request = RenderRequest(
      from: TestData.saturday, to: TestData.sunday,
      selections: [
        TemplateSelection(templateID: "test-single", matchIDs: ["a"]),
        TemplateSelection(templateID: "test-list", matchIDs: ["a", "b"]),
      ])
    let events = try await collect(setup.service.render(request))
    #expect(events.contains { if case .imageFailed(_, _, 1, 2) = $0 { return true } else { return false } })
    guard case .finished(let summary) = events.last else {
      Issue.record("no finished event")
      return
    }
    #expect(summary.produced == 1 && summary.failed == 1)
  }

  @Test func cancellingStopsAfterTheCurrentImage() async throws {
    let matches = TestData.manyMatches(5).map { match in
      var single = match
      single.teamID = TestData.firstTeam.id
      return single
    }
    let setup = try setup(matches: matches)
    let request = RenderRequest(
      from: TestData.saturday, to: TestData.sunday,
      selections: [TemplateSelection(templateID: "test-single", matchIDs: matches.map(\.id))])
    var events: [RenderEvent] = []
    for try await event in setup.service.render(request) {
      events.append(event)
      if case .imageDone = event { break }  // ends the stream: cancels the task
    }
    try await Task.sleep(for: .seconds(1))
    let records = try FakeRenderRepository(database: setup.database).list(from: nil, to: nil)
    #expect(records.count >= 1 && records.count < 5)
  }

  @Test func unwritableOutputFolderFailsTheWholeRun() async throws {
    let setup = try setup(matches: [TestData.match("a")])
    var settings = try FakeSettingsRepository(database: setup.database).load()
    let blocker = setup.paths.dataFolder.appendingPathComponent("file-not-folder")
    try Data("x".utf8).write(to: blocker)
    settings.outputFolder = blocker.appendingPathComponent("sub").path
    try FakeSettingsRepository(database: setup.database).save(settings)
    await #expect(throws: AppError.self) {
      _ = try await collect(setup.service.render(RenderRequest(from: TestData.saturday, to: TestData.sunday)))
    }
  }

  @Test func previewWithFixtureAndWithMatches() async throws {
    let setup = try setup(matches: [TestData.match("a"), TestData.match("b", time: "16:00")])
    let fixturePreview = try await setup.service.preview(templateID: "test-single", matchIDs: [])
    let data = try Data(contentsOf: fixturePreview)
    #expect(ExactImage.pixelSize(of: data)?.width == 1080)
    #expect(try Pixels(png: data).centreHex == "#CF3326")

    let listPreview = try await setup.service.preview(templateID: "test-list", matchIDs: ["a", "b"])
    #expect(ExactImage.pixelSize(of: try Data(contentsOf: listPreview))?.height == 1920)
    await #expect(throws: AppError.notFound) {
      _ = try await setup.service.preview(templateID: "missing", matchIDs: [])
    }
  }
}
