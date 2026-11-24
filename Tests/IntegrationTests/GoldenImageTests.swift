import Foundation
import SSCore
import Testing

typealias Bitmap = (width: Int, height: Int, bytes: [UInt8])

/// Golden images of the four built-in templates, rendered from the fixture contexts.
///
/// Two golden sets, because text anti-aliasing differs between macOS/WebKit versions and the
/// tolerance below is deliberately not loosened: `.golden/` for local machines and `.golden/ci/`
/// for the GitHub runner (used when the environment variable CI is "true"). A set is only ever
/// written by the environment it belongs to. The CI set must come from the runner: run the
/// "Update goldens" workflow (.github/workflows/update-goldens.yml, workflow_dispatch), download
/// its artifact and commit the PNGs into `Tests/IntegrationTests/.golden/ci/`. With no image there
/// the test fails and says so; it never passes silently.
///
/// Update the local set on purpose, after a deliberate template change (macOS only):
///
///     UPDATE_GOLDEN=1 swift test --filter GoldenImageTests
///
/// (and the CI set through the workflow; locally `CI=true` would write `.golden/ci/`).
///
/// The update keeps only renders that show the crest and writes one when `agreeingRenders` of them
/// agree, so a render with a missing crest cannot become a golden.
///
/// The comparison allows small anti-aliasing differences between machines but is local as well as
/// global: the mean absolute channel difference over the image must stay under 1.0 (of 255), fewer
/// than 0.5% of pixels may differ by more than 24, and no 32x32 block may differ on average by more
/// than 8. The block rule is what catches a missing crest, which is a small part of the image.
@MainActor
@Suite(.serialized)
struct GoldenImageTests {
  nonisolated static let runsOnCI = ProcessInfo.processInfo.environment["CI"] == "true"
  nonisolated static let goldenFolder: URL = {
    let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent(".golden", isDirectory: true)
    return runsOnCI ? base.appendingPathComponent("ci", isDirectory: true) : base
  }()
  nonisolated static let missingGoldenHelp =
    runsOnCI
    ? "Run the \"Update goldens\" workflow on GitHub (Actions, workflow_dispatch), download the artifact and commit the PNGs into Tests/IntegrationTests/.golden/ci/."
    : "Run: UPDATE_GOLDEN=1 swift test --filter GoldenImageTests"
  nonisolated static let templateIDs = [
    "post-prematch", "story-programme", "story-halftime", "story-fulltime", "story-results",
  ]
  static let attempts = 1
  static let agreeingRenders = 3

  @Test(arguments: templateIDs) func builtinMatchesGolden(templateID: String) async throws {
    let env = try Env()
    let golden = Self.goldenFolder.appendingPathComponent("\(templateID).png")

    if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1" {
      // The crest-less state of the engine flake is common, so only renders that show the crest
      // count, and `agreeingRenders` of them must agree before one is written.
      var kept: [(url: URL, image: Bitmap)] = []
      var chosen: URL?
      for _ in 0..<40 where chosen == nil {
        let png = try await env.renderer.preview(templateID: templateID, matchIDs: [])
        let current = try #require(await Self.loadBitmap(png))
        guard await Self.hasCrestOffMain(current, templateID: templateID) else { continue }
        kept.append((png, current))
        let agreeing = await Self.countAgreeing(kept.map(\.image), with: current)
        if agreeing >= Self.agreeingRenders { chosen = png }
      }
      try #require(chosen != nil, "renders of \(templateID) never settled; golden not written")
      try FileManager.default.createDirectory(at: Self.goldenFolder, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: golden.path) { try FileManager.default.removeItem(at: golden) }
      try FileManager.default.copyItem(at: try #require(chosen), to: golden)
      return
    }

    try #require(
      FileManager.default.fileExists(atPath: golden.path),
      "Missing golden image \(golden.lastPathComponent) in \(Self.goldenFolder.path). \(Self.missingGoldenHelp)")
    let expected = try #require(await Self.loadBitmap(golden))

    var last = "no render"
    for _ in 0..<Self.attempts {
      let png = try await env.renderer.preview(templateID: templateID, matchIDs: [])
      let actual = try #require(await Self.loadBitmap(png))
      guard let difference = await Self.compareOffMain(actual, expected) else { return }
      last = difference
    }
    Issue.record("\(templateID) never matched its golden image in \(Self.attempts) renders; last: \(last)")
  }

  /// The comparison must notice a blanked crest in every template.
  // Pure pixel work, so it runs off the main actor.
  @Test(arguments: templateIDs) nonisolated func blankedCrestIsDetected(templateID: String) throws {
    let golden = Self.goldenFolder.appendingPathComponent("\(templateID).png")
    try #require(
      FileManager.default.fileExists(atPath: golden.path),
      "Missing golden image \(golden.lastPathComponent) in \(Self.goldenFolder.path). \(Self.missingGoldenHelp)")
    let expected = try #require(decodePixels(golden))
    #expect(Self.compare(expected, expected) == nil)
    // The crest sits at x 68...174; y 83 in the post, 253 in the stories (124 px box).
    let top = Self.crestTop(templateID)
    #expect(Self.hasCrest(expected, templateID: templateID))
    var blanked = expected
    let fillIndex = ((top + 60) * expected.width + 20) * 4
    let fill = Array(expected.bytes[fillIndex..<(fillIndex + 4)])
    for y in top..<(top + 124) {
      for x in 68..<192 {
        let index = (y * expected.width + x) * 4
        blanked.bytes.replaceSubrange(index..<(index + 4), with: fill)
      }
    }
    #expect(Self.compare(blanked, expected) != nil)
    #expect(!Self.hasCrest(blanked, templateID: templateID))
  }

  // The pixel helpers are `nonisolated` and the `async` wrappers below hop off the main actor,
  // so only the rendering call stays on it. Bitmaps are Sendable value types.

  /// Decodes a PNG off the main actor.
  nonisolated static func loadBitmap(_ url: URL) async -> Bitmap? { decodePixels(url) }

  /// `compare`, off the main actor.
  nonisolated static func compareOffMain(_ actual: Bitmap, _ expected: Bitmap) async -> String? {
    compare(actual, expected)
  }

  /// `hasCrest`, off the main actor.
  nonisolated static func hasCrestOffMain(_ image: Bitmap, templateID: String) async -> Bool {
    hasCrest(image, templateID: templateID)
  }

  /// How many of `images` match `current` within the tolerance, off the main actor.
  nonisolated static func countAgreeing(_ images: [Bitmap], with current: Bitmap) async -> Int {
    images.filter { compare($0, current) == nil }.count
  }

  /// Top of the 124 px crest box (x 68...192): y 83 in the post, 253 in the stories.
  nonisolated static func crestTop(_ templateID: String) -> Int { templateID == "post-prematch" ? 83 : 253 }

  /// `true` when the crest box holds the crest's black outline (a blank box has no dark pixels).
  nonisolated static func hasCrest(_ image: Bitmap, templateID: String) -> Bool {
    let top = crestTop(templateID)
    var dark = 0
    for y in top..<(top + 124) {
      for x in 68..<192 {
        let index = (y * image.width + x) * 4
        if image.bytes[index] < 60 && image.bytes[index + 1] < 60 && image.bytes[index + 2] < 60 { dark += 1 }
      }
    }
    return dark > 200
  }

  /// `nil` when the images match within the tolerance, otherwise what differs.
  nonisolated static func compare(_ actual: Bitmap, _ expected: Bitmap) -> String? {
    guard actual.width == expected.width, actual.height == expected.height else {
      return "size \(actual.width)x\(actual.height), expected \(expected.width)x\(expected.height)"
    }
    let block = 32
    let columns = (actual.width + block - 1) / block
    let rows = (actual.height + block - 1) / block
    var blockTotals = [Int](repeating: 0, count: columns * rows)
    var blockCounts = [Int](repeating: 0, count: columns * rows)
    var total = 0
    var differing = 0
    let pixels = actual.bytes.count / 4
    for pixel in 0..<pixels {
      var worst = 0
      var sum = 0
      for channel in 0..<3 {
        let difference = abs(Int(actual.bytes[pixel * 4 + channel]) - Int(expected.bytes[pixel * 4 + channel]))
        sum += difference
        worst = max(worst, difference)
      }
      total += sum
      if worst > 24 { differing += 1 }
      let cell = (pixel / actual.width / block) * columns + (pixel % actual.width) / block
      blockTotals[cell] += sum
      blockCounts[cell] += 3
    }
    let mean = Double(total) / Double(pixels * 3)
    let share = Double(differing) / Double(pixels)
    var worstBlock = 0.0
    for cell in 0..<blockTotals.count where blockCounts[cell] > 0 {
      worstBlock = max(worstBlock, Double(blockTotals[cell]) / Double(blockCounts[cell]))
    }
    if mean < 1.0 && share < 0.005 && worstBlock <= 8 { return nil }
    return "mean difference \(mean), \(share * 100)% of pixels differ, worst 32x32 block \(worstBlock)"
  }
}
