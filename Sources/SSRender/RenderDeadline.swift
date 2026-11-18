import Foundation

/// The time limit of one render, counted only while the renderer could actually run.
///
/// A render needs the main actor at every step: the scheme handler answers WebKit on it, and the
/// navigation delegate, `callAsyncJavaScript` and `takeSnapshot` complete on it. A plain wall-clock
/// deadline also counted time in which none of that could happen, and failed good renders with the
/// timeout:
/// - the Mac asleep (lid closed, or an idle Mac between two dark wakes): `ContinuousClock` keeps
///   running during sleep, so a render in flight found its deadline passed on wake;
/// - the main actor blocked by other work (a long synchronous computation in the app, or a test
///   comparing bitmaps on the main actor while another test renders).
///
/// So the budget is spent by a ticker on the main actor that runs every `tick` on `SuspendingClock`
/// (which stops while the Mac sleeps), and that counts at most `longestCountedGap` between two of its
/// runs: a longer gap means the main actor was not available, and that time is not the template's
/// fault. A page that is really stuck still fails after `budget` of available time.
@MainActor
final class RenderDeadline {
  typealias Clock = SuspendingClock

  /// How often the ticker spends the budget.
  static let tick: Duration = .milliseconds(100)
  /// Most time counted between two ticks; the rest of a longer gap is ignored.
  static let longestCountedGap: Duration = .milliseconds(250)

  /// Budget not spent yet.
  private(set) var remaining: Duration
  private(set) var isExpired = false
  private var action: (id: Int, run: @MainActor () -> Void)?
  private var lastID = 0
  private var ticker: Task<Void, Never>?

  init(_ budget: Duration) {
    remaining = budget
    guard budget > .zero else {
      isExpired = true
      return
    }
    ticker = Task { [weak self] in
      let clock = Clock()
      var last = clock.now
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: Self.tick, clock: clock)
        } catch {
          return
        }
        guard let self else { return }
        let now = clock.now
        if self.spend(min(now - last, Self.longestCountedGap)) { return }
        last = now
      }
    }
  }

  /// Runs `run` once when the budget runs out (at once if it already has). Returns an id for
  /// `removeExpiry`. One action at a time: a new one replaces the previous one.
  @discardableResult
  func onExpiry(_ run: @escaping @MainActor () -> Void) -> Int {
    lastID += 1
    if isExpired {
      run()
    } else {
      action = (lastID, run)
    }
    return lastID
  }

  /// Forgets the action registered with `id`, if it is still the current one.
  func removeExpiry(_ id: Int) {
    if action?.id == id { action = nil }
  }

  /// Stops the ticker; the deadline never expires afterwards.
  func cancel() {
    ticker?.cancel()
    ticker = nil
    action = nil
  }

  /// Spends `duration`; returns `true` when the budget is gone.
  private func spend(_ duration: Duration) -> Bool {
    remaining -= duration
    guard remaining <= .zero else { return false }
    isExpired = true
    ticker = nil
    let current = action
    action = nil
    current?.run()
    return true
  }
}
