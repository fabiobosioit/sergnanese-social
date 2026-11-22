import Foundation

/// Runs `work` on every item, at most `limit` at a time, on the main actor, and returns the answers in the
/// order of the items. An item that was not started because the task was cancelled has no answer (`nil`).
@MainActor
enum CSIConcurrentMap {
  static func run<Item: Sendable, Answer: Sendable>(
    _ items: [Item], limit: Int, _ work: @escaping @MainActor @Sendable (Item) async -> Answer
  ) async -> [Answer?] {
    let queue = Queue<Answer>(count: items.count)
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<min(max(limit, 1), items.count) {
        group.addTask { await Self.worker(queue, items, work) }
      }
    }
    return queue.answers
  }

  private static func worker<Item: Sendable, Answer: Sendable>(
    _ queue: Queue<Answer>, _ items: [Item], _ work: @MainActor @Sendable (Item) async -> Answer
  ) async {
    while !Task.isCancelled, let index = queue.take() {
      queue.answers[index] = await work(items[index])
    }
  }

  /// The next item to start and the answers so far, shared by the workers.
  @MainActor
  private final class Queue<Answer: Sendable> {
    private var next = 0
    private let count: Int
    var answers: [Answer?]

    init(count: Int) {
      self.count = count
      answers = Array(repeating: nil, count: count)
    }

    func take() -> Int? {
      guard next < count else { return nil }
      defer { next += 1 }
      return next
    }
  }
}
