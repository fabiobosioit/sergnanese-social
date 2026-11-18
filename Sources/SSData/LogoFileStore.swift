import AppKit
import Foundation
import ImageIO
import SSCore
import UniformTypeIdentifiers

/// `LogoStore` on the logos folder. Every logo is converted to a PNG of at most 1024 px and stored
/// under a generated `<uuid>.png` name.
public struct LogoFileStore: LogoStore {
  public let folder: URL

  public static let maxBytes = 5 * 1024 * 1024
  public static let maxPixels = 1024

  public init(folder: URL) { self.folder = folder }

  public func importLogo(from url: URL, replacing: String?) async throws -> String {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw AppError.io(message: DataStrings.cannotRead(url.path))
    }
    return try store(data, replacing: replacing)
  }

  public func importLogo(data: Data, replacing: String?) async throws -> String {
    try store(data, replacing: replacing)
  }

  public func remove(fileName: String) throws {
    // A stored name never contains a path; refuse anything that does, so a bad value cannot reach
    // outside the logos folder.
    guard fileName == (fileName as NSString).lastPathComponent else { return }
    let target = url(for: fileName)
    guard FileManager.default.fileExists(atPath: target.path) else { return }
    do {
      try FileManager.default.removeItem(at: target)
    } catch {
      throw AppError.io(message: DataStrings.cannotWrite(target.path))
    }
  }

  public func url(for fileName: String) -> URL { folder.appendingPathComponent(fileName) }

  // MARK: Conversion

  private func store(_ data: Data, replacing: String?) throws -> String {
    guard data.count <= Self.maxBytes else {
      throw AppError.validation(field: .logo, message: DataStrings.logoTooLarge)
    }
    guard let png = Self.pngData(from: data) else {
      throw AppError.validation(field: .logo, message: DataStrings.logoNotImage)
    }
    let name = "\(newEntityID().lowercased()).png"
    let target = url(for: name)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try png.write(to: target, options: .atomic)
    } catch {
      throw AppError.io(message: DataStrings.cannotWrite(target.path))
    }
    if let replacing, replacing != name { try remove(fileName: replacing) }
    return name
  }

  /// PNG bytes of at most `maxPixels` on the longest side, or `nil` when `data` is not a supported image.
  static func pngData(from data: Data) -> Data? {
    if isSVG(data) { return svgPNG(from: data) }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
    else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxPixels),
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return encodePNG(image)
  }

  private static func encodePNG(_ image: CGImage) -> Data? {
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }

  private static func isSVG(_ data: Data) -> Bool {
    String(decoding: data.prefix(1024), as: UTF8.self).contains("<svg")
  }

  /// Rasterises an SVG with the system's SVG support, longest side `maxPixels`, transparent background.
  private static func svgPNG(from data: Data) -> Data? {
    guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
    let scale = CGFloat(maxPixels) / max(image.size.width, image.size.height)
    let pixelsWide = max(1, Int((image.size.width * scale).rounded()))
    let pixelsHigh = max(1, Int((image.size.height * scale).rounded()))
    guard
      let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: representation)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
    NSGraphicsContext.restoreGraphicsState()
    return representation.representation(using: .png, properties: [:])
  }
}
