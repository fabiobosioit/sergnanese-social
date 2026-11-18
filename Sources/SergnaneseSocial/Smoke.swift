import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SSCore

/// Self-contained packaging check, run by `--smoke`. It proves that a packaged app, copied away
/// from the build machine, runs the real engine: resources are found, the database opens in a
/// temporary data folder, the seed loads, a built-in template renders to a PNG of the exact size and
/// the accent colour reads back unchanged. Returns the process exit code.
func runSmoke() -> Int32 {
  MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.prohibited)
    var outcome: Result<Void, SmokeFailure>?
    Task { @MainActor in
      do {
        try await smokeChecks()
        outcome = .success(())
      } catch let failure as SmokeFailure {
        outcome = .failure(failure)
      } catch {
        outcome = .failure(SmokeFailure(message: "\(error)"))
      }
    }
    let deadline = Date().addingTimeInterval(90)
    while outcome == nil && Date() < deadline {
      RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    switch outcome {
    case .success?:
      print("SMOKE OK")
      return 0
    case .failure(let failure)?:
      print("SMOKE FAILED: \(failure.message)")
      return 1
    case nil:
      print("SMOKE FAILED: timed out after 90 s")
      return 1
    }
  }
}

private struct SmokeFailure: Error {
  var message: String
}

@MainActor
private func smokeChecks() async throws {
  // Temporary data folder: the user's real folders are never opened.
  let temp = FileManager.default.temporaryDirectory.appendingPathComponent(
    "ss-smoke-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: temp) }
  var environment = ProcessInfo.processInfo.environment
  environment["SS_DATA_DIR"] = temp.path
  let paths = try AppPaths.resolve(environment: environment)
  print("smoke: resources \(paths.resources.path)")

  let services = try Composition.makeServices(paths: paths)
  print("smoke: services ready")

  let today = DayDate.today()
  let summary = try await services.demoData.load(today: today)
  guard summary.matches > 0 else { throw SmokeFailure(message: "seed loaded no matches") }
  print("smoke: seed \(summary.matches) matches")

  let weekend = nextWeekend(from: today)
  let details = try services.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)
  guard let match = details.first(where: { $0.team.isFirstTeam && $0.match.status == .scheduled }) else {
    throw SmokeFailure(message: "no first-team match in the next weekend")
  }
  let request = RenderRequest(
    weekend: weekend, selections: [TemplateSelection(templateID: "post-prematch", matchIDs: [match.match.id])])
  var image: RenderedImage?
  for try await event in services.renderer.render(request) {
    switch event {
    case .imageDone(let done, _, _): image = done
    case .imageFailed(_, let message, _, _): throw SmokeFailure(message: "render failed: \(message)")
    default: break
    }
  }
  guard let image else { throw SmokeFailure(message: "nothing was rendered") }
  let data = try Data(contentsOf: image.record.fileURL)
  guard let source = CGImageSourceCreateWithData(data as CFData, nil),
    let png = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { throw SmokeFailure(message: "output is not a PNG") }
  guard png.width == 1080, png.height == 1350 else {
    throw SmokeFailure(message: "unexpected PNG size \(png.width)x\(png.height)")
  }
  let accent = try accentHex(of: png, x: 20, y: 1340)
  guard accent == "#CF3326" else { throw SmokeFailure(message: "accent pixel is \(accent), expected #CF3326") }
  print("smoke: rendered \(png.width)x\(png.height), accent pixel \(accent)")
}

/// Colour of one pixel, read back in sRGB.
private func accentHex(of image: CGImage, x: Int, y: Int) throws -> String {
  var pixel = [UInt8](repeating: 0, count: 4)
  guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw SmokeFailure(message: "no sRGB") }
  let drawn = pixel.withUnsafeMutableBytes { raw -> Bool in
    guard
      let context = CGContext(
        data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return false }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return true
  }
  guard drawn else { throw SmokeFailure(message: "cannot read pixel") }
  return String(format: "#%02X%02X%02X", pixel[0], pixel[1], pixel[2])
}
