import Foundation
import Testing

@testable import SSApp

@MainActor
struct CSIConcurrentMapTests {
  /// Counts how many jobs run at the same time.
  @MainActor
  final class Meter {
    var running = 0
    var peak = 0
    private var waiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    /// Returns once `running` has reached `count`. No polling and no deadline.
    func waitUntilRunning(_ count: Int) async {
      if running >= count { return }
      await withCheckedContinuation { waiter = (count, $0) }
    }

    func started() {
      running += 1
      peak = max(peak, running)
      if let waiter, running >= waiter.count {
        self.waiter = nil
        waiter.continuation.resume()
      }
    }
  }

  @Test func answersComeBackInOrderWithAtMostThreeAtATime() async {
    let meter = Meter()
    let answers = await CSIConcurrentMap.run(Array(0..<10), limit: 3) { value in
      meter.started()
      try? await Task.sleep(for: .milliseconds(10 + (10 - value) * 3))
      meter.running -= 1
      return value * 2
    }
    #expect(answers == (0..<10).map { $0 * 2 })
    #expect(meter.peak == 3)
  }

  @Test func fewerItemsThanTheLimit() async {
    let answers = await CSIConcurrentMap.run(["a", "b"], limit: 3) { $0.uppercased() }
    #expect(answers == ["A", "B"])
    #expect(await CSIConcurrentMap.run([Int](), limit: 3) { $0 }.isEmpty)
  }

  @Test func cancellationLeavesTheRestUnstarted() async {
    let meter = Meter()
    let task = Task { @MainActor in
      await CSIConcurrentMap.run(Array(0..<9), limit: 3) { value in
        meter.started()
        try? await Task.sleep(for: .seconds(30))  // returns at once when cancelled
        return value
      }
    }
    await meter.waitUntilRunning(3)
    task.cancel()
    let answers = await task.value
    #expect(answers.count == 9)
    #expect(meter.running == 3, "running \(meter.running)")
    #expect(answers.filter { $0 == nil }.count == 6)
  }
}
