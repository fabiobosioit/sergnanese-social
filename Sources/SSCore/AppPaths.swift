import Foundation

/// Where the app keeps its files (`01-architecture.md` §2).
///
/// ```
/// <dataFolder>/            ~/Library/Application Support/Sergnanese Social/      release builds
///                          ~/Library/Application Support/Sergnanese Social Dev/  debug builds, scripts
///                          $SS_DATA_DIR                                           when set (tests, tools)
///     db.sqlite
///     backups/
///     logos/
///     templates/
/// ```
///
/// Resources (`Templates/`, `Fixtures/`, `Seed/`) are never loaded with `Bundle.module`; see
/// `resolveResources`.
public struct AppPaths: Sendable, Equatable, Hashable {
  public var dataFolder: URL
  /// The folder holding `Templates/`, `Fixtures/` and `Seed/`.
  public var resources: URL
  /// Used when `ClubSettings.outputFolder` is `nil`.
  public var defaultOutputFolder: URL

  public init(dataFolder: URL, resources: URL, defaultOutputFolder: URL) {
    self.dataFolder = dataFolder
    self.resources = resources
    self.defaultOutputFolder = defaultOutputFolder
  }

  public var database: URL { dataFolder.appendingPathComponent("db.sqlite") }
  public var backups: URL { dataFolder.appendingPathComponent("backups", isDirectory: true) }
  public var logos: URL { dataFolder.appendingPathComponent("logos", isDirectory: true) }
  public var templates: URL { dataFolder.appendingPathComponent("templates", isDirectory: true) }

  /// Bundled built-in templates.
  public var builtinTemplates: URL { resources.appendingPathComponent("Templates", isDirectory: true) }
  /// Sample contexts and the data set behind the fakes.
  public var fixtures: URL { resources.appendingPathComponent("Fixtures", isDirectory: true) }
  /// Seed (demo) data.
  public var seed: URL { resources.appendingPathComponent("Seed", isDirectory: true) }

  /// The folder images are written to for `settings`.
  public func outputFolder(for settings: ClubSettings) -> URL {
    guard let path = settings.outputFolder else { return defaultOutputFolder }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  /// `true` when this is the user's real data folder (release builds). Tools such as
  /// `ss-tool seed` refuse to run against it.
  public var isReleaseDataFolder: Bool {
    dataFolder.standardizedFileURL.path == Self.standardDataFolder(isDebugBuild: false).standardizedFileURL.path
  }

  /// Creates the data folder and `backups/`, `logos/`, `templates/` when missing.
  public func createFolders() throws {
    for folder in [dataFolder, backups, logos, templates] {
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      } catch {
        throw AppError.io(message: CoreStrings.cannotCreateFolder(folder.path))
      }
    }
  }

  /// Modification date of the newest file in `backups/`, `nil` when there is none.
  public func latestBackupDate() -> Date? {
    let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: backups, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
    else { return nil }
    return files.compactMap { url -> Date? in
      guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
      return values.contentModificationDate
    }.max()
  }

  // MARK: Resolution

  /// `true` in debug builds (`swift build`, `swift run`, `Scripts/run.sh`).
  public static var isDebugBuild: Bool {
    #if DEBUG
      return true
    #else
      return false
    #endif
  }

  /// `~/Library/Application Support/Sergnanese Social[ Dev]/`.
  public static func standardDataFolder(isDebugBuild: Bool) -> URL {
    let support =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    return support.appendingPathComponent(
      isDebugBuild ? "Sergnanese Social Dev" : "Sergnanese Social", isDirectory: true)
  }

  /// The paths for this process, with folders created:
  /// - data folder: `SS_DATA_DIR` if set, else the Dev folder in debug builds, else the release folder;
  /// - default output folder: `<SS_DATA_DIR>/output` when `SS_DATA_DIR` is set, else
  ///   `~/Pictures/Sergnanese Social` (`… Dev` in debug builds);
  /// - resources: see `resolveResources`.
  ///
  /// Throws `AppError.io` when the resources folder cannot be found or a folder cannot be created.
  public static func resolve(
    environment: [String: String] = ProcessInfo.processInfo.environment, isDebugBuild: Bool = AppPaths.isDebugBuild
  ) throws -> AppPaths {
    guard let resources = resolveResources(environment: environment) else {
      throw AppError.io(message: CoreStrings.resourcesNotFound)
    }
    let paths: AppPaths
    if let custom = environment["SS_DATA_DIR"], !custom.isEmpty {
      let folder = URL(fileURLWithPath: custom, isDirectory: true)
      paths = AppPaths(
        dataFolder: folder, resources: resources,
        defaultOutputFolder: folder.appendingPathComponent("output", isDirectory: true))
    } else {
      let pictures =
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
      paths = AppPaths(
        dataFolder: standardDataFolder(isDebugBuild: isDebugBuild), resources: resources,
        defaultOutputFolder: pictures.appendingPathComponent(
          isDebugBuild ? "Sergnanese Social Dev" : "Sergnanese Social", isDirectory: true))
    }
    try paths.createFolders()
    return paths
  }

  /// Paths inside a new, empty temporary folder (output in `<tmp>/output`), with folders created.
  /// For tests and the fakes: never touches the user's folders.
  public static func temporary() throws -> AppPaths {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("SergnaneseSocial-\(UUID().uuidString)", isDirectory: true)
    let resources = resolveResources() ?? root.appendingPathComponent("Resources", isDirectory: true)
    let paths = AppPaths(
      dataFolder: root.appendingPathComponent("data", isDirectory: true), resources: resources,
      defaultOutputFolder: root.appendingPathComponent("output", isDirectory: true))
    try paths.createFolders()
    return paths
  }

  /// Finds the resources folder, in order:
  /// 1. `SS_RESOURCES_DIR`, when it names an existing folder;
  /// 2. `Bundle.main.resourceURL` (the packaged app), when it holds `Templates`, `Fixtures` or `Seed`;
  /// 3. the repository's `Resources/` (for `swift run` and `swift test`), found from this source
  ///    file's location and from the current directory.
  public static func resolveResources(
    environment: [String: String] = ProcessInfo.processInfo.environment, sourceFile: String = #filePath
  ) -> URL? {
    let fileManager = FileManager.default
    func isFolder(_ url: URL) -> Bool {
      var isDirectory: ObjCBool = false
      return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    func hasMarker(_ url: URL) -> Bool {
      ["Templates", "Fixtures", "Seed"].contains { isFolder(url.appendingPathComponent($0)) }
    }
    if let custom = environment["SS_RESOURCES_DIR"], !custom.isEmpty {
      let url = URL(fileURLWithPath: custom, isDirectory: true)
      if isFolder(url) { return url }
    }
    if let bundled = Bundle.main.resourceURL, hasMarker(bundled) { return bundled }
    // Sources/SSCore/AppPaths.swift → repository root.
    let repo = URL(fileURLWithPath: sourceFile).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Resources", isDirectory: true)
    if hasMarker(repo) { return repo }
    let current = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
      .appendingPathComponent("Resources", isDirectory: true)
    if hasMarker(current) { return current }
    return nil
  }
}
