import Foundation
import SSCore
import Testing

@testable import SSRender

/// Regression tests for the "template not ready after 10 seconds" flake: renders that failed with the
/// timeout although the page was fine, because the time limit also counted time in which the
/// renderer could not run at all (the main actor blocked by other work, or the Mac asleep).
///
/// No test bounds an expiry with wall-clock time. A deadline deliberately ignores time in which the
/// main actor is busy, and on a loaded CI runner the main actor can be busy for seconds (other suites
/// run `@MainActor` tests in parallel), so "expires within N seconds" is not a property it has. The
/// accounting is tested with `count(gap:)` and no ticker; the real ticker is tested by waiting for
/// what it does (`didCount`, `isExpired`), with `waitUntil`, whose limit is counted the same way.
@MainActor
@Suite(.serialized)
struct RenderDeadlineTests {
  /// Waits, without blocking the main actor, until `condition` holds. Returns `false` only after
  /// `limit` of time this test could run: like `RenderDeadline`, a gap of more than 250 ms between two
  /// checks counts as 250 ms, so a main actor busy elsewhere never uses up the limit. The limit only
  /// stops a broken test from hanging; it is far beyond what any condition here needs.
  func waitUntil(limit: Duration = .seconds(30), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    var last = clock.now
    var counted = Duration.zero
    while !condition() {
      if counted >= limit { return false }
      try? await Task.sleep(for: .milliseconds(5))
      let now = clock.now
      counted += min(now - last, .milliseconds(250))
      last = now
    }
    return true
  }

  // MARK: Accounting, without a ticker

  @Test func budgetIsSpentGapByGap() {
    let deadline = RenderDeadline(.milliseconds(300), startsTicker: false)
    #expect(!deadline.isExpired)
    #expect(!deadline.count(gap: .milliseconds(100)))
    #expect(!deadline.count(gap: .milliseconds(100)))
    #expect(deadline.remaining == .milliseconds(100))
    #expect(!deadline.isExpired)
    #expect(deadline.count(gap: .milliseconds(100)))
    #expect(deadline.isExpired)
    #expect(deadline.remaining == .zero)
    #expect(deadline.countedGaps == 3)
  }

  @Test func aLongGapCountsOnlyTheLongestCountedGap() {
    let deadline = RenderDeadline(.seconds(1), startsTicker: false)
    var counted: [Duration] = []
    deadline.didCount = { counted.append($0) }
    // The ticker ran again only 10 s later: the main actor was busy with other work meanwhile.
    #expect(!deadline.count(gap: .seconds(10)))
    #expect(counted == [RenderDeadline.longestCountedGap])
    #expect(deadline.remaining == .seconds(1) - RenderDeadline.longestCountedGap)
    #expect(!deadline.isExpired)
    // Even an hour-long gap cannot expire a deadline with more than one gap's worth left.
    #expect(!deadline.count(gap: .seconds(3600)))
    #expect(deadline.remaining == .seconds(1) - RenderDeadline.longestCountedGap * 2)
  }

  @Test func expiryRunsTheRegisteredActionOnce() {
    let deadline = RenderDeadline(.milliseconds(100), startsTicker: false)
    var calls = 0
    _ = deadline.onExpiry { calls += 1 }
    #expect(deadline.count(gap: .milliseconds(100)))
    #expect(calls == 1)
    // Gaps after expiry are ignored and never run the action again.
    #expect(deadline.count(gap: .milliseconds(100)))
    #expect(calls == 1)
    #expect(deadline.countedGaps == 1)
    // An action registered after expiry runs at once.
    var late = 0
    deadline.onExpiry { late += 1 }
    #expect(late == 1)
    // A new action replaces the previous one.
    let replaced = RenderDeadline(.milliseconds(100), startsTicker: false)
    var first = 0
    var second = 0
    replaced.onExpiry { first += 1 }
    replaced.onExpiry { second += 1 }
    replaced.count(gap: .milliseconds(100))
    #expect(first == 0)
    #expect(second == 1)
    // A removed action never runs; removing an id that is no longer current changes nothing.
    let other = RenderDeadline(.milliseconds(100), startsTicker: false)
    var removedCalls = 0
    var keptCalls = 0
    let removedID = other.onExpiry { removedCalls += 1 }
    other.removeExpiry(removedID)
    other.count(gap: .milliseconds(100))
    #expect(other.isExpired)
    #expect(removedCalls == 0)
    let stale = RenderDeadline(.milliseconds(100), startsTicker: false)
    let staleID = stale.onExpiry {}
    stale.onExpiry { keptCalls += 1 }
    stale.removeExpiry(staleID)
    stale.count(gap: .milliseconds(100))
    #expect(keptCalls == 1)
  }

  @Test func zeroBudgetIsExpiredAtOnce() {
    let deadline = RenderDeadline(.zero)
    #expect(deadline.isExpired)
    var calls = 0
    deadline.onExpiry { calls += 1 }
    #expect(calls == 1)
  }

  @Test func cancelledDeadlineIgnoresGaps() {
    let deadline = RenderDeadline(.milliseconds(100), startsTicker: false)
    var calls = 0
    _ = deadline.onExpiry { calls += 1 }
    deadline.cancel()
    #expect(!deadline.count(gap: .seconds(10)))
    #expect(!deadline.isExpired)
    #expect(deadline.remaining == .milliseconds(100))
    #expect(calls == 0)
  }

  // MARK: The real ticker

  @Test func tickerSpendsTheBudgetAndExpires() async throws {
    let start = ContinuousClock.now
    let deadline = RenderDeadline(.milliseconds(300))
    defer { deadline.cancel() }
    var calls = 0
    _ = deadline.onExpiry { calls += 1 }
    #expect(!deadline.isExpired)
    try #require(await waitUntil { deadline.isExpired })
    // Counted time never exceeds the time that passed (SuspendingClock deltas are at most
    // ContinuousClock deltas, and each gap counts at most itself), so it cannot expire early.
    #expect(ContinuousClock.now - start >= .milliseconds(300))
    // Each gap counts at most `longestCountedGap`, so 300 ms take at least two runs of the ticker,
    // and the last one overshoots by less than one gap.
    #expect(deadline.countedGaps >= 2)
    #expect(deadline.remaining <= .zero)
    #expect(deadline.remaining > .zero - RenderDeadline.longestCountedGap)
    #expect(calls == 1)
    // The ticker stopped: the action never runs again. (Load only makes this wait longer.)
    let gaps = deadline.countedGaps
    try await Task.sleep(for: .milliseconds(300))
    #expect(calls == 1)
    #expect(deadline.countedGaps == gaps)
  }

  @Test func timeTheMainActorIsBlockedDoesNotCount() async throws {
    // The budget is long enough that the ticker cannot expire it before the block (that would take
    // eight gaps), and the block is kept short: every suite of this process shares the main actor.
    let deadline = RenderDeadline(.seconds(2))
    defer { deadline.cancel() }
    var counted: [Duration] = []
    deadline.didCount = { counted.append($0) }
    try #require(await waitUntil { !counted.isEmpty })  // the ticker is running
    try #require(!deadline.isExpired)
    let before = counted.count
    blockMainActor(for: .milliseconds(700))
    try #require(await waitUntil { counted.count > before })
    // The first gap after the block lasted at least 0.7 s and counted exactly `longestCountedGap`,
    // however many more gaps ran before this check.
    #expect(counted[before] == RenderDeadline.longestCountedGap)
    // It still expires once the main actor is free again.
    #expect(await waitUntil { deadline.isExpired })
  }

  @Test func cancelledDeadlineNeverExpires() async throws {
    let deadline = RenderDeadline(.milliseconds(100))
    var calls = 0
    _ = deadline.onExpiry { calls += 1 }
    deadline.cancel()
    // Load can only make the ticker run less in this time, never more.
    try await Task.sleep(for: .milliseconds(400))
    #expect(!deadline.isExpired)
    #expect(deadline.countedGaps == 0)
    #expect(calls == 0)
  }

  // MARK: Timeout messages

  /// A page that never becomes ready still fails, and the message says what it was waiting for.
  @Test func timeoutNamesThePendingCondition() async throws {
    let html = """
      <!doctype html><div style="width:200px;height:200px"></div>
      <script>window.__ready = new Promise(function () {});</script>
      """
    let folder = try FixtureTemplates.custom(
      in: try makeTemporaryFolder(), id: "never-ready", width: 200, height: 200, html: html)
    let renderer = try await warmedUpRenderer(timeout: .seconds(2))
    let page = WebRenderer.Page(html: html, templateFolder: folder, logosFolder: nil, width: 200, height: 200)
    await #expect(
      throws: AppError.render(message: RenderStrings.timeout(seconds: 2, pending: [RenderStrings.pendingReady]))
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
    let renderer = try await warmedUpRenderer(timeout: .seconds(2))
    let page = WebRenderer.Page(html: html, templateFolder: folder, logosFolder: nil, width: 200, height: 200)
    await #expect(
      throws: AppError.render(message: RenderStrings.timeout(seconds: 2, pending: [RenderStrings.pendingUnresponsive]))
    ) {
      _ = try await renderer.render(page)
    }
  }
}
