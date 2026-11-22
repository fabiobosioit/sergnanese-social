import AppKit
import Foundation
import ImageIO
import SSCore
import Testing
import UniformTypeIdentifiers

@testable import SSData

@Suite struct LogoStoreTests {
  private func jpeg(width: Int, height: Int) throws -> Data {
    let context = try #require(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(red: 0.8, green: 0.2, blue: 0.15, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
  }

  private func pixelSize(of url: URL) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    return (
      try #require(properties[kCGImagePropertyPixelWidth] as? Int),
      try #require(properties[kCGImagePropertyPixelHeight] as? Int)
    )
  }

  private func assertPNG(_ store: LogoFileStore, _ name: String) throws -> (width: Int, height: Int) {
    #expect(name.hasSuffix(".png"))
    let url = store.url(for: name)
    let header = try Data(contentsOf: url).prefix(4)
    #expect(Array(header) == [0x89, 0x50, 0x4E, 0x47])
    let size = try pixelSize(of: url)
    #expect(size.width <= 1024 && size.height <= 1024)
    return size
  }

  @Test func largeJPEGBecomesPNGUnder1024() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = LogoFileStore(folder: folder.appendingPathComponent("logos"))
    let source = folder.appendingPathComponent("big.jpg")
    try jpeg(width: 3000, height: 2000).write(to: source)
    let name = try await store.importLogo(from: source, replacing: nil)
    let size = try assertPNG(store, name)
    #expect(size.width == 1024)
    #expect(size.height > 600 && size.height < 700)
  }

  @Test func svgBecomesPNGUnder1024() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = LogoFileStore(folder: folder)
    let svg = """
      <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">
        <rect width="200" height="100" fill="#cf3326"/><circle cx="100" cy="50" r="30" fill="white"/>
      </svg>
      """
    let name = try await store.importLogo(data: Data(svg.utf8), replacing: nil)
    let size = try assertPNG(store, name)
    #expect(size.width == 1024 && size.height == 512)
  }

  @Test func smallImageIsNotUpscaled() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = LogoFileStore(folder: folder)
    let name = try await store.importLogo(data: jpeg(width: 200, height: 200), replacing: nil)
    let size = try assertPNG(store, name)
    #expect(size.width == 200 && size.height == 200)
  }

  @Test func replacingRemovesTheOldFileAndNamesAreGenerated() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = LogoFileStore(folder: folder)
    let data = try jpeg(width: 64, height: 64)
    let first = try await store.importLogo(data: data, replacing: nil)
    let second = try await store.importLogo(data: data, replacing: first)
    #expect(first != second)
    #expect(!FileManager.default.fileExists(atPath: store.url(for: first).path))
    #expect(FileManager.default.fileExists(atPath: store.url(for: second).path))
    try store.remove(fileName: second)
    try store.remove(fileName: second)  // already gone: not an error
    #expect(!FileManager.default.fileExists(atPath: store.url(for: second).path))
  }

  @Test func rejectsOversizedAndUnsupportedData() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = LogoFileStore(folder: folder)
    do {
      _ = try await store.importLogo(data: Data(count: LogoFileStore.maxBytes + 1), replacing: nil)
      Issue.record("expected error")
    } catch AppError.validation(let field, _) {
      #expect(field == .logo)
    }
    do {
      _ = try await store.importLogo(data: Data("not an image".utf8), replacing: nil)
      Issue.record("expected error")
    } catch AppError.validation(let field, _) {
      #expect(field == .logo)
    }
    let missing = folder.appendingPathComponent("missing.png")
    await #expect(throws: AppError.self) { _ = try await store.importLogo(from: missing, replacing: nil) }
    let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    #expect(leftovers.isEmpty)
  }

  @Test func namedImportIsAPNGReplacesSameNameAndRemovesReplaced() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = LogoFileStore(folder: folder)
    let old = try await store.importLogo(data: jpeg(width: 100, height: 100), replacing: nil)
    let name = try await store.importLogo(data: jpeg(width: 3000, height: 2000), fileName: "917410.png", replacing: old)
    #expect(name == "917410.png")
    let size = try assertPNG(store, name)
    #expect(size.width == 1024)
    #expect(!FileManager.default.fileExists(atPath: store.url(for: old).path))

    let again = try await store.importLogo(
      data: jpeg(width: 200, height: 200), fileName: "917410.png", replacing: "917410.png")
    #expect(again == "917410.png")
    #expect(try assertPNG(store, again).width == 200)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["917410.png"])
  }

  @Test func namedImportRefusesBadNamesAndWritesNothing() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = LogoFileStore(folder: folder.appendingPathComponent("logos"))
    for bad in ["../x.png", "917410.jpg", "abc.png"] {
      do {
        _ = try await store.importLogo(data: jpeg(width: 50, height: 50), fileName: bad, replacing: nil)
        Issue.record("expected \(bad) to be refused")
      } catch AppError.validation(let field, _) {
        #expect(field == .logo)
      }
    }
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("logos").path))
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("x.png").path))
  }
}
