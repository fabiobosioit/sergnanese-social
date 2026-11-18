import AppKit

/// Determinate progress on the Dock icon while images are generated. When it finishes and the app is
/// in the background, the icon bounces once. No notification, no alert.
@MainActor
public final class DockProgress {
  public static let shared = DockProgress()

  private(set) var fraction: Double?
  private let tile: NSDockTile
  private var view: DockProgressView?

  init(tile: NSDockTile = NSApplication.shared.dockTile) {
    self.tile = tile
  }

  /// `done` of `total` images are ready. Pass `total == 0` to clear.
  public func update(done: Int, total: Int) {
    guard total > 0 else {
      clear()
      return
    }
    set(Self.fraction(done: done, total: total))
  }

  /// Clamped to 0...1.
  nonisolated static func fraction(done: Int, total: Int) -> Double {
    guard total > 0 else { return 0 }
    return min(1, max(0, Double(done) / Double(total)))
  }

  /// Removes the bar. When `bounce` is true and the app is not active, the icon bounces once.
  public func finish(bounce: Bool = true) {
    clear()
    if bounce && !NSApplication.shared.isActive {
      NSApplication.shared.requestUserAttention(.informationalRequest)
    }
  }

  public func clear() {
    fraction = nil
    view = nil
    tile.contentView = nil
    tile.display()
  }

  private func set(_ value: Double) {
    fraction = value
    if view == nil {
      let progressView = DockProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
      view = progressView
      tile.contentView = progressView
    }
    view?.fraction = value
    tile.display()
  }
}

/// The app icon with a bar along the bottom.
private final class DockProgressView: NSView {
  var fraction: Double = 0 {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSApplication.shared.applicationIconImage.draw(in: bounds)
    let track = NSRect(x: 8, y: 6, width: bounds.width - 16, height: 12)
    let radius = track.height / 2
    NSColor.windowBackgroundColor.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
    let inner = track.insetBy(dx: 2, dy: 2)
    let filled = NSRect(x: inner.minX, y: inner.minY, width: inner.width * fraction, height: inner.height)
    NSColor.controlAccentColor.setFill()
    NSBezierPath(roundedRect: filled, xRadius: inner.height / 2, yRadius: inner.height / 2).fill()
  }
}
