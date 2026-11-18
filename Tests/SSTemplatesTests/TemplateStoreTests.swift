import Foundation
import SSCore
import Testing
import ZIPFoundation

@testable import SSTemplates

/// A temporary data folder and resources folder, with helpers to write template folders and zips.
struct StoreSandbox {
  let root: URL
  let paths: AppPaths
  let store: FileTemplateStore

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SSTemplatesTests-\(UUID().uuidString)", isDirectory: true)
    paths = AppPaths(
      dataFolder: root.appendingPathComponent("data", isDirectory: true),
      resources: root.appendingPathComponent("resources", isDirectory: true),
      defaultOutputFolder: root.appendingPathComponent("output", isDirectory: true))
    try paths.createFolders()
    try FileManager.default.createDirectory(at: paths.builtinTemplates, withIntermediateDirectories: true)
    store = FileTemplateStore(paths: paths)
  }

  static func manifest(id: String, version: String = "1.0.0", name: String? = nil) -> String {
    """
    {"id": "\(id)", "name": "\(name ?? id)", "version": "\(version)", "format": "post", "width": 1080,
     "height": 1350, "kind": "single", "purpose": "prematch"}
    """
  }

  /// Writes a valid template folder (manifest, template.html, a css file) and returns it.
  @discardableResult
  func writeTemplate(
    at folder: URL, id: String, version: String = "1.0.0", html: String = "<div>{{club.name}}</div>",
    extra: [String: Data] = [:]
  ) throws -> URL {
    var files: [String: Data] = [
      "manifest.json": Data(Self.manifest(id: id, version: version).utf8),
      "template.html": Data(html.utf8),
      "assets/style.css": Data("body{}".utf8),
    ]
    files.merge(extra) { $1 }
    for (path, data) in files {
      let url = folder.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url)
    }
    return folder
  }

  func source(_ name: String) -> URL { root.appendingPathComponent("sources/\(name)", isDirectory: true) }

  /// Writes a zip with the given entries. A `nil` data with a target makes a symbolic link.
  func writeZip(_ name: String, entries: [(path: String, data: Data, symlink: Bool)]) throws -> URL {
    let url = root.appendingPathComponent(name)
    let archive = try Archive(url: url, accessMode: .create)
    for entry in entries {
      let data = entry.data
      try archive.addEntry(
        with: entry.path, type: entry.symlink ? .symlink : .file, uncompressedSize: Int64(data.count),
        compressionMethod: entry.symlink ? .none : .deflate
      ) { position, size in
        data.subdata(in: Int(position)..<Int(position) + size)
      }
    }
    return url
  }

  func validZipEntries(id: String, prefix: String = "") -> [(path: String, data: Data, symlink: Bool)] {
    [
      (prefix + "manifest.json", Data(Self.manifest(id: id).utf8), false),
      (prefix + "template.html", Data("<div>{{club.name}}</div>".utf8), false),
      (prefix + "assets/style.css", Data("body{}".utf8), false),
    ]
  }

  func installedFiles(_ id: String) -> [String] {
    let folder = paths.templates.appendingPathComponent(id)
    let enumerator = FileManager.default.enumerator(atPath: folder.path)
    return (enumerator?.allObjects as? [String] ?? []).sorted()
  }
}

func problems(_ outcome: TemplateInstallOutcome) -> [String] {
  if case .invalid(let problems) = outcome { return problems }
  return []
}

@Suite struct TemplateImportTests {
  @Test func installsValidFolder() throws {
    let box = try StoreSandbox()
    let folder = try box.writeTemplate(at: box.source("mine"), id: "my-template")
    let outcome = try box.store.install(from: folder, replace: false)
    guard case .installed(let template) = outcome else {
      Issue.record("expected installed, got \(outcome)")
      return
    }
    #expect(template.id == "my-template")
    #expect(template.isBuiltin == false)
    #expect(template.folder == box.paths.templates.appendingPathComponent("my-template", isDirectory: true))
    #expect(box.installedFiles("my-template").contains("assets/style.css"))
    #expect(try box.store.list().map(\.id) == ["my-template"])
  }

  @Test func installsFolderWithManifestOneLevelDeep() throws {
    let box = try StoreSandbox()
    let outer = box.source("outer")
    try box.writeTemplate(at: outer.appendingPathComponent("inner"), id: "deep")
    try Data().write(to: outer.appendingPathComponent(".DS_Store"))
    guard case .installed(let template) = try box.store.install(from: outer, replace: false) else {
      Issue.record("expected installed")
      return
    }
    #expect(template.id == "deep")
  }

  @Test func installsValidZip() throws {
    let box = try StoreSandbox()
    let zip = try box.writeZip("valid.zip", entries: box.validZipEntries(id: "zipped"))
    guard case .installed(let template) = try box.store.install(from: zip, replace: false) else {
      Issue.record("expected installed")
      return
    }
    #expect(template.id == "zipped")
    #expect(box.installedFiles("zipped") == ["assets", "assets/style.css", "manifest.json", "template.html"])
  }

  @Test func installsZipWithTopFolderAndSkipsMacJunk() throws {
    let box = try StoreSandbox()
    var entries = box.validZipEntries(id: "foldered", prefix: "foldered/")
    entries.append(("__MACOSX/foldered/._template.html", Data("junk".utf8), false))
    let zip = try box.writeZip("foldered.zip", entries: entries)
    guard case .installed = try box.store.install(from: zip, replace: false) else {
      Issue.record("expected installed")
      return
    }
    #expect(!box.installedFiles("foldered").contains { $0.contains("MACOSX") })
  }

  @Test func rejectsMissingManifest() throws {
    let box = try StoreSandbox()
    let folder = box.source("nomanifest")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("<div></div>".utf8).write(to: folder.appendingPathComponent("template.html"))
    #expect(problems(try box.store.install(from: folder, replace: false)) == [TemplateStrings.manifestMissing])

    let zip = try box.writeZip("nomanifest.zip", entries: [("template.html", Data("<div></div>".utf8), false)])
    #expect(problems(try box.store.install(from: zip, replace: false)) == [TemplateStrings.manifestMissing])
  }

  @Test func rejectsMissingTemplateHTMLAndBadManifest() throws {
    let box = try StoreSandbox()
    let folder = box.source("bad")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(#"{"id": "bad", "name": "Bad", "version": "1.0.0", "format": "post", "width": "x"}"#.utf8)
      .write(to: folder.appendingPathComponent("manifest.json"))
    let found = problems(try box.store.install(from: folder, replace: false))
    #expect(found.contains(TemplateStrings.templateHTMLMissing))
    #expect(found.contains("manifest.width deve essere un numero intero."))
    #expect(found.contains("manifest.kind manca."))
  }

  @Test func rejectsPathTraversalInZip() throws {
    let box = try StoreSandbox()
    var entries = box.validZipEntries(id: "evil")
    entries.append(("../escaped.html", Data("x".utf8), false))
    let zip = try box.writeZip("traversal.zip", entries: entries)
    let found = problems(try box.store.install(from: zip, replace: false))
    #expect(found == [TemplateStrings.unsafePath("../escaped.html")])
    #expect(
      !FileManager.default.fileExists(
        atPath: FileManager.default.temporaryDirectory.appendingPathComponent("escaped.html").path))
    #expect(try box.store.list().isEmpty)

    let absolute = try box.writeZip(
      "absolute.zip", entries: box.validZipEntries(id: "abs") + [("/tmp/x.html", Data("x".utf8), false)])
    #expect(
      problems(try box.store.install(from: absolute, replace: false)) == [TemplateStrings.unsafePath("/tmp/x.html")])
  }

  @Test func rejectsSymlinkInFolderAndZip() throws {
    let box = try StoreSandbox()
    let folder = try box.writeTemplate(at: box.source("linked"), id: "linked")
    try FileManager.default.createSymbolicLink(
      at: folder.appendingPathComponent("assets/secret.css"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
    #expect(
      problems(try box.store.install(from: folder, replace: false)) == [TemplateStrings.symlink("assets/secret.css")])

    var entries = box.validZipEntries(id: "zlink")
    entries.append(("assets/secret.css", Data("/etc/hosts".utf8), true))
    let zip = try box.writeZip("symlink.zip", entries: entries)
    #expect(
      problems(try box.store.install(from: zip, replace: false)) == [TemplateStrings.symlink("assets/secret.css")])
    #expect(try box.store.list().isEmpty)
  }

  @Test func rejectsOversizeFolderAndZip() throws {
    let box = try StoreSandbox()
    let big = Data(count: Int(TemplateImportLimits.maxTotalBytes) + 1)
    let folder = try box.writeTemplate(at: box.source("big"), id: "big", extra: ["assets/big.png": big])
    let tooLarge = TemplateStrings.tooLarge(megabytes: 20)
    #expect(problems(try box.store.install(from: folder, replace: false)) == [tooLarge])

    // Zeros compress to a few kilobytes: the zip is small, its declared content is not.
    let zip = try box.writeZip("bomb.zip", entries: box.validZipEntries(id: "bomb") + [("assets/big.png", big, false)])
    #expect(try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 < 1_000_000)
    #expect(problems(try box.store.install(from: zip, replace: false)) == [tooLarge])
  }

  @Test func rejectsTooManyFilesAndForbiddenTypes() throws {
    let box = try StoreSandbox()
    var extra: [String: Data] = [:]
    for index in 0..<TemplateImportLimits.maxFiles { extra["assets/f\(index).css"] = Data("a".utf8) }
    let folder = try box.writeTemplate(at: box.source("many"), id: "many", extra: extra)
    #expect(problems(try box.store.install(from: folder, replace: false)) == [TemplateStrings.tooManyFiles(200)])

    let typed = try box.writeTemplate(at: box.source("typed"), id: "typed", extra: ["run.sh": Data("x".utf8)])
    #expect(
      problems(try box.store.install(from: typed, replace: false)) == [TemplateStrings.fileTypeNotAllowed("run.sh")])
  }

  @Test func rejectsNonZipFiles() throws {
    let box = try StoreSandbox()
    let fake = box.root.appendingPathComponent("fake.zip")
    try Data("not a zip".utf8).write(to: fake)
    #expect(problems(try box.store.install(from: fake, replace: false)) == [TemplateStrings.zipNotValid])
    let text = box.root.appendingPathComponent("notes.txt")
    try Data("x".utf8).write(to: text)
    #expect(problems(try box.store.install(from: text, replace: false)) == [TemplateStrings.notFolderOrZip])
    #expect(
      problems(try box.store.install(from: box.root.appendingPathComponent("missing"), replace: false))
        == [TemplateStrings.notFolderOrZip])
  }

  @Test func idClashNeedsReplace() throws {
    let box = try StoreSandbox()
    let first = try box.writeTemplate(at: box.source("v1"), id: "same", html: "<div>one</div>")
    let second = try box.writeTemplate(at: box.source("v2"), id: "same", html: "<div>two</div>")
    _ = try box.store.install(from: first, replace: false)
    guard case .alreadyExists(let existing) = try box.store.install(from: second, replace: false) else {
      Issue.record("expected alreadyExists")
      return
    }
    #expect(existing.id == "same")
    let html = existing.folder.appendingPathComponent("template.html")
    #expect(try String(contentsOf: html, encoding: .utf8) == "<div>one</div>")
    guard case .installed = try box.store.install(from: second, replace: true) else {
      Issue.record("expected installed")
      return
    }
    #expect(try String(contentsOf: html, encoding: .utf8) == "<div>two</div>")
    #expect(!box.installedFiles("same").isEmpty)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: box.paths.templates.path)
    #expect(leftovers == ["same"])
  }

  @Test func safeComponentsRejectsUnsafePaths() {
    #expect(SafeUnzip.safeComponents("a/b.css") == ["a", "b.css"])
    #expect(SafeUnzip.safeComponents("assets/") == ["assets"])
    for path in ["", "/etc/passwd", "../x", "a/../../x", "a/./b", "a\\b", "C:/x", "a//b", "x\0y"] {
      #expect(SafeUnzip.safeComponents(path) == nil, "\(path)")
    }
  }
}

@Suite struct BuiltinTemplateTests {
  @Test func installsBuiltinsAndUpdatesOnlyNewerVersions() throws {
    let box = try StoreSandbox()
    let bundled = box.paths.builtinTemplates.appendingPathComponent("post")
    try box.writeTemplate(at: bundled, id: "post-builtin", html: "<div>bundled</div>")
    try box.store.installBuiltins()
    let template = try box.store.get(id: "post-builtin")
    #expect(template.isBuiltin)
    let html = template.folder.appendingPathComponent("template.html")
    #expect(try String(contentsOf: html, encoding: .utf8) == "<div>bundled</div>")

    // Same version: a local edit is kept.
    try Data("<div>edited</div>".utf8).write(to: html)
    try box.store.installBuiltins()
    #expect(try String(contentsOf: html, encoding: .utf8) == "<div>edited</div>")

    // Newer bundled version: replaced.
    try box.writeTemplate(at: bundled, id: "post-builtin", version: "1.1.0", html: "<div>new</div>")
    try box.store.installBuiltins()
    #expect(try String(contentsOf: html, encoding: .utf8) == "<div>new</div>")
    #expect(try box.store.get(id: "post-builtin").manifest.version == "1.1.0")
  }

  @Test func removeAndRestore() throws {
    let box = try StoreSandbox()
    try box.writeTemplate(at: box.paths.builtinTemplates.appendingPathComponent("b"), id: "builtin-one")
    try box.store.installBuiltins()
    #expect(throws: AppError.conflict(message: TemplateStrings.builtinCannotBeRemoved)) {
      try box.store.remove(id: "builtin-one")
    }

    let user = try box.writeTemplate(at: box.source("u"), id: "user-one")
    _ = try box.store.install(from: user, replace: false)
    #expect(try box.store.list().map(\.id) == ["builtin-one", "user-one"])
    try box.store.remove(id: "user-one")
    #expect(throws: AppError.notFound) { try box.store.get(id: "user-one") }
    #expect(throws: AppError.notFound) { try box.store.remove(id: "user-one") }

    // Replace the built-in, then restore the bundled copy.
    let replacement = try box.writeTemplate(at: box.source("r"), id: "builtin-one", html: "<div>mine</div>")
    _ = try box.store.install(from: replacement, replace: true)
    let restored = try box.store.restoreBuiltin(id: "builtin-one")
    #expect(restored.isBuiltin)
    let html = try String(contentsOf: restored.folder.appendingPathComponent("template.html"), encoding: .utf8)
    #expect(html == "<div>{{club.name}}</div>")
    #expect(throws: AppError.notFound) { _ = try box.store.restoreBuiltin(id: "user-one") }
  }

  @Test func getRejectsPathLikeIDs() throws {
    let box = try StoreSandbox()
    #expect(throws: AppError.notFound) { try box.store.get(id: "../data") }
    #expect(throws: AppError.notFound) { try box.store.get(id: "") }
  }
}
