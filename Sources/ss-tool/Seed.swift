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

/// `true` when `folder` is the user's real (release) data folder. `SS_RELEASE_DATA_DIR` replaces
/// that folder, so a test can prove the refusal without pointing at the real one.
func isReleaseFolder(_ folder: URL, environment: [String: String]) -> Bool {
  let release: URL
  if let override = environment["SS_RELEASE_DATA_DIR"], !override.isEmpty {
    release = URL(fileURLWithPath: override, isDirectory: true)
  } else {
    release = AppPaths.standardDataFolder(isDebugBuild: false)
  }
  return folder.standardizedFileURL.path == release.standardizedFileURL.path
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
