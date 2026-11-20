import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SSCore
import SSRender

/// Decoded pixels of a PNG, in sRGB, row 0 at the top.
struct Pixels {
  let width: Int
  let height: Int
  let bytes: [UInt8]

  init(png data: Data) throws {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw CocoaError(.fileReadCorruptFile) }
    try self.init(image: image)
  }

  init(image: CGImage) throws {
    let width = image.width
    let height = image.height
    self.width = width
    self.height = height
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
      guard
        let context = CGContext(
          data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { throw CocoaError(.fileReadCorruptFile) }
    bytes = buffer
  }

  /// `"#RRGGBB"` of the pixel at (`x`, `y`), `y` counted from the top.
  func hex(x: Int, y: Int) -> String {
    let offset = (y * width + x) * 4
    return String(format: "#%02X%02X%02X", bytes[offset], bytes[offset + 1], bytes[offset + 2])
  }

  var centreHex: String { hex(x: width / 2, y: height / 2) }
}

/// A fresh temporary folder.
func makeTemporaryFolder(_ name: String = "SSRenderTests") throws -> URL {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
    "\(name)-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  return folder
}

/// Keeps the main actor (the main thread) busy for `duration` without suspending, like a long
/// synchronous computation elsewhere in the app or in a test running in parallel. Every suite of
/// this test process shares the main actor, so keep `duration` short: it delays them all.
@MainActor
func blockMainActor(for duration: Duration) {
  let end = ContinuousClock.now + duration
  while ContinuousClock.now < end {}
}

/// The bundle id of the frontmost app and the visible windows of this process, to check that
/// rendering never shows a window or changes focus.
@MainActor
struct FocusSnapshot: Equatable {
  let frontmost: String?
  let visibleWindows: Int
  let isActive: Bool

  static func take() -> FocusSnapshot {
    FocusSnapshot(
      frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        ?? NSWorkspace.shared.frontmostApplication?.localizedName,
      visibleWindows: NSApplication.shared.windows.filter(\.isVisible).count,
      isActive: NSApplication.shared.isActive)
  }
}

/// A renderer whose web view exists and has finished one render, for the timeout tests. The first
/// render launches WebKit's processes, which on a busy CI runner can take longer than a short
/// timeout; a timeout test would then time out while loading and name the wrong pending condition.
/// A timeout resets the web view, so a failed warm-up is retried with a fresh one.
@MainActor
func warmedUpRenderer(timeout: Duration) async throws -> WebRenderer {
  let html = "<!doctype html><div style=\"width:200px;height:200px\"></div>"
  let folder = try FixtureTemplates.custom(
    in: try makeTemporaryFolder(), id: "warm-up", width: 200, height: 200, html: html)
  let renderer = WebRenderer(timeout: timeout)
  let page = WebRenderer.Page(html: html, templateFolder: folder, logosFolder: nil, width: 200, height: 200)
  for _ in 0..<3 {
    if (try? await renderer.render(page)) != nil { break }
  }
  return renderer
}
