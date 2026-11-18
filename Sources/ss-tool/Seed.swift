import Foundation
import SSCore
import SSData
import SSSeed

/// The data folder `AppPaths.resolve` would pick, worked out without creating anything.
func wouldBeDataFolder(environment: [String: String]) -> URL {
  if let custom = environment["SS_DATA_DIR"], !custom.isEmpty {
    return URL(fileURLWithPath: custom, isDirectory: true)
  }
  return AppPaths.standardDataFolder(isDebugBuild: AppPaths.isDebugBuild)
}

/// A comparable form of `url`: symlinks resolved as far as the path exists (the rest appended as
/// is), standardised and lower-cased, since the Mac's file system is case-insensitive.
func comparablePath(_ url: URL) -> String {
  var existing = url.standardizedFileURL
  var rest: [String] = []
  while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
    rest.insert(existing.lastPathComponent, at: 0)
    existing = existing.deletingLastPathComponent()
  }
  var resolved = existing.resolvingSymlinksInPath()
  for component in rest { resolved.appendPathComponent(component) }
  return resolved.standardizedFileURL.path.lowercased()
}

/// `true` when `folder` is the user's real (release) data folder, or the folder named by
/// `SS_RELEASE_DATA_DIR`. The variable only adds a protected folder (tests use it to prove the
/// refusal without pointing at the real one); it never replaces the real check.
func isReleaseFolder(_ folder: URL, environment: [String: String]) -> Bool {
  var protected = [AppPaths.standardDataFolder(isDebugBuild: false)]
  if let override = environment["SS_RELEASE_DATA_DIR"], !override.isEmpty {
    protected.append(URL(fileURLWithPath: override, isDirectory: true))
  }
  let target = comparablePath(folder)
  return protected.contains { comparablePath($0) == target }
}

/// `ss-tool seed`: loads the fake matches for the coming weekends into the Dev data folder (or
/// `SS_DATA_DIR`). Refuses to touch the release data folder, and checks before anything is created.
func runSeed(_ args: [String]) async -> Int32 {
  let environment = ProcessInfo.processInfo.environment
  let folder = wouldBeDataFolder(environment: environment)
  if isReleaseFolder(folder, environment: environment) {
    FileHandle.standardError.write(
      Data("seed: refused, \(folder.path) is the release data folder\n".utf8))
    return 1
  }
  do {
    let paths = try AppPaths.resolve()
    // Second line of defence, after the folder is resolved.
    if paths.isReleaseDataFolder || isReleaseFolder(paths.dataFolder, environment: environment) {
      FileHandle.standardError.write(
        Data("seed: refused, \(paths.dataFolder.path) is the release data folder\n".utf8))
      return 1
    }
    let database = try AppDatabase.open(paths: paths)
    let loader = SeedLoader(
      seedFolder: paths.seed, teams: database.teams, opponents: database.opponents, matches: database.matches,
      logos: LogoFileStore(folder: paths.logos))
    let summary = try await loader.load(today: DayDate.today())
    let counts = "\(summary.teams) teams, \(summary.opponents) opponents, \(summary.matches) matches"
    print("seed: \(counts) in \(paths.dataFolder.path)")
    return 0
  } catch {
    FileHandle.standardError.write(Data("seed: \(error.localizedDescription)\n".utf8))
    return 1
  }
}
