import AppKit
import ImageIO
import SwiftUI

/// Small cached thumbnails of image files, decoded off the main thread with ImageIO.
///
/// Only a `CGImage` (Sendable) crosses the actor boundary; the `NSImage` is created and cached on the
/// main actor, because `NSImage` is not `Sendable` in older SDKs.
enum ThumbnailLoader {
  @MainActor private static let cache = NSCache<NSString, NSImage>()

  static func key(_ url: URL, maxPixel: Int) -> NSString { "\(url.path)@\(maxPixel)" as NSString }

  @MainActor
  static func cached(_ url: URL, maxPixel: Int) -> NSImage? {
    cache.object(forKey: key(url, maxPixel: maxPixel))
  }

  /// Decodes at most `maxPixel` pixels on the longest side. Returns `nil` when the file is missing or
  /// is not an image.
  @MainActor
  static func load(_ url: URL, maxPixel: Int) async -> NSImage? {
    let cacheKey = key(url, maxPixel: maxPixel)
    if let hit = cache.object(forKey: cacheKey) { return hit }
    let decoded: CGImage? = await Task.detached(priority: .userInitiated) {
      decode(url, maxPixel: maxPixel)
    }.value
    guard let cg = decoded else { return nil }
    let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    cache.setObject(image, forKey: cacheKey)
    return image
  }

  private nonisolated static func decode(_ url: URL, maxPixel: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }
}

/// Shows an image file scaled to fit, with a placeholder while it loads and a "file not found" mark
/// when it cannot be read.
struct ThumbnailView: View {
  let url: URL
  let maxPixel: Int
  @ViewState private var image: NSImage?
  @ViewState private var failed = false

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
      } else if failed {
        VStack(spacing: 4) {
          Image(systemName: "photo.badge.exclamationmark")
            .font(.title2)
          Text(AppStrings.Gallery.missingFile)
            .font(.caption)
        }
        .foregroundStyle(.secondary)
      } else {
        ProgressView().controlSize(.small)
      }
    }
    .task(id: url) {
      failed = false
      if let hit = ThumbnailLoader.cached(url, maxPixel: maxPixel) {
        image = hit
        return
      }
      image = nil
      let loaded = await ThumbnailLoader.load(url, maxPixel: maxPixel)
      image = loaded
      failed = loaded == nil
    }
  }
}
