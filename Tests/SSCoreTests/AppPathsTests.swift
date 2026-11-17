import Foundation
import Testing

@testable import SSCore

@Suite struct AppPathsTests {
  @Test func resolvesWithDataDirOverride() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ss-paths-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let paths = try AppPaths.resolve(environment: ["SS_DATA_DIR": folder.path], isDebugBuild: false)
    #expect(paths.dataFolder.standardizedFileURL.path == folder.standardizedFileURL.path)
    #expect(paths.database.lastPathComponent == "db.sqlite")
    #expect(paths.defaultOutputFolder.lastPathComponent == "output")
    for sub in [paths.backups, paths.logos, paths.templates] {
      #expect(FileManager.default.fileExists(atPath: sub.path))
    }
    #expect(!paths.isReleaseDataFolder)
  }

  @Test func standardFolders() {
    #expect(AppPaths.standardDataFolder(isDebugBuild: true).lastPathComponent == "Sergnanese Social Dev")
    #expect(AppPaths.standardDataFolder(isDebugBuild: false).lastPathComponent == "Sergnanese Social")
    #expect(AppPaths.isDebugBuild)  // tests run in debug
  }

  @Test func resourcesLookupOrder() throws {
    let custom = FileManager.default.temporaryDirectory.appendingPathComponent("ss-res-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: custom) }
    #expect(AppPaths.resolveResources(environment: ["SS_RESOURCES_DIR": custom.path])?.path == custom.path)
    // Without the variable, the repository's Resources/ (it holds Fixtures/) is found.
    let repo = try #require(AppPaths.resolveResources(environment: [:]))
    #expect(FileManager.default.fileExists(atPath: repo.appendingPathComponent("Fixtures").path))
    // A missing SS_RESOURCES_DIR falls through to the next candidate.
    #expect(AppPaths.resolveResources(environment: ["SS_RESOURCES_DIR": "/nonexistent-ss"]) == repo)
  }

  @Test func temporaryPathsAreIsolated() throws {
    let first = try AppPaths.temporary()
    let second = try AppPaths.temporary()
    #expect(first.dataFolder != second.dataFolder)
    #expect(first.dataFolder.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    #expect(first.latestBackupDate() == nil)
    try Data("x".utf8).write(to: first.backups.appendingPathComponent("db-1.sqlite"))
    #expect(first.latestBackupDate() != nil)
  }

  @Test func outputFolderFollowsSettings() throws {
    let paths = try AppPaths.temporary()
    #expect(paths.outputFolder(for: .defaults) == paths.defaultOutputFolder)
    var settings = ClubSettings.defaults
    settings.outputFolder = "/tmp/elsewhere"
    #expect(paths.outputFolder(for: settings).path == "/tmp/elsewhere")
  }
}
