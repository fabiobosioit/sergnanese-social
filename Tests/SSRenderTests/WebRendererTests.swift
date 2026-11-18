import AppKit
import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSRender

/// Renders with the real off-screen `WKWebView`. Serialized: the tests share one renderer, Dark Mode
/// is switched on the shared application, and focus checks only make sense when nothing else renders.
@MainActor
@Suite(.serialized)
struct WebRendererTests {
  static let renderer = WebRenderer()

  /// The page of a template folder. The two fixture templates are filled with the standard fixture
  /// contexts through Mustache and get the fixture logos; the variants are used as written.
  func page(_ folder: URL, width: Int = 1080, height: Int = 1350, logos: URL? = nil) throws -> WebRenderer.Page {
    let context: TemplateContext?
    switch folder.lastPathComponent {
    case "test-single": context = .single(try Fixtures.singleContext())
    case "test-list": context = .list(try Fixtures.listContext())
    default: context = nil
    }
    var html = try String(contentsOf: folder.appendingPathComponent("template.html"), encoding: .utf8)
    var logosFolder = logos
    if let context {
      let manifest = TemplateManifest(
        id: folder.lastPathComponent, name: "t", version: "1.0.0", format: .post, width: width, height: height,
        kind: .single, purpose: .other)
      html = try TemplateHTML().render(
        InstalledTemplate(manifest: manifest, folder: folder, isBuiltin: false), context: context)
      logosFolder = try logos ?? Fixtures.logosFolder()
    }
    return WebRenderer.Page(html: html, templateFolder: folder, logosFolder: logosFolder, width: width, height: height)
  }

  @Test func rendersExactSizeAndAccentColour() async throws {
    let folders = try FixtureTemplates.install(in: try makeTemporaryFolder())
    let output = try await Self.renderer.render(page(folders.single))
    let size = try #require(ExactImage.pixelSize(of: output.png))
    #expect(size.width == 1080 && size.height == 1350)
    let pixels = try Pixels(png: output.png)
    #expect(pixels.centreHex == "#CF3326")
    // The club crest from assets/ was served by the scheme handler (blue square at bottom-left).
    #expect(pixels.hex(x: 120, y: 1230) == "#0000FF")
    // The opponent logo came from the logos folder through `_logos/` (no initials circle, which is white).
    #expect(pixels.hex(x: 960, y: 1180) != "#CF3326" && pixels.hex(x: 960, y: 1180) != "#FFFFFF")
    #expect(output.blockedURLs.isEmpty)
  }

  @Test func otherSizesAreExactToo() async throws {
    let folders = try FixtureTemplates.install(in: try makeTemporaryFolder())
    let list = try await Self.renderer.render(page(folders.list, width: 1080, height: 1920))
    #expect(ExactImage.pixelSize(of: list.png)?.width == 1080)
    #expect(ExactImage.pixelSize(of: list.png)?.height == 1920)
    let odd = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: "odd", width: 333, height: 201,
      html: "<!doctype html><div style='width:333px;height:201px;background:#123456'></div>")
    let small = try await Self.renderer.render(page(odd, width: 333, height: 201))
    #expect(ExactImage.pixelSize(of: small.png)?.width == 333)
    #expect(ExactImage.pixelSize(of: small.png)?.height == 201)
    #expect(try Pixels(png: small.png).centreHex == "#123456")
  }

  @Test func darkModeDoesNotChangeTheImage() async throws {
    let folders = try FixtureTemplates.install(in: try makeTemporaryFolder())
    let light = try await Self.renderer.render(page(folders.single))
    let app = NSApplication.shared
    let previous = app.appearance
    app.appearance = NSAppearance(named: .darkAqua)
    defer { app.appearance = previous }
    #expect(app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    // A new web view, created while the app is dark, must still render light.
    let fresh = WebRenderer()
    let dark = try await fresh.render(page(folders.single))
    let reused = try await Self.renderer.render(page(folders.single))
    #expect(try Pixels(png: dark.png).centreHex == "#CF3326")
    #expect(try Pixels(png: dark.png).bytes == Pixels(png: light.png).bytes)
    #expect(try Pixels(png: reused.png).bytes == Pixels(png: light.png).bytes)
  }

  @Test func sameContextTwiceGivesIdenticalPixels() async throws {
    let folders = try FixtureTemplates.install(in: try makeTemporaryFolder())
    let first = try await Self.renderer.render(page(folders.single))
    let second = try await Self.renderer.render(page(folders.single))
    #expect(try Pixels(png: first.png).bytes == Pixels(png: second.png).bytes)
  }

  @Test func remoteRequestsAreBlockedAndReported() async throws {
    let html = """
      <!doctype html><html><head>
      <link rel="stylesheet" href="https://fonts.example.invalid/css?family=Barlow">
      <style>#root{width:400px;height:300px;background:#00FF00}
      #bg{width:100px;height:100px;background-image:url(https://images.example.invalid/bg.png)}</style>
      </head><body><div id="root"><img src="https://images.example.invalid/logo.png" alt="">
      <div id="bg"></div></div>
      <script>fetch('https://api.example.invalid/data').catch(function () {});
      try { new WebSocket('wss://socket.example.invalid/'); } catch (e) {}</script>
      </body></html>
      """
    let folder = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: "remote", width: 400, height: 300, html: html)
    let output = try await Self.renderer.render(page(folder, width: 400, height: 300))
    let blocked = Set(output.blockedURLs)
    #expect(blocked.contains("https://fonts.example.invalid/css?family=Barlow"))
    #expect(blocked.contains("https://images.example.invalid/logo.png"))
    #expect(blocked.contains("https://api.example.invalid/data"))
    #expect(try Pixels(png: output.png).hex(x: 300, y: 200) == "#00FF00")

    let warnings = TemplateRenderService.blockedWarnings(output.blockedURLs, templateID: "remote")
    #expect(warnings.count == output.blockedURLs.count)
    #expect(warnings.allSatisfy { $0.kind == .blockedRequest && $0.templateID == "remote" })
  }

  @Test func navigationAwayIsRefused() async throws {
    let html = """
      <!doctype html><div style="width:200px;height:200px;background:#0000FF"></div>
      <script>window.__ready = new Promise(function (resolve) {
        window.addEventListener('load', function () {
          location.href = 'https://elsewhere.example.invalid/';
          setTimeout(resolve, 200);
        });
      });</script>
      """
    let folder = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: "nav", width: 200, height: 200, html: html)
    let output = try await Self.renderer.render(page(folder, width: 200, height: 200))
    #expect(output.blockedURLs.contains("https://elsewhere.example.invalid/"))
    #expect(try Pixels(png: output.png).centreHex == "#0000FF")
  }

  @Test func filesOutsideTheTemplateFolderAreNotServed() async throws {
    let parent = try makeTemporaryFolder()
    // Red files next to and above the template folder, and a logos folder elsewhere.
    try FixtureTemplates.writePNG(color: (255, 0, 0), size: 16, to: parent.appendingPathComponent("secret.png"))
    try FixtureTemplates.writePNG(color: (255, 0, 0), size: 16, to: parent.appendingPathComponent("evil/secret.png"))
    let logos = parent.appendingPathComponent("logos", isDirectory: true)
    try FixtureTemplates.writePNG(color: (0, 0, 255), size: 16, to: logos.appendingPathComponent("ok.png"))
    let html = """
      <!doctype html><html><head><style>
      #root{position:relative;width:400px;height:100px;background:#FFFFFF}
      #root div{position:absolute;top:0;width:100px;height:100px;background-size:cover}
      </style></head><body><div id="root">
      <div style="left:0;background-image:url(../secret.png)"></div>
      <div style="left:100px;background-image:url(%2e%2e/evil/secret.png)"></div>
      <div style="left:200px;background-image:url(_logos/../secret.png)"></div>
      <div style="left:300px;background-image:url(_logos/ok.png)"></div>
      </div>
      <script>window.__ready = fetch('../secret.png').then(function (r) { window.status = String(r.status); },
        function () {});</script>
      </body></html>
      """
    let folder = try FixtureTemplates.custom(
      in: parent.appendingPathComponent("templates"), id: "escape", width: 400, height: 100, html: html)
    let output = try await Self.renderer.render(page(folder, width: 400, height: 100, logos: logos))
    let pixels = try Pixels(png: output.png)
    #expect(pixels.hex(x: 50, y: 50) == "#FFFFFF")
    #expect(pixels.hex(x: 150, y: 50) == "#FFFFFF")
    #expect(pixels.hex(x: 250, y: 50) == "#FFFFFF")
    #expect(pixels.hex(x: 350, y: 50) == "#0000FF")  // a real logo is served
  }

  @Test func readyPromiseIsAwaited() async throws {
    let html = """
      <!doctype html><div id="root" style="width:200px;height:200px;background:#FF0000"></div>
      <script>window.__ready = new Promise(function (resolve) {
        setTimeout(function () { document.getElementById('root').style.background = '#00FF00'; resolve(); }, 300);
      });</script>
      """
    let folder = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: "ready", width: 200, height: 200, html: html)
    let output = try await Self.renderer.render(page(folder, width: 200, height: 200))
    #expect(try Pixels(png: output.png).centreHex == "#00FF00")
  }

  @Test func neverReadyFailsWithAClearTimeout() async throws {
    let html = """
      <!doctype html><div style="width:200px;height:200px"></div>
      <script>window.__ready = new Promise(function () {});</script>
      """
    let folder = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: "stuck", width: 200, height: 200, html: html)
    let renderer = WebRenderer(timeout: .seconds(1))
    let start = ContinuousClock.now
    await #expect(
      throws: AppError.render(message: RenderStrings.timeout(seconds: 1, pending: [RenderStrings.pendingReady]))
    ) {
      _ = try await renderer.render(page(folder, width: 200, height: 200))
    }
    #expect(ContinuousClock.now - start < .seconds(5))
    // The renderer recovers with a new web view.
    let ok = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: "ok", width: 200, height: 200,
      html: "<!doctype html><div style='width:200px;height:200px;background:#00FF00'></div>")
    #expect(try Pixels(png: await renderer.render(page(ok, width: 200, height: 200)).png).centreHex == "#00FF00")
  }

  /// The `check.sh` flake: `GoldenImageTests` compared bitmaps synchronously on the main actor for
  /// seconds while `WorkflowTests` rendered in parallel. The render could not progress meanwhile (the
  /// scheme handler, the navigation delegate and every WebKit completion run on the main actor), and
  /// a wall-clock deadline passed while it was blocked. Before `RenderDeadline` this failed every
  /// time with the timeout. In this serialized suite so that it never overlaps the timeout test.
  @Test func blockedMainActorDoesNotFailARender() async throws {
    // The page is ready only after a file it asks for 150 ms after loading: the scheme handler can
    // answer that request only once the main actor is free again, so the render is surely in flight
    // during the whole block.
    let html = """
      <!doctype html><div id="root" style="width:300px;height:200px;background:#FF0000"></div>
      <script>window.__ready = new Promise(function (resolve) { setTimeout(resolve, 150); })
        .then(function () { return fetch('colour.txt'); }).then(function (r) { return r.text(); })
        .then(function (colour) { document.getElementById('root').style.background = colour.trim(); });</script>
      """
    let folder = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: "blocked-main", width: 300, height: 200, html: html)
    try Data("#00FF00".utf8).write(to: folder.appendingPathComponent("colour.txt"))
    let renderer = WebRenderer(timeout: .seconds(1))
    let page = WebRenderer.Page(html: html, templateFolder: folder, logosFolder: nil, width: 300, height: 200)
    _ = try await renderer.render(page)  // the rule list and the web view exist: the next render starts at once
    let render = Task { try await renderer.render(page) }
    try await Task.sleep(for: .milliseconds(50))
    blockMainActor(for: .milliseconds(1600))
    let output = try await render.value
    #expect(ExactImage.pixelSize(of: output.png)?.width == 300)
    #expect(ExactImage.pixelSize(of: output.png)?.height == 200)
    #expect(try Pixels(png: output.png).centreHex == "#00FF00")
  }

  @Test func wrongRootSizeIsRefused() async throws {
    let folder = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: "small-root", width: 300, height: 300,
      html: "<!doctype html><div style='width:200px;height:300px'></div>")
    await #expect(throws: AppError.self) {
      _ = try await Self.renderer.render(page(folder, width: 300, height: 300))
    }
    let two = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: "two-roots", width: 300, height: 300,
      html: "<!doctype html><div style='width:300px;height:300px'></div><p>x</p>")
    await #expect(throws: AppError.self) {
      _ = try await Self.renderer.render(page(two, width: 300, height: 300))
    }
  }

  @Test func queuedRendersRunOneAtATime() async throws {
    let folders = try FixtureTemplates.install(in: try makeTemporaryFolder())
    let first = try page(folders.single)
    let second = try page(folders.list, width: 1080, height: 1920)
    async let one = Self.renderer.render(first)
    async let two = Self.renderer.render(second)
    let (a, b) = try await (one, two)
    #expect(ExactImage.pixelSize(of: a.png)?.height == 1350)
    #expect(ExactImage.pixelSize(of: b.png)?.height == 1920)
  }

  @Test func noWindowAppearsAndFocusDoesNotChange() async throws {
    let before = FocusSnapshot.take()
    let folders = try FixtureTemplates.install(in: try makeTemporaryFolder())
    for _ in 0..<3 { _ = try await WebRenderer().render(page(folders.single)) }
    let after = FocusSnapshot.take()
    #expect(after == before)
    #expect(after.visibleWindows == 0)
    #expect(!after.isActive)
    #expect(NSApplication.shared.keyWindow == nil)
    #expect(NSApplication.shared.activationPolicy() != .regular)
  }
}
