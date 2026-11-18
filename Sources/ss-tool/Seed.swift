import Foundation
import SSCore
import SSData
import SSSeed

/// `ss-tool seed`: loads the fake matches for the coming weekends into the Dev data folder (or
/// `SS_DATA_DIR`). Refuses to touch the release data folder.
func runSeed(_ args: [String]) async -> Int32 {
  do {
    let paths = try AppPaths.resolve()
    if paths.isReleaseDataFolder {
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
