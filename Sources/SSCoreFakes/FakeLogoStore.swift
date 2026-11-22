import Foundation
import SSCore

/// Stores logos in a folder without converting them: the bytes are written as given under a new
/// `<uuid>.png` name, or under the caller's `<digits>.png` name. It checks the 5 MB limit and that the
/// data looks like a supported image.
public struct FakeLogoStore: LogoStore {
  public let folder: URL
  public static let maxBytes = 5 * 1024 * 1024

  public init(folder: URL) { self.folder = folder }

  public func importLogo(from url: URL, replacing: String?) async throws -> String {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw AppError.io(message: FakeStrings.cannotRead(url.path))
    }
    return try store(data, replacing: replacing)
  }

  public func importLogo(data: Data, replacing: String?) async throws -> String {
    try store(data, replacing: replacing)
  }

  public func importLogo(data: Data, fileName: String, replacing: String?) async throws -> String {
    guard isValidImportedLogoFileName(fileName) else {
      throw AppError.validation(field: .logo, message: FakeStrings.logoBadName(fileName))
    }
    return try store(data, as: fileName, replacing: replacing)
  }

  public func remove(fileName: String) throws {
    let url = url(for: fileName)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      throw AppError.io(message: FakeStrings.cannotWrite(url.path))
    }
  }

  public func url(for fileName: String) -> URL { folder.appendingPathComponent(fileName) }

  private func store(_ data: Data, as fileName: String? = nil, replacing: String?) throws -> String {
    guard data.count <= Self.maxBytes else {
      throw AppError.validation(field: .logo, message: FakeStrings.logoTooLarge)
    }
    guard Self.looksLikeImage(data) else {
      throw AppError.validation(field: .logo, message: FakeStrings.logoNotImage)
    }
    let name = fileName ?? "\(newEntityID().lowercased()).png"
    let target = url(for: name)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: target, options: .atomic)
    } catch {
      throw AppError.io(message: FakeStrings.cannotWrite(target.path))
    }
    if let replacing, replacing != name { try remove(fileName: replacing) }
    return name
  }

  /// PNG, JPEG, WebP, HEIC or SVG by signature.
  static func looksLikeImage(_ data: Data) -> Bool {
    let bytes = [UInt8](data.prefix(32))
    func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
      bytes.count >= offset + prefix.count && Array(bytes[offset..<offset + prefix.count]) == prefix
    }
    if starts([0x89, 0x50, 0x4E, 0x47]) || starts([0xFF, 0xD8, 0xFF]) { return true }
    if starts(Array("RIFF".utf8)) && starts(Array("WEBP".utf8), at: 8) { return true }
    if starts(Array("ftyp".utf8), at: 4) { return true }
    let head = String(decoding: data.prefix(512), as: UTF8.self)
    return head.contains("<svg")
  }
}
