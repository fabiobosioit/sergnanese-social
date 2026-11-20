import AppKit
import Foundation
import SSCore
import Testing

@testable import SSRender

/// Regression tests for the missing-crest bug: a large image (the club crest is a 500×500 PNG)
/// was sometimes absent from the snapshot although the page had reported itself ready.
///
/// WebKit decodes a large image asynchronously the first time a tile containing it is painted and
/// paints nothing until that decode lands; `img.complete` and `img.decode()` do not wait for it. A
/// snapshot taken in that window came back without the image (about 1 render in 4). The tests
/// render many times in a row so that a regression is very unlikely to slip through.
@MainActor
@Suite(.serialized)
struct LargeImageTests {
  static let renderer = WebRenderer()
  /// With the bug, each render missed the image with a probability of about 0.25, so all of these
  /// renders passing by chance is below 1 in 1000 per test.
  static let renders = 24
  static let green = "#00A651"

  /// A template folder with a large green square PNG at `assets/crest.png`.
  func folder(id: String, body: String) throws -> URL {
    let html = """
      <!doctype html><html><head><meta charset="utf-8"><style>
      #root { position: relative; width: 1080px; height: 1350px; background: #FFFFFF; }
      .crest { position: absolute; left: 60px; top: 80px; width: 124px; height: 124px; }
      </style></head><body><div id="root">\(body)</div></body></html>
      """
    let folder = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: id, width: 1080, height: 1350, html: html)
    try FixtureTemplates.writePNG(color: (0, 166, 81), size: 600, to: folder.appendingPathComponent("assets/crest.png"))
    return folder
  }

  /// Renders `folder` `renders` times (each time as a fresh load) and returns how many images lack
  /// the crest at its centre.
  func misses(_ folder: URL) async throws -> Int {
    let html = try String(contentsOf: folder.appendingPathComponent("template.html"), encoding: .utf8)
    var misses = 0
    for _ in 0..<Self.renders {
      let page = WebRenderer.Page(html: html, templateFolder: folder, logosFolder: nil, width: 1080, height: 1350)
      let output = try await Self.renderer.render(page)
      if try Pixels(png: output.png).hex(x: 122, y: 142) != Self.green { misses += 1 }
    }
    return misses
  }

  /// Control for `changingPageStillRenders`: a page that does not change settles.
  @Test func staticPageSettles() async throws {
    let folder = try folder(id: "static", body: "")
    let html = try String(contentsOf: folder.appendingPathComponent("template.html"), encoding: .utf8)
    let renderer = WebRenderer(timeout: .seconds(60))
    _ = try await renderer.render(
      WebRenderer.Page(html: html, templateFolder: folder, logosFolder: nil, width: 1080, height: 1350))
    #expect(renderer.lastSettle == .settled)
  }

  @Test func largeImgIsAlwaysInTheSnapshot() async throws {
    let folder = try folder(id: "large-img", body: "<img class='crest' src='assets/crest.png' alt=''>")
    #expect(try await misses(folder) == 0)
  }

  @Test func explicitAsyncDecodingIsOverridden() async throws {
    let body = """
      <img class="crest" decoding="async" src="assets/crest.png" alt="">
      <script>document.querySelector('.crest').decoding = 'async';</script>
      """
    #expect(try await misses(folder(id: "async-img", body: body)) == 0)
  }

  @Test func imgAddedByScriptIsInTheSnapshot() async throws {
    let body = """
      <script>
      var img = new Image(); img.className = 'crest'; img.alt = ''; img.src = 'assets/crest.png';
      document.getElementById('root').appendChild(img);
      window.__ready = img.decode();
      </script>
      """
    #expect(try await misses(folder(id: "script-img", body: body)) == 0)
  }

  @Test func largeCSSBackgroundIsAlwaysInTheSnapshot() async throws {
    let body = "<div class='crest' style='background: url(assets/crest.png) center / contain no-repeat'></div>"
    #expect(try await misses(folder(id: "large-bg", body: body)) == 0)
  }

  // MARK: The settle loop, without WebKit

  @Test func settleLoopStopsAtTheSnapshotLimit() {
    var loop = WebRenderer.SettleLoop(maxSnapshots: 8)
    for index in 1..<8 {
      #expect(loop.add(Data([UInt8(index)]), deadlineExpired: false) == nil)
    }
    #expect(loop.add(Data([8]), deadlineExpired: false) == .snapshotLimit)
    #expect(loop.count == 8)
  }

  @Test func settleLoopStopsAtTwoIdenticalSnapshots() {
    var loop = WebRenderer.SettleLoop(maxSnapshots: 8)
    #expect(loop.add(Data([1]), deadlineExpired: false) == nil)
    #expect(loop.add(Data([2]), deadlineExpired: false) == nil)
    #expect(loop.add(Data([2]), deadlineExpired: false) == .settled)
    #expect(loop.count == 3)
  }

  @Test func settleLoopNeverSettlesOnUnreadablePixels() {
    var loop = WebRenderer.SettleLoop(maxSnapshots: 3)
    #expect(loop.add(nil, deadlineExpired: false) == nil)
    #expect(loop.add(nil, deadlineExpired: false) == nil)
    #expect(loop.add(nil, deadlineExpired: false) == .snapshotLimit)
  }

  @Test func settleLoopStopsAtTheDeadline() {
    var loop = WebRenderer.SettleLoop(maxSnapshots: 8)
    #expect(loop.add(Data([1]), deadlineExpired: false) == nil)
    #expect(loop.add(Data([2]), deadlineExpired: true) == .deadline)
    #expect(loop.count == 2)
  }

  // MARK: A page that keeps changing

  /// A page that never stops changing still renders, without waiting for the timeout, and at the
  /// exact size.
  ///
  /// The page changes through a `MessageChannel` loop: in the hidden web view CSS animations are
  /// paused and timers are throttled, so a page animated with those settles after all. Each message
  /// writes a larger number into the box, so two snapshots usually differ and the settle loop stops
  /// at `maxSnapshots` (`.snapshotLimit`).
  ///
  /// No wall-clock bound (it failed on loaded CI runners, like 5e8876f and a16f551). The renderer
  /// reports how its settle loop stopped: at most `maxSnapshots` snapshots and an outcome other than
  /// `.deadline` prove it did not wait for the timeout. `.settled` is accepted, since WebKit does
  /// not guarantee that a hidden page runs a message between two snapshots. The cap itself is proved
  /// with pixels that always differ, without WebKit, by `settleLoopStopsAtTheSnapshotLimit`. The
  /// generous timeout keeps a slow runner from reaching the deadline first.
  @Test func changingPageStillRenders() async throws {
    let html = """
      <!doctype html><html><head><style>
      #root { position: relative; width: 400px; height: 300px; background: #FFFFFF; }
      #box { position: absolute; left: 150px; top: 100px; width: 100px; height: 100px; background: #0000FF;
        color: #FFFFFF; font: 24px sans-serif; }
      </style></head><body><div id="root"><div id="box"></div></div>
      <script>
      var n = 0, box = document.getElementById('box'), channel = new MessageChannel();
      channel.port1.onmessage = function () { n += 1; box.textContent = n; channel.port2.postMessage(0); };
      channel.port2.postMessage(0);
      </script></body></html>
      """
    let folder = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: "changing", width: 400, height: 300, html: html)
    let page = WebRenderer.Page(html: html, templateFolder: folder, logosFolder: nil, width: 400, height: 300)
    let renderer = WebRenderer(timeout: .seconds(60))
    let output = try await renderer.render(page)
    let outcome = try #require(renderer.lastSettle)
    #expect(outcome != .deadline)
    #expect(renderer.lastSnapshotCount <= WebRenderer.maxSnapshots)
    #expect(ExactImage.pixelSize(of: output.png)?.width == 400)
    #expect(ExactImage.pixelSize(of: output.png)?.height == 300)
    #expect(try Pixels(png: output.png).hex(x: 10, y: 10) == "#FFFFFF")
  }
}
