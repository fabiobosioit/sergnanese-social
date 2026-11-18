import AppKit
import ImageIO
import SwiftUI

/// Small cached thumbnails of image files, decoded off the main thread with ImageIO.
enum ThumbnailLoader {
  // NSCache is thread-safe; the box only exists to hold it in a global.
  private final class Cache: @unchecked Sendable {  // safe: NSCache does its own locking
    let storage = NSCache<NSString, NSImage>()
  }
  private static let cache = Cache()

  static func key(_ url: URL, maxPixel: Int) -> NSString { "\(url.path)@\(maxPixel)" as NSString }

  @MainActor
  static func cached(_ url: URL, maxPixel: Int) -> NSImage? {
    cache.storage.object(forKey: key(url, maxPixel: maxPixel))
  }

  /// Decodes at most `maxPixel` pixels on the longest side. Returns `nil` when the file is missing or
  /// is not an image.
  static func load(_ url: URL, maxPixel: Int) async -> NSImage? {
    let cacheKey = key(url, maxPixel: maxPixel)
    if let hit = cache.storage.object(forKey: cacheKey) { return hit }
    let image: NSImage? = await Task.detached(priority: .userInitiated) {
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
      ]
      guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
      return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }.value
    if let image { cache.storage.setObject(image, forKey: cacheKey) }
    return image
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
