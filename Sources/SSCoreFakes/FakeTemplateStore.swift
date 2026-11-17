import Foundation
import SSCore
import Synchronization

/// An in-memory template list. Each template gets a folder under `folder` holding its
/// `manifest.json` (so "Mostra nel Finder" has something to show). `install(from:replace:)` accepts
/// folders only and validates their `manifest.json` with `TemplateManifest.decode(from:)`.
public final class FakeTemplateStore: TemplateStore {
  /// The four built-ins of v0.1.0, with the limits used throughout the fixtures.
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
  ]

  public let folder: URL
  private let templates: Mutex<[String: InstalledTemplate]>

  /// `installBuiltins()` is called here, so the list starts with the four built-ins.
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
    if url.pathExtension.lowercased() == "zip" { return .invalid(problems: [FakeStrings.zipNotSupported]) }
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
