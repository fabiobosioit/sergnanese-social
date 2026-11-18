import Foundation
import SSCore
import Synchronization

/// Templates installed as folders in `AppPaths.templates` (`<data folder>/templates/<id>/`).
///
/// Built-ins come from `AppPaths.builtinTemplates` (`Resources/Templates/`): a template is a built-in
/// when a bundled template has the same id. Built-ins cannot be removed, only restored; they can be
/// replaced by an import with the same id (the replacement keeps the built-in flag, and
/// `restoreBuiltin` puts the bundled copy back).
///
/// Changes to the folder are serialised by a lock and installed through a staging folder, so a
/// failed import never leaves a half-copied template behind.
public final class FileTemplateStore: TemplateStore {
  public let paths: AppPaths
  private let lock = Mutex(())

  public init(paths: AppPaths) {
    self.paths = paths
  }

  // MARK: TemplateStore

  public func installBuiltins() throws {
    try lock.withLock { _ in
      try createTemplatesFolder()
      for builtin in bundledTemplates() {
        let installed = folder(for: builtin.manifest.id)
        if let current = try? readManifest(in: installed),
          compareTemplateVersions(current.version, builtin.manifest.version) != .orderedAscending
        {
          continue
        }
        try put(builtin, id: builtin.manifest.id)
      }
    }
  }

  public func list() throws -> [InstalledTemplate] {
    let builtinIDs = Set(bundledTemplates().map(\.manifest.id))
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: paths.templates.path) else { return [] }
    let children: [URL]
    do {
      children = try fileManager.contentsOfDirectory(
        at: paths.templates, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    } catch {
      throw AppError.io(message: TemplateStrings.cannotRead(paths.templates.path))
    }
    let templates = children.compactMap { child -> InstalledTemplate? in
      let id = child.lastPathComponent
      guard isValidTemplateID(id), let manifest = try? readManifest(in: child), manifest.id == id else { return nil }
      return InstalledTemplate(manifest: manifest, folder: child, isBuiltin: builtinIDs.contains(id))
    }
    return templates.sorted { lhs, rhs in
      let order = lhs.manifest.name.compare(rhs.manifest.name, options: [.caseInsensitive, .diacriticInsensitive])
      return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
    }
  }

  public func get(id: String) throws -> InstalledTemplate {
    guard isValidTemplateID(id) else { throw AppError.notFound }
    let templateFolder = folder(for: id)
    guard let manifest = try? readManifest(in: templateFolder), manifest.id == id else { throw AppError.notFound }
    let isBuiltin = bundledTemplates().contains { $0.manifest.id == id }
    return InstalledTemplate(manifest: manifest, folder: templateFolder, isBuiltin: isBuiltin)
  }

  public func install(from url: URL, replace: Bool) throws -> TemplateInstallOutcome {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return .invalid(problems: [TemplateStrings.notFolderOrZip])
    }
    if isDirectory.boolValue {
      return try install(inspecting: url, replace: replace)
    }
    guard url.pathExtension.lowercased() == "zip" else { return .invalid(problems: [TemplateStrings.notFolderOrZip]) }
    let extraction = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SergnaneseTemplateImport-\(UUID().uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: extraction, withIntermediateDirectories: true)
    } catch {
      throw AppError.io(message: TemplateStrings.cannotWrite(extraction.path))
    }
    defer { try? FileManager.default.removeItem(at: extraction) }
    let problems = SafeUnzip.extract(url, to: extraction)
    guard problems.isEmpty else { return .invalid(problems: problems) }
    return try install(inspecting: extraction, replace: replace)
  }

  public func remove(id: String) throws {
    try lock.withLock { _ in
      let template = try get(id: id)
      guard !template.isBuiltin else { throw AppError.conflict(message: TemplateStrings.builtinCannotBeRemoved) }
      do {
        try FileManager.default.removeItem(at: template.folder)
      } catch {
        throw AppError.io(message: TemplateStrings.cannotWrite(template.folder.path))
      }
    }
  }

  public func restoreBuiltin(id: String) throws -> InstalledTemplate {
    try lock.withLock { _ in
      guard let builtin = bundledTemplates().first(where: { $0.manifest.id == id }) else { throw AppError.notFound }
      try createTemplatesFolder()
      try put(builtin, id: id)
      return InstalledTemplate(manifest: builtin.manifest, folder: folder(for: id), isBuiltin: true)
    }
  }

  // MARK: Helpers

  private func install(inspecting folder: URL, replace: Bool) throws -> TemplateInstallOutcome {
    let template: InspectedTemplate
    switch TemplateInspector.inspect(folder: folder) {
    case .failure(let problems): return .invalid(problems: problems.messages)
    case .success(let inspected): template = inspected
    }
    return try lock.withLock { _ in
      let id = template.manifest.id
      if !replace, let existing = try? get(id: id) { return .alreadyExists(existing) }
      try createTemplatesFolder()
      try put(template, id: id)
      return .installed(try get(id: id))
    }
  }

  /// Copies `template` to `templates/<id>` through a staging folder, replacing any existing copy.
  private func put(_ template: InspectedTemplate, id: String) throws {
    let fileManager = FileManager.default
    let staging = paths.templates.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: staging) }
    try TemplateInspector.copy(template, to: staging)
    let destination = folder(for: id)
    do {
      if fileManager.fileExists(atPath: destination.path) {
        _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
      } else {
        try fileManager.moveItem(at: staging, to: destination)
      }
    } catch {
      throw AppError.io(message: TemplateStrings.cannotWrite(destination.path))
    }
  }

  /// Bundled templates that pass inspection, by id (the first folder wins on a duplicate id).
  private func bundledTemplates() -> [InspectedTemplate] {
    guard
      let children = try? FileManager.default.contentsOfDirectory(
        at: paths.builtinTemplates, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    else { return [] }
    var seen = Set<String>()
    return children.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { child in
      guard TemplateInspector.isRegularFile(child.appendingPathComponent("manifest.json")),
        case .success(let template) = TemplateInspector.inspect(folder: child),
        seen.insert(template.manifest.id).inserted
      else { return nil }
      return template
    }
  }

  private func folder(for id: String) -> URL {
    paths.templates.appendingPathComponent(id, isDirectory: true)
  }

  private func readManifest(in folder: URL) throws -> TemplateManifest {
    let data = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
    return try TemplateManifest.decode(from: data)
  }

  private func createTemplatesFolder() throws {
    do {
      try FileManager.default.createDirectory(at: paths.templates, withIntermediateDirectories: true)
    } catch {
      throw AppError.io(message: TemplateStrings.cannotWrite(paths.templates.path))
    }
  }
}
