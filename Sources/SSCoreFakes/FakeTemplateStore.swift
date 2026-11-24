import Foundation
import SSCore
import Synchronization

/// An in-memory template list. Each template gets a folder under `folder` holding its
/// `manifest.json` (so "Mostra nel Finder" has something to show). `install(from:replace:)` validates
/// a folder's `manifest.json` with `TemplateManifest.decode(from:)` and requires `template.html`; for
/// a `.zip` it checks the zip signature and installs a template made up from the file name, so the
/// import can be demonstrated under `--mock`. Anything else is `.invalid`.
public final class FakeTemplateStore: TemplateStore {
  /// The four built-ins of v0.1.0 and the results recap of T4.5, with the limits used throughout the
  /// fixtures.
  public static let builtinManifests: [TemplateManifest] = [
    TemplateManifest(
      id: "post-prematch", name: "Post · Pre-partita", version: "1.0.0", format: .post, width: 1080, height: 1350,
      kind: .single, purpose: .prematch, requires: [.time, .venue],
      limits: TemplateLimits(teamName: 16, venue: 14, category: 22)),
    TemplateManifest(
      id: "story-programme", name: "Story · Programma pre-partita", version: "1.0.0", format: .story, width: 1080,
      height: 1920, kind: .list, purpose: .programme, pageSize: 10, requires: [.time, .venue],
      limits: TemplateLimits(teamName: 22, venue: 14, category: 16)),
    TemplateManifest(
      id: "story-halftime", name: "Story · Intervallo", version: "1.0.0", format: .story, width: 1080, height: 1920,
      kind: .single, purpose: .halftime, requires: [.halfTime], limits: TemplateLimits(teamName: 16, category: 22)),
    TemplateManifest(
      id: "story-fulltime", name: "Story · Risultato finale", version: "1.0.0", format: .story, width: 1080,
      height: 1920, kind: .single, purpose: .fulltime, requires: [.score],
      limits: TemplateLimits(teamName: 16, category: 22)),
    TemplateManifest(
      id: "story-results", name: "Story · Risultati del weekend", version: "1.0.0", format: .story, width: 1080,
      height: 1920, kind: .list, purpose: .fulltime, pageSize: 10, requires: [.score],
      limits: TemplateLimits(teamName: 22, category: 16)),
  ]

  public let folder: URL
  private let templates: Mutex<[String: InstalledTemplate]>

  /// `installBuiltins()` is called here, so the list starts with the five built-ins.
  public init(folder: URL) {
    self.folder = folder
    self.templates = Mutex([:])
    try? installBuiltins()
  }

  public func installBuiltins() throws {
    for manifest in Self.builtinManifests {
      let existing = templates.withLock { $0[manifest.id] }
      if let existing, existing.isBuiltin,
        compareTemplateVersions(existing.manifest.version, manifest.version) != .orderedAscending
      {
        continue
      }
      try put(manifest, isBuiltin: true)
    }
  }

  public func list() throws -> [InstalledTemplate] {
    templates.withLock { Array($0.values) }.sorted { lhs, rhs in
      lhs.manifest.name == rhs.manifest.name ? lhs.id < rhs.id : lhs.manifest.name < rhs.manifest.name
    }
  }

  public func get(id: String) throws -> InstalledTemplate {
    guard let template = templates.withLock({ $0[id] }) else { throw AppError.notFound }
    return template
  }

  public func install(from url: URL, replace: Bool) throws -> TemplateInstallOutcome {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return .invalid(problems: [FakeStrings.notFolderOrZip])
    }
    if !isDirectory.boolValue {
      guard url.pathExtension.lowercased() == "zip" else { return .invalid(problems: [FakeStrings.notFolderOrZip]) }
      guard let manifest = Self.manifest(forZipAt: url) else { return .invalid(problems: [FakeStrings.zipNotValid]) }
      if let existing = templates.withLock({ $0[manifest.id] }), !replace { return .alreadyExists(existing) }
      return .installed(try put(manifest, isBuiltin: false))
    }
    let manifestURL = url.appendingPathComponent("manifest.json")
    guard let data = try? Data(contentsOf: manifestURL) else {
      return .invalid(problems: [FakeStrings.manifestMissing])
    }
    let manifest: TemplateManifest
    do {
      manifest = try TemplateManifest.decode(from: data)
    } catch AppError.template(let problems) {
      return .invalid(problems: problems)
    }
    guard FileManager.default.fileExists(atPath: url.appendingPathComponent("template.html").path) else {
      return .invalid(problems: [FakeStrings.templateHTMLMissing])
    }
    if let existing = templates.withLock({ $0[manifest.id] }), !replace { return .alreadyExists(existing) }
    return .installed(try put(manifest, isBuiltin: false))
  }

  public func remove(id: String) throws {
    let template = try get(id: id)
    guard !template.isBuiltin else { throw AppError.conflict(message: FakeStrings.builtinCannotBeRemoved) }
    _ = templates.withLock { $0.removeValue(forKey: id) }
    try? FileManager.default.removeItem(at: template.folder)
  }

  public func restoreBuiltin(id: String) throws -> InstalledTemplate {
    guard let manifest = Self.builtinManifests.first(where: { $0.id == id }) else { throw AppError.notFound }
    return try put(manifest, isBuiltin: true)
  }

  /// The fake does not unzip. For a file that really is a zip (`PK\u{3}\u{4}` signature) it makes up
  /// a plausible manifest from the file name: id = slug of the name, "story" in the name → story
  /// 1080×1920, "programm" in the name → list template with `pageSize` 10. `nil` when not a zip.
  static func manifest(forZipAt url: URL) -> TemplateManifest? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let head = try? handle.read(upToCount: 4), head == Data([0x50, 0x4B, 0x03, 0x04]) else { return nil }
    let name = url.deletingPathExtension().lastPathComponent
    var id = String(slug(name).prefix(64))
    while id.hasSuffix("-") { id.removeLast() }
    if id.isEmpty { id = "template-importato" }
    let key = searchKey(name)
    let isStory = key.contains("story")
    let isList = key.contains("programm")
    return TemplateManifest(
      id: id, name: name, version: "1.0.0", format: isStory ? .story : .post, width: 1080,
      height: isStory ? 1920 : 1350, kind: isList ? .list : .single, purpose: isList ? .programme : .other,
      pageSize: isList ? 10 : nil, limits: TemplateLimits(teamName: 16, venue: 14, category: 22))
  }

  @discardableResult
  private func put(_ manifest: TemplateManifest, isBuiltin: Bool) throws -> InstalledTemplate {
    let templateFolder = folder.appendingPathComponent(manifest.id, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: templateFolder, withIntermediateDirectories: true)
      try Fixtures.makeEncoder().encode(manifest).write(to: templateFolder.appendingPathComponent("manifest.json"))
    } catch {
      throw AppError.io(message: FakeStrings.cannotWrite(templateFolder.path))
    }
    let template = InstalledTemplate(manifest: manifest, folder: templateFolder, isBuiltin: isBuiltin)
    templates.withLock { $0[manifest.id] = template }
    return template
  }
}
