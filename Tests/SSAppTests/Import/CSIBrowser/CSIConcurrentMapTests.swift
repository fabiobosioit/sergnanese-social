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
  }

  @Test func answersComeBackInOrderWithAtMostThreeAtATime() async {
    let meter = Meter()
    let answers = await CSIConcurrentMap.run(Array(0..<10), limit: 3) { value in
      meter.running += 1
      meter.peak = max(meter.peak, meter.running)
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
        meter.running += 1
        try? await Task.sleep(for: .seconds(30))  // returns at once when cancelled
        return value
      }
    }
    let deadline = ContinuousClock.now + .seconds(10)
    while meter.running < 3 && ContinuousClock.now < deadline { await Task.yield() }
    task.cancel()
    let answers = await task.value
    #expect(answers.count == 9)
    #expect(meter.running == 3, "running \(meter.running)")
    #expect(answers.filter { $0 == nil }.count == 6)
  }
}
