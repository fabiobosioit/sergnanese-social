import Foundation
import SSCore
import Testing

/// Golden images of the four built-in templates, rendered from the fixture contexts.
///
/// Update them on purpose, after a deliberate template change (macOS only):
///
///     UPDATE_GOLDEN=1 swift test --filter GoldenImageTests
///
/// The comparison allows small anti-aliasing differences between machines: the mean absolute
/// channel difference must stay under 1.0 (of 255) and fewer than 0.5% of pixels may differ by more
/// than 24 in any channel.
///
/// KNOWN ENGINE FLAKE: in a minority of renders (roughly 1 in 3 on the author's Mac) the club crest
/// is missing from the snapshot although the page reported itself ready. Until the render engine is
/// fixed, the comparison renders up to `attempts` times and passes when any render matches. A
/// render that never matches still fails, so real layout regressions are caught.
@MainActor
@Suite(.serialized)
struct GoldenImageTests {
  nonisolated static let goldenFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent(".golden", isDirectory: true)
  nonisolated static let templateIDs = ["post-prematch", "story-programme", "story-halftime", "story-fulltime"]
  static let attempts = 1

  @Test(arguments: templateIDs) func builtinMatchesGolden(templateID: String) async throws {
    let env = try Env()
    let golden = Self.goldenFolder.appendingPathComponent("\(templateID).png")

    if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1" {
      let png = try await env.renderer.preview(templateID: templateID, matchIDs: [])
      try FileManager.default.createDirectory(at: Self.goldenFolder, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: golden.path) { try FileManager.default.removeItem(at: golden) }
      try FileManager.default.copyItem(at: png, to: golden)
      return
    }

    try #require(
      FileManager.default.fileExists(atPath: golden.path),
      "Missing golden image \(golden.lastPathComponent). Run: UPDATE_GOLDEN=1 swift test --filter GoldenImageTests")
    let expected = try #require(decodePixels(golden))

    var last = "no render"
    for _ in 0..<Self.attempts {
      let png = try await env.renderer.preview(templateID: templateID, matchIDs: [])
      let actual = try #require(decodePixels(png))
      guard let difference = Self.compare(actual, expected) else { return }
      last = difference
    }
    Issue.record("\(templateID) never matched its golden image in \(Self.attempts) renders; last: \(last)")
  }

  /// `nil` when the images match within the tolerance, otherwise what differs.
  static func compare(
    _ actual: (width: Int, height: Int, bytes: [UInt8]), _ expected: (width: Int, height: Int, bytes: [UInt8])
  ) -> String? {
    guard actual.width == expected.width, actual.height == expected.height else {
      return "size \(actual.width)x\(actual.height), expected \(expected.width)x\(expected.height)"
    }
    var total = 0
    var differing = 0
    let pixels = actual.bytes.count / 4
    for pixel in 0..<pixels {
      var worst = 0
      for channel in 0..<3 {
        let difference = abs(Int(actual.bytes[pixel * 4 + channel]) - Int(expected.bytes[pixel * 4 + channel]))
        total += difference
        worst = max(worst, difference)
      }
      if worst > 24 { differing += 1 }
    }
    let mean = Double(total) / Double(pixels * 3)
    let share = Double(differing) / Double(pixels)
    if mean < 1.0 && share < 0.005 { return nil }
    return "mean difference \(mean), \(share * 100)% of pixels differ"
  }
}
