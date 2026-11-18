import CoreGraphics
import Foundation
import ImageIO
import SSCore
import SSData
import SSRender
import SSSeed
import SSTemplates

/// Real services on a temporary data folder, wired like `Composition.makeServices` (that file lives
/// in the executable target, which tests cannot import). No UI, and never the user's folders.
@MainActor
final class Env {
  let root: URL
  let paths: AppPaths
  let database: AppDatabase
  let templates: FileTemplateStore
  let logos: LogoFileStore
  let renderer: TemplateRenderService
  let loader: SeedLoader

  /// A Wednesday: the next weekend starts on Saturday 2026-11-21.
  static let today = try! DayDate("2026-11-18")

  /// One web view for every test, as in the app. Several off-screen web views at once make snapshots flaky.
  static let webRenderer = WebRenderer()

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ss-integration-\(UUID().uuidString)", isDirectory: true)
    guard let resources = AppPaths.resolveResources() else {
      throw AppError.io(message: "resources folder not found")
    }
    paths = AppPaths(
      dataFolder: root.appendingPathComponent("data", isDirectory: true), resources: resources,
      defaultOutputFolder: root.appendingPathComponent("output", isDirectory: true))
    try paths.createFolders()
    database = try AppDatabase.open(paths: paths)
    logos = LogoFileStore(folder: paths.logos)
    templates = FileTemplateStore(paths: paths)
    try templates.installBuiltins()
    renderer = TemplateRenderService(
      templates: templates, matches: database.matches, renders: database.renders, settings: database.settings,
      paths: paths, renderer: Env.webRenderer)
    loader = SeedLoader(
      seedFolder: paths.seed, teams: database.teams, opponents: database.opponents, matches: database.matches,
      logos: logos)
  }

  deinit { try? FileManager.default.removeItem(at: root) }

  var weekend: Weekend { nextWeekend(from: Env.today) }

  func seed() async throws {
    _ = try await loader.load(today: Env.today)
  }

  /// Runs a render to the end and returns the finished images (throwing on any failed image).
  func render(_ request: RenderRequest) async throws -> [RenderedImage] {
    var images: [RenderedImage] = []
    for try await event in renderer.render(request) {
      switch event {
      case .imageDone(let image, _, _): images.append(image)
      case .imageFailed(let planned, let message, _, _):
        throw AppError.render(message: "\(planned.fileName): \(message)")
      default: break
      }
    }
    return images
  }
}

func pngSize(_ url: URL) -> (width: Int, height: Int)? {
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
    let width = properties[kCGImagePropertyPixelWidth] as? Int,
    let height = properties[kCGImagePropertyPixelHeight] as? Int
  else { return nil }
  return (width, height)
}

/// RGBA bytes of a PNG decoded in sRGB, row 0 at the top.
func decodePixels(_ url: URL) -> (width: Int, height: Int, bytes: [UInt8])? {
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
    let space = CGColorSpace(name: CGColorSpace.sRGB)
  else { return nil }
  let width = image.width
  let height = image.height
  var bytes = [UInt8](repeating: 0, count: width * height * 4)
  let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
    guard
      let context = CGContext(
        data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return false }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
  }
  return drawn ? (width, height, bytes) : nil
}
