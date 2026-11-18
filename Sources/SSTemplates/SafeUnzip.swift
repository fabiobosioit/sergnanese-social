import Foundation
import SSCore
import ZIPFoundation

/// Extracts a template `.zip`, treating it as hostile.
///
/// Before anything is written, every entry is checked: no absolute path, no `..`, no backslash or
/// drive letter, no symbolic link, at most `TemplateImportLimits.maxFiles` files and
/// `TemplateImportLimits.maxTotalBytes` declared bytes. While extracting, the bytes actually produced
/// are counted again (a zip can lie about its sizes) and the destination of every file is checked to
/// be inside the extraction folder.
enum SafeUnzip {
  /// Extracts `zip` into `destination` (an empty folder). Returns the problems found; when there is
  /// any, nothing usable was extracted.
  static func extract(_ zip: URL, to destination: URL) -> [String] {
    let fileSize = (try? zip.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    if Int64(fileSize) > TemplateImportLimits.maxTotalBytes {
      return [TemplateStrings.tooLarge(megabytes: TemplateImportLimits.maxMegabytes)]
    }
    let archive: Archive
    do {
      archive = try Archive(url: zip, accessMode: .read)
    } catch {
      return [TemplateStrings.zipNotValid]
    }

    var problems: [String] = []
    var fileEntries: [(entry: Entry, components: [String])] = []
    var declaredBytes: UInt64 = 0
    for entry in archive {
      let path = entry.path
      guard let components = safeComponents(path) else {
        problems.append(TemplateStrings.unsafePath(path))
        continue
      }
      switch entry.type {
      case .symlink:
        problems.append(TemplateStrings.symlink(path))
      case .directory:
        continue
      case .file:
        if components.contains(where: TemplateInspector.isIgnored) { continue }
        fileEntries.append((entry, components))
        declaredBytes += entry.uncompressedSize
      }
    }
    if fileEntries.count > TemplateImportLimits.maxFiles {
      problems.append(TemplateStrings.tooManyFiles(TemplateImportLimits.maxFiles))
    }
    if declaredBytes > UInt64(TemplateImportLimits.maxTotalBytes) {
      problems.append(TemplateStrings.tooLarge(megabytes: TemplateImportLimits.maxMegabytes))
    }
    guard problems.isEmpty else { return problems }

    let base = destination.standardizedFileURL.resolvingSymlinksInPath().path + "/"
    var writtenBytes: Int64 = 0
    for (entry, components) in fileEntries {
      var target = destination
      for component in components { target.appendPathComponent(component) }
      let resolvedParent = target.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path + "/"
      guard target.standardizedFileURL.path.hasPrefix(destination.standardizedFileURL.path + "/"),
        resolvedParent.hasPrefix(base) || resolvedParent == base
      else {
        return [TemplateStrings.unsafePath(entry.path)]
      }
      do {
        try FileManager.default.createDirectory(
          at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data()
        _ = try archive.extract(entry, skipCRC32: false) { chunk in
          writtenBytes += Int64(chunk.count)
          guard writtenBytes <= TemplateImportLimits.maxTotalBytes, data.count + chunk.count <= entry.uncompressedSize
          else { throw TemplateProblems([TemplateStrings.tooLarge(megabytes: TemplateImportLimits.maxMegabytes)]) }
          data.append(chunk)
        }
        // `.withoutOverwriting`: a second entry with the same path never replaces the first.
        try data.write(to: target, options: [.withoutOverwriting])
      } catch let error as TemplateProblems {
        return error.messages
      } catch {
        return [TemplateStrings.cannotExtract(entry.path)]
      }
    }
    return []
  }

  /// The path components of a zip entry, or `nil` when the path is unsafe: empty, absolute, with a
  /// backslash, a drive letter, a NUL, or a `.`/`..` component. A trailing `/` (directory) is allowed.
  static func safeComponents(_ path: String) -> [String]? {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return nil }
    var parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    if parts.last == "" { parts.removeLast() }
    guard !parts.isEmpty else { return nil }
    for part in parts {
      if part.isEmpty || part == "." || part == ".." { return nil }
    }
    if let first = parts.first, first.count >= 2, first.dropFirst().first == ":" { return nil }
    return parts
  }
}
