import Foundation
import SSCore
import Testing

@testable import SSRender

/// Regression tests for the "template not ready after 10 seconds" flake: renders that failed with the
/// timeout although the page was fine, because the time limit also counted time in which the
/// renderer could not run at all (the main actor blocked by other work, or the Mac asleep).
@MainActor
@Suite(.serialized)
struct RenderDeadlineTests {
  /// Waits until `deadline` expires, up to `limit`; returns how long it took.
  func waitForExpiry(_ deadline: RenderDeadline, limit: Duration) async -> Duration? {
    let start = ContinuousClock.now
    while ContinuousClock.now - start < limit {
      if deadline.isExpired { return ContinuousClock.now - start }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return deadline.isExpired ? ContinuousClock.now - start : nil
  }

  @Test func expiresAfterItsBudget() async throws {
    let deadline = RenderDeadline(.milliseconds(300))
    defer { deadline.cancel() }
    #expect(!deadline.isExpired)
    let elapsed = try #require(await waitForExpiry(deadline, limit: .seconds(3)))
    #expect(elapsed >= .milliseconds(250))
    #expect(elapsed < .seconds(2))
  }

  @Test func expiryRunsTheRegisteredActionOnce() async throws {
    let deadline = RenderDeadline(.milliseconds(100))
    defer { deadline.cancel() }
    var calls = 0
    _ = deadline.onExpiry { calls += 1 }
    _ = try #require(await waitForExpiry(deadline, limit: .seconds(3)))
    try await Task.sleep(for: .milliseconds(300))
    #expect(calls == 1)
    // An action registered after expiry runs at once.
    var late = 0
    deadline.onExpiry { late += 1 }
    #expect(late == 1)
    // A removed action never runs.
    let other = RenderDeadline(.milliseconds(100))
    defer { other.cancel() }
    var removedCalls = 0
    let id = other.onExpiry { removedCalls += 1 }
    other.removeExpiry(id)
    _ = try #require(await waitForExpiry(other, limit: .seconds(3)))
    #expect(removedCalls == 0)
  }

  @Test func timeTheMainActorIsBlockedDoesNotCount() async throws {
    // Kept short: every suite of this process shares the main actor (see `blockMainActor`).
    let deadline = RenderDeadline(.milliseconds(500))
    defer { deadline.cancel() }
    blockMainActor(for: .milliseconds(700))
    try await Task.sleep(for: .milliseconds(20))
    // 0.7 s passed on the clock, but at most `longestCountedGap` (+ one tick) was counted.
    #expect(!deadline.isExpired)
    #expect(deadline.remaining >= .milliseconds(500) - RenderDeadline.longestCountedGap - RenderDeadline.tick)
    // It still expires once the main actor is free again.
    #expect(await waitForExpiry(deadline, limit: .seconds(3)) != nil)
  }

  @Test func cancelledDeadlineNeverExpires() async throws {
    let deadline = RenderDeadline(.milliseconds(100))
    var calls = 0
    _ = deadline.onExpiry { calls += 1 }
    deadline.cancel()
    try await Task.sleep(for: .milliseconds(400))
    #expect(!deadline.isExpired)
    #expect(calls == 0)
  }

  /// A page that never becomes ready still fails, and the message says what it was waiting for.
  @Test func timeoutNamesThePendingCondition() async throws {
    let html = """
      <!doctype html><div style="width:200px;height:200px"></div>
      <script>window.__ready = new Promise(function () {});</script>
      """
    let folder = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: "never-ready", width: 200, height: 200, html: html)
    let renderer = WebRenderer(timeout: .seconds(1))
    let page = WebRenderer.Page(html: html, templateFolder: folder, logosFolder: nil, width: 200, height: 200)
    await #expect(
      throws: AppError.render(message: RenderStrings.timeout(seconds: 1, pending: [RenderStrings.pendingReady]))
    ) {
      _ = try await renderer.render(page)
    }
  }

  @Test func timeoutNamesAStuckScript() async throws {
    let html = """
      <!doctype html><div style="width:200px;height:200px"></div>
      <script>window.addEventListener('load', function () { while (true) {} });</script>
      """
    let folder = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: "busy", width: 200, height: 200, html: html)
    let renderer = WebRenderer(timeout: .seconds(1))
    let page = WebRenderer.Page(html: html, templateFolder: folder, logosFolder: nil, width: 200, height: 200)
    await #expect(
      throws: AppError.render(message: RenderStrings.timeout(seconds: 1, pending: [RenderStrings.pendingUnresponsive]))
    ) {
      _ = try await renderer.render(page)
    }
  }
}
