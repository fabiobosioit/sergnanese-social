import AppKit
import CoreGraphics
import Foundation
import SSCore
import Testing

@testable import SSRender

/// The redraw step on synthetic snapshots, without WebKit.
@Suite struct ExactImageTests {
  /// A `scale`× image of a `width × height` point page: accent colour with a white top-left quarter.
  func synthetic(width: Int, height: Int, scale: Int, space: CGColorSpace? = nil) throws -> CGImage {
    let colorSpace = space ?? CGColorSpace(name: CGColorSpace.sRGB)!
    let context = try #require(
      CGContext(
        data: nil, width: width * scale, height: height * scale, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    context.setFillColor(CGColor(colorSpace: srgb, components: [0xCF / 255.0, 0x33 / 255.0, 0x26 / 255.0, 1])!)
    context.fill(CGRect(x: 0, y: 0, width: width * scale, height: height * scale))
    context.setFillColor(CGColor(colorSpace: srgb, components: [1, 1, 1, 1])!)
    context.fill(CGRect(x: 0, y: height * scale / 2, width: width * scale / 2, height: height * scale / 2))
    return try #require(context.makeImage())
  }

  @Test(arguments: [1, 2, 3])
  func redrawsToExactSize(scale: Int) throws {
    let image = try synthetic(width: 1080, height: 1350, scale: scale)
    let png = try ExactImage.exactPNG(from: image, width: 1080, height: 1350)
    let size = try #require(ExactImage.pixelSize(of: png))
    #expect(size.width == 1080 && size.height == 1350)
    let pixels = try Pixels(png: png)
    #expect(pixels.hex(x: 810, y: 1000) == "#CF3326")
    #expect(pixels.hex(x: 10, y: 10) == "#FFFFFF")  // top-left quarter stays at the top
    #expect(pixels.hex(x: 1070, y: 1340) == "#CF3326")
  }

  @Test func picksTheLargestRepresentationOfASnapshot() throws {
    // A snapshot NSImage is sized in points with a 2× bitmap inside.
    let bitmap = try synthetic(width: 200, height: 250, scale: 2)
    let image = NSImage(cgImage: bitmap, size: NSSize(width: 200, height: 250))
    let best = try #require(ExactImage.largestBitmap(of: image))
    #expect(best.width == 400 && best.height == 500)
    let png = try ExactImage.exactPNG(from: image, width: 200, height: 250)
    #expect(ExactImage.pixelSize(of: png)?.width == 200)
    #expect(ExactImage.pixelSize(of: png)?.height == 250)
  }

  @Test func convertsOtherColourSpacesToSRGB() throws {
    let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
    let image = try synthetic(width: 100, height: 100, scale: 2, space: p3)
    let png = try ExactImage.exactPNG(from: image, width: 100, height: 100)
    #expect(try Pixels(png: png).hex(x: 75, y: 75) == "#CF3326")
  }

  @Test func verifyRejectsWrongPixelSize() throws {
    let png = try ExactImage.pngData(try synthetic(width: 50, height: 60, scale: 2))
    #expect(throws: AppError.self) { try ExactImage.verifyPixelSize(of: png, width: 50, height: 60) }
    try ExactImage.verifyPixelSize(of: png, width: 100, height: 120)
    #expect(throws: AppError.self) { try ExactImage.verifyPixelSize(of: Data("x".utf8), width: 1, height: 1) }
  }
}

@Suite struct PageDocumentTests {
  @Test func insertsHeaderAfterDoctype() {
    let html = "\n<!DOCTYPE html>\n<html><head></head><body></body></html>"
    let prepared = PageDocument.prepare(html)
    #expect(prepared.hasPrefix("\n<!DOCTYPE html>" + PageDocument.header))
    #expect(prepared.hasSuffix("<html><head></head><body></body></html>"))
  }

  @Test func insertsHeaderFirstWithoutDoctype() {
    #expect(PageDocument.prepare("<div></div>") == PageDocument.header + "<div></div>")
  }
}
