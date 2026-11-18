import Foundation
import SSCore
import SSCoreFakes
import SSSeed
import Testing

/// `Resources/Seed/` next to the repository's other resources.
private func seedFolder() throws -> URL {
  guard let resources = AppPaths.resolveResources() else {
    throw AppError.io(message: "Resources folder not found")
  }
  return resources.appendingPathComponent("Seed", isDirectory: true)
}

/// Fake repositories and a temporary logo folder, with a loader on top.
private struct Harness {
  let logoFolder: URL
  let database: FakeDatabase
  let teams: FakeTeamRepository
  let opponents: FakeOpponentRepository
  let matches: FakeMatchRepository
  let loader: SeedLoader

  init() throws {
    logoFolder = FileManager.default.temporaryDirectory
      .appendingPathComponent("ss-seed-\(UUID().uuidString)", isDirectory: true)
    database = FakeDatabase()
    teams = FakeTeamRepository(database: database)
    opponents = FakeOpponentRepository(database: database)
    matches = FakeMatchRepository(database: database)
    loader = SeedLoader(
      seedFolder: try seedFolder(), teams: teams, opponents: opponents, matches: matches,
      logos: FakeLogoStore(folder: logoFolder))
  }

  var logoCount: Int {
    (try? FileManager.default.contentsOfDirectory(atPath: logoFolder.path).count) ?? 0
  }

  func removeLogoFolder() {
    try? FileManager.default.removeItem(at: logoFolder)
  }
}

// MARK: - Seed files

@Test func seedFilesDecodeIntoModelTypes() throws {
  let catalog = try SeedCatalog(folder: seedFolder())
  #expect(catalog.teams.count == 10)
  #expect(catalog.opponents.count == 20)
  #expect(
    catalog.teams.map(\.name) == [
      "Prima Squadra", "Juniores", "Allievi U17", "Allievi U16", "Giovanissimi U15",
      "Giovanissimi U14", "Esordienti", "Pulcini", "Primi Calci", "Femminile",
    ])
  #expect(catalog.teams.map(\.sortOrder) == Array(0..<10))
  #expect(catalog.teams.filter(\.isFirstTeam).map(\.name) == ["Prima Squadra"])
  #expect(Set(catalog.opponents.map(\.id)).count == 20)
}

@Test func opponentsCoverTheEdgeCases() throws {
  let opponents = try SeedCatalog(folder: seedFolder()).opponents
  #expect(opponents.filter { $0.name.count > 35 }.count == 3)
  #expect(opponents.filter { $0.name.hasPrefix("A.S.D.") || $0.name.hasPrefix("Pol.") }.count == 2)
  #expect(opponents.contains { $0.name.contains("'") && $0.name.contains("à") })
  #expect(opponents.filter { $0.logoFile == nil }.count == 4)
}

@Test func everyLogoFileExists() throws {
  let catalog = try SeedCatalog(folder: seedFolder())
  let files = catalog.opponents.compactMap(\.logoFile)
  #expect(files.count == 16)
  for file in files {
    #expect(FileManager.default.fileExists(atPath: catalog.logosFolder.appendingPathComponent(file).path))
  }
}

// MARK: - Generator

@Test func generatorIsDeterministicForADate() throws {
  let day = try DayDate("2026-11-18")
  let matches = generateMatches(today: day)
  #expect(!matches.isEmpty)
  #expect(matches == generateMatches(today: day))
}

@Test func generatedMatchesHaveTheRequiredShape() throws {
  let today = try DayDate("2026-11-18")  // a Wednesday: the first weekend is 21–22 November
  let matches = generateMatches(today: today)
  let catalog = try SeedCatalog(folder: seedFolder())
  let teamIDs = Set(catalog.teams.map(\.id))
  let opponentIDs = Set(catalog.opponents.map(\.id))
  #expect(matches.allSatisfy { teamIDs.contains($0.teamID) && opponentIDs.contains($0.opponentID) })
  #expect(matches.allSatisfy { $0.source == .seed && !$0.isLocked })

  let first = weekend(containing: today)
  #expect(first.saturday.value == "2026-11-21")
  let upcoming = [first, first.next, first.next.next, first.next.next.next]
  let counts = upcoming.map { week in matches.filter { week.contains($0.date) }.count }
  #expect(counts == [9, 10, 12, 8])
  #expect(counts.filter { $0 == 12 }.count == 1)
  #expect(counts.filter { (8...11).contains($0) }.count == 3)

  let upcomingMatches = matches.filter { match in upcoming.contains { $0.contains(match.date) } }
  #expect(upcomingMatches.allSatisfy { $0.score == nil && $0.halfTime == nil })

  let last = first.previous
  let lastMatches = matches.filter { last.contains($0.date) }
  #expect(lastMatches.count == 9)
  #expect(lastMatches.allSatisfy { $0.status == .played && $0.score != nil && $0.halfTime != nil })

  #expect(matches.filter { $0.status == .postponed }.count == 1)
  #expect(matches.filter { $0.time == nil }.count == 1)
  #expect(Set(matches.map { $0.date.isoWeekday }) == [6, 7])
  #expect(Set(matches.map(\.isHome)) == [true, false])
  // No team plays twice on the same day, even in the 12-match weekend.
  #expect(Set(matches.map { "\($0.teamID)-\($0.date.value)" }).count == matches.count)
}

@Test func saturdayStartsTheCurrentWeekend() throws {
  let saturday = try DayDate("2026-11-21")
  #expect(generateMatches(today: saturday).contains { $0.date.value == "2026-11-21" })
}

// MARK: - Loading and removing

@Test func freshDatabaseGetsPrimaSquadraAsFirstTeam() async throws {
  let harness = try Harness()
  defer { harness.removeLogoFolder() }
  _ = try await harness.loader.load(today: try DayDate("2026-11-18"))
  let teams = try harness.teams.list()
  #expect(teams.count == 10)
  #expect(teams.filter(\.isFirstTeam).map(\.name) == ["Prima Squadra"])
}

@Test func loadingTwiceLeavesTheSameNumberOfRows() async throws {
  let harness = try Harness()
  defer { harness.removeLogoFolder() }
  let today = try DayDate("2026-11-18")
  let first = try await harness.loader.load(today: today)
  let second = try await harness.loader.load(today: today)
  #expect(first == second)
  #expect(first == DemoDataSummary(teams: 10, opponents: 20, matches: generateMatches(today: today).count))
  #expect(try harness.teams.list().count == 10)
  #expect(try harness.opponents.list().count == 20)
  #expect(try harness.matches.count(source: .seed) == generateMatches(today: today).count)
  #expect(harness.logoCount == 16)
  #expect(try harness.loader.hasDemoData())
}

@Test func loadingKeepsAnExistingFirstTeam() async throws {
  let harness = try Harness()
  defer { harness.removeLogoFolder() }
  let own = try harness.teams.create(
    TeamDraft(name: "Squadra del Club", shortLabel: "Club", isFirstTeam: true, isActive: true))
  _ = try await harness.loader.load(today: try DayDate("2026-11-18"))
  let teams = try harness.teams.list()
  #expect(teams.count == 11)
  #expect(teams.filter(\.isFirstTeam).map(\.id) == [own.id])
}

@Test func removeKeepsUserTeamsAndTheRefusedFirstTeam() async throws {
  let harness = try Harness()
  defer { harness.removeLogoFolder() }
  _ = try await harness.loader.load(today: try DayDate("2026-11-18"))
  _ = try harness.teams.create(
    TeamDraft(name: "Squadra del Club", shortLabel: "Club", isFirstTeam: false, isActive: true))

  // The delete of the seed first team is refused while the user's team exists: remove() skips it.
  try harness.loader.remove()

  #expect(try harness.loader.hasDemoData() == false)
  #expect(try harness.teams.list().map(\.name) == ["Prima Squadra", "Squadra del Club"])
  #expect(try harness.opponents.list().isEmpty)
  #expect(harness.logoCount == 0)
}

@Test func removeWithNoUserDataEmptiesTheDatabaseAndLoadingAgainWorks() async throws {
  let harness = try Harness()
  defer { harness.removeLogoFolder() }
  let today = try DayDate("2026-11-18")
  _ = try await harness.loader.load(today: today)
  try harness.loader.remove()
  #expect(try harness.teams.list().isEmpty)
  #expect(try harness.opponents.list().isEmpty)
  #expect(try harness.matches.count(source: nil) == 0)

  _ = try await harness.loader.load(today: today)
  #expect(try harness.teams.list().count == 10)
  #expect(try harness.opponents.list().count == 20)
}
