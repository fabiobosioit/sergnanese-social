import AppKit
import Foundation
import GRDB
import SSCore
import WebKit

/// Self-contained packaging check, run by `--smoke` (T1.5). It proves that a packaged app, copied
/// away from the build machine, can: find its bundled resources, open a SQLite database, and
/// snapshot HTML in an off-screen `WKWebView` to a PNG of the exact size asked for.
/// T3.1 switches this to the real engine. Returns the process exit code.
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
    let deadline = Date().addingTimeInterval(60)
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
      print("SMOKE FAILED: timed out after 60 s")
      return 1
    }
  }
}

private struct SmokeFailure: Error {
  var message: String
}

@MainActor
private func smokeChecks() async throws {
  // 1. Resources resolve to plain folders (never Bundle.module).
  guard let resources = AppPaths.resolveResources() else {
    throw SmokeFailure(message: "resources folder not found")
  }
  let fileManager = FileManager.default
  var isFolder: ObjCBool = false
  let hasFolder = ["Templates", "Fixtures"].contains {
    fileManager.fileExists(atPath: resources.appendingPathComponent($0).path, isDirectory: &isFolder)
      && isFolder.boolValue
  }
  guard hasFolder else { throw SmokeFailure(message: "no Templates or Fixtures in \(resources.path)") }
  print("smoke: resources \(resources.path)")

  // 2. SQLite through GRDB, in a temporary folder.
  let temp = fileManager.temporaryDirectory.appendingPathComponent(
    "ss-smoke-\(UUID().uuidString)", isDirectory: true)
  try fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
  defer { try? fileManager.removeItem(at: temp) }
  let queue = try DatabaseQueue(path: temp.appendingPathComponent("smoke.sqlite").path)
  let answer = try await queue.write { db -> Int in
    try db.execute(sql: "CREATE TABLE t (n INTEGER)")
    try db.execute(sql: "INSERT INTO t (n) VALUES (42)")
    return try Int.fetchOne(db, sql: "SELECT n FROM t") ?? -1
  }
  guard answer == 42 else { throw SmokeFailure(message: "database returned \(answer)") }
  print("smoke: database ok")

  // 3. Off-screen WKWebView snapshot of a tiny inline page, exact pixel size.
  let width = 270
  let height = 480
  let web = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: height))
  let loader = NavigationWaiter()
  web.navigationDelegate = loader
  try await loader.load(
    "<html><body style=\"margin:0;background:#c00\"><h1 style=\"color:white\">Smoke</h1></body></html>", in: web)
  let config = WKSnapshotConfiguration()
  config.rect = CGRect(x: 0, y: 0, width: width, height: height)
  config.snapshotWidth = NSNumber(value: width)
  let image = try await web.takeSnapshot(configuration: config)
  guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    throw SmokeFailure(message: "snapshot has no bitmap")
  }
  let rep = NSBitmapImageRep(cgImage: cgImage)
  guard let png = rep.representation(using: .png, properties: [:]), !png.isEmpty else {
    throw SmokeFailure(message: "could not encode PNG")
  }
  guard cgImage.width >= width, cgImage.height >= height, cgImage.width * height == cgImage.height * width else {
    throw SmokeFailure(message: "unexpected snapshot size \(cgImage.width)x\(cgImage.height)")
  }
  print("smoke: snapshot \(cgImage.width)x\(cgImage.height), \(png.count) bytes")
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
  private var continuation: CheckedContinuation<Void, Error>?

  func load(_ html: String, in web: WKWebView) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      self.continuation = continuation
      web.loadHTMLString(html, baseURL: nil)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    continuation?.resume()
    continuation = nil
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    continuation?.resume(throwing: error)
    continuation = nil
  }
}
