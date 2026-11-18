import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SSCore
import UniformTypeIdentifiers

/// Turns a web view snapshot into a PNG of exactly the template's size, in sRGB.
///
/// `WKWebView.takeSnapshot` returns an image in points: on a Retina display its bitmap is 2× (or
/// more) the requested size. The bitmap is redrawn into an sRGB context of exactly `width × height`
/// pixels, encoded as PNG, and the PNG is decoded again to check its pixel size. Any mismatch throws.
public enum ExactImage {
  /// The sRGB colour space every output image uses.
  static let sRGB: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

  /// The largest bitmap among the image's representations, as a `CGImage`. A snapshot `NSImage` is
  /// sized in points; its representation holds the real pixels.
  public static func largestBitmap(of image: NSImage) -> CGImage? {
    let best = image.representations.max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
    if let best, let cgImage = best.cgImage(forProposedRect: nil, context: nil, hints: nil) { return cgImage }
    var rect = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
  }

  /// Redraws `image` into an opaque sRGB bitmap of exactly `width × height` pixels. A larger image
  /// (a 2× snapshot) is scaled down with high-quality interpolation; colours are converted to sRGB
  /// when the source uses another colour space.
  public static func redraw(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw AppError.render(message: RenderStrings.snapshotFailed) }
    context.interpolationQuality = (image.width == width && image.height == height) ? .none : .high
    context.setFillColor(CGColor(colorSpace: sRGB, components: [1, 1, 1, 1]) ?? CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let result = context.makeImage() else { throw AppError.render(message: RenderStrings.snapshotFailed) }
    guard result.width == width, result.height == height else {
      throw AppError.render(
        message: RenderStrings.wrongPixelSize(
          width: result.width, height: result.height, expectedWidth: width, expectedHeight: height))
    }
    return result
  }

  /// Encodes `image` as PNG (with its sRGB profile).
  public static func pngData(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { throw AppError.render(message: RenderStrings.pngEncodingFailed) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw AppError.render(message: RenderStrings.pngEncodingFailed)
    }
    return data as Data
  }

  /// Pixel size of an encoded image, read back from its data.
  public static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (width, height)
  }

  /// Throws unless `data` decodes to an image of exactly `width × height` pixels.
  public static func verifyPixelSize(of data: Data, width: Int, height: Int) throws {
    guard let size = pixelSize(of: data) else { throw AppError.render(message: RenderStrings.pngEncodingFailed) }
    guard size.width == width, size.height == height else {
      throw AppError.render(
        message: RenderStrings.wrongPixelSize(
          width: size.width, height: size.height, expectedWidth: width, expectedHeight: height))
    }
  }

  /// Redraw, encode and verify in one step: the PNG of `image` at exactly `width × height` pixels.
  public static func exactPNG(from image: CGImage, width: Int, height: Int) throws -> Data {
    let exact = try redraw(image, width: width, height: height)
    let data = try pngData(exact)
    try verifyPixelSize(of: data, width: width, height: height)
    return data
  }

  /// Same as `exactPNG(from:width:height:)` for a snapshot `NSImage`.
  public static func exactPNG(from image: NSImage, width: Int, height: Int) throws -> Data {
    guard let bitmap = largestBitmap(of: image) else { throw AppError.render(message: RenderStrings.snapshotFailed) }
    return try exactPNG(from: bitmap, width: width, height: height)
  }
}
