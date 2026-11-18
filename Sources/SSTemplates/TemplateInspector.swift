import Foundation
import SSCore

/// Limits applied to every imported template (folder or zip).
public enum TemplateImportLimits {
  /// Total size of the template's files.
  public static let maxTotalBytes: Int64 = 20 * 1024 * 1024
  /// Number of files (directories are not counted).
  public static let maxFiles = 200
  /// File types a template may contain, by lower-case extension.
  public static let allowedExtensions: Set<String> = [
    "html", "htm", "css", "js", "mjs", "json", "png", "jpg", "jpeg", "gif", "webp", "avif", "svg", "woff", "woff2",
    "ttf", "otf", "txt", "md",
  ]

  static var maxMegabytes: Int { Int(maxTotalBytes / 1024 / 1024) }
}

/// A template folder that passed every check.
struct InspectedTemplate {
  var manifest: TemplateManifest
  /// The folder holding `manifest.json` (the given folder or its only subfolder with one).
  var root: URL
  /// Files to copy, relative to `root`, with `/` separators. Hidden files and `__MACOSX` are left out.
  var files: [String]
}

/// Checks a template folder on disk: manifest, `template.html`, file types, symbolic links, size and
/// file count. Every problem is collected, one Italian sentence each.
enum TemplateInspector {
  /// `true` for names that are skipped silently: hidden files (`.DS_Store`) and macOS zip leftovers.
  static func isIgnored(_ name: String) -> Bool {
    name.hasPrefix(".") || name == "__MACOSX"
  }

  /// The folder holding `manifest.json`: `folder` itself, or its only visible subfolder that has one.
  static func locateRoot(in folder: URL) -> URL? {
    let fileManager = FileManager.default
    if isRegularFile(folder.appendingPathComponent("manifest.json")) { return folder }
    guard
      let children = try? fileManager.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
    else { return nil }
    let candidates = children.filter { child in
      guard !isIgnored(child.lastPathComponent),
        let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
        values.isDirectory == true, values.isSymbolicLink != true
      else { return false }
      return isRegularFile(child.appendingPathComponent("manifest.json"))
    }
    return candidates.count == 1 ? candidates[0] : nil
  }

  /// Inspects `folder` (the template root is located inside it). Returns the template or the
  /// problems found.
  static func inspect(folder: URL) -> Result<InspectedTemplate, TemplateProblems> {
    guard let root = locateRoot(in: folder) else {
      return .failure(TemplateProblems([TemplateStrings.manifestMissing]))
    }
    var problems: [String] = []
    var files: [String] = []
    var totalBytes: Int64 = 0
    walk(root, relative: "", problems: &problems, files: &files, totalBytes: &totalBytes)
    if files.count > TemplateImportLimits.maxFiles {
      problems.append(TemplateStrings.tooManyFiles(TemplateImportLimits.maxFiles))
    }
    if totalBytes > TemplateImportLimits.maxTotalBytes {
      problems.append(TemplateStrings.tooLarge(megabytes: TemplateImportLimits.maxMegabytes))
    }

    var manifest: TemplateManifest?
    if let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")) {
      do {
        manifest = try TemplateManifest.decode(from: data)
      } catch AppError.template(let manifestProblems) {
        problems.append(contentsOf: manifestProblems)
      } catch {
        problems.append(TemplateStrings.manifestUnreadable)
      }
    } else {
      problems.append(TemplateStrings.manifestUnreadable)
    }
    if !files.contains("template.html") { problems.append(TemplateStrings.templateHTMLMissing) }

    guard problems.isEmpty, let manifest else { return .failure(TemplateProblems(problems)) }
    return .success(InspectedTemplate(manifest: manifest, root: root, files: files.sorted()))
  }

  /// Walks `folder` without following symbolic links.
  private static func walk(
    _ folder: URL, relative: String, problems: inout [String], files: inout [String], totalBytes: inout Int64
  ) {
    let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey]
    guard
      let children = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: keys, options: [])
    else {
      problems.append(TemplateStrings.cannotRead(folder.path))
      return
    }
    for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      let name = child.lastPathComponent
      if isIgnored(name) { continue }
      let path = relative.isEmpty ? name : relative + "/" + name
      guard let values = try? child.resourceValues(forKeys: Set(keys)) else {
        problems.append(TemplateStrings.cannotRead(path))
        continue
      }
      if values.isSymbolicLink == true {
        problems.append(TemplateStrings.symlink(path))
      } else if values.isDirectory == true {
        // Stop descending once the limit is clearly exceeded (a folder with thousands of files).
        if files.count <= TemplateImportLimits.maxFiles {
          walk(child, relative: path, problems: &problems, files: &files, totalBytes: &totalBytes)
        }
      } else if values.isRegularFile == true {
        if !TemplateImportLimits.allowedExtensions.contains(child.pathExtension.lowercased()) {
          problems.append(TemplateStrings.fileTypeNotAllowed(path))
        }
        files.append(path)
        totalBytes += Int64(values.fileSize ?? 0)
      } else {
        problems.append(TemplateStrings.notRegularFile(path))
      }
    }
  }

  static func isRegularFile(_ url: URL) -> Bool {
    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    return values?.isRegularFile == true && values?.isSymbolicLink != true
  }

  /// Copies `template.files` into `destination` (created; must not exist), creating subfolders.
  static func copy(_ template: InspectedTemplate, to destination: URL) throws {
    let fileManager = FileManager.default
    do {
      try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
      for path in template.files {
        let source = template.root.appendingPathComponent(path)
        let target = destination.appendingPathComponent(path)
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: target)
      }
    } catch {
      throw AppError.io(message: TemplateStrings.cannotWrite(destination.path))
    }
  }
}

/// Problems that make a template invalid.
struct TemplateProblems: Error, Equatable {
  var messages: [String]
  init(_ messages: [String]) { self.messages = messages }
}
