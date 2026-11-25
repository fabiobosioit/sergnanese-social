import AppKit
import Foundation
import SSApp
import SSCore
import SSCoreFakes
import SwiftUI

/// `ss-tool screenshots [output-folder]`: renders every screen of the app on the fake data, in Light
/// and in Dark appearance, to `out/screens/<screen>-<light|dark>.png`.
///
/// The views are hosted in an off-screen window and drawn by AppKit itself, so no screen recording
/// permission is needed. Best effort: the toolbar and the menu bar are not part of the window content
/// and are not captured.
func runScreenshots(_ args: [String]) async -> Int32 {
  let folder = URL(fileURLWithPath: args.first ?? "out/screens", isDirectory: true)
  return await captureScreenshots(to: folder)
}

@MainActor
private func captureScreenshots(to folder: URL) async -> Int32 {
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)
  do {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  } catch {
    FileHandle.standardError.write(Data("cannot create \(folder.path): \(error.localizedDescription)\n".utf8))
    return 1
  }
  let services = AppServices.fake()
  let resultServices = AppServices.fake()
  var failures = 0
  for appearance in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    for scene in ScreenshotSupport.scenes(services: services, resultServices: resultServices) {
      let file = folder.appendingPathComponent("\(scene.name)-\(appearance.0).png")
      if let png = await render(scene, appearance: appearance.1) {
        do {
          try png.write(to: file)
          print("wrote \(file.path)")
        } catch {
          failures += 1
          print("failed \(file.path): \(error.localizedDescription)")
        }
      } else {
        failures += 1
        print("failed \(file.path): could not draw the view")
      }
    }
  }
  return failures == 0 ? 0 : 1
}

@MainActor
private func render(_ scene: ScreenshotScene, appearance: NSAppearance.Name) async -> Data? {
  let frame = NSRect(origin: .zero, size: scene.size)
  let host = NSHostingView(rootView: scene.view.background(Color(nsColor: .windowBackgroundColor)))
  host.frame = frame
  let window = NSWindow(
    contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
  window.appearance = NSAppearance(named: appearance)
  window.contentView = host
  window.setContentSize(scene.size)
  // Off screen but ordered in, so SwiftUI runs onAppear and .task (thumbnails).
  window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
  window.orderFrontRegardless()
  defer { window.orderOut(nil) }
  // Let SwiftUI lay out, load thumbnails and settle; the run loop must turn for that.
  // Both are needed: sleeping lets main-actor tasks (thumbnail loading) resume, and the run loop
  // services AppKit's display and layout work.
  for _ in 0..<30 {
    try? await Task.sleep(for: .milliseconds(60))
    pumpRunLoop()
    host.layoutSubtreeIfNeeded()
  }
  guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
  host.cacheDisplay(in: host.bounds, to: rep)
  return rep.representation(using: .png, properties: [:])
}

/// Lets AppKit do its display and layout work (synchronous on purpose: the run loop cannot be used from async code).
@MainActor
private func pumpRunLoop() {
  RunLoop.current.run(until: Date().addingTimeInterval(0.04))
}
