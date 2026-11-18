import Foundation
import SSCore

/// The `DemoDataLoader` behind "Carica dati demo". Works only through the repository protocols and
/// `LogoStore`, so it runs the same on the database and on the fakes.
public struct SeedLoader: DemoDataLoader {
  /// `Resources/Seed/` (`AppPaths.seed`).
  let seedFolder: URL
  let teams: any TeamRepository
  let opponents: any OpponentRepository
  let matches: any MatchRepository
  let logos: any LogoStore

  public init(
    seedFolder: URL, teams: any TeamRepository, opponents: any OpponentRepository,
    matches: any MatchRepository, logos: any LogoStore
  ) {
    self.seedFolder = seedFolder
    self.teams = teams
    self.opponents = opponents
    self.matches = matches
    self.logos = logos
  }

  /// Removes the `.seed` matches, then inserts the seed teams and opponents that do not exist yet
  /// (matched by name) and the generated matches for the weekends around `today`.
  ///
  /// Teams are created with `isFirstTeam` false: the repository gives the flag to the first team
  /// it creates when there is none, and never takes it from an existing first team.
  public func load(today: DayDate) async throws -> DemoDataSummary {
    let seed = try SeedCatalog(folder: seedFolder)
    _ = try matches.deleteAll(source: .seed)

    var teamIDs: [EntityID: EntityID] = [:]
    var existingTeams = try teams.list()
    for team in seed.teams.sorted(by: { $0.sortOrder < $1.sortOrder }) {
      if let found = existingTeams.first(where: { searchKey($0.name) == searchKey(team.name) }) {
        teamIDs[team.id] = found.id
      } else {
        var draft = TeamDraft(team)
        draft.isFirstTeam = false
        let created = try teams.create(draft)
        existingTeams.append(created)
        teamIDs[team.id] = created.id
      }
    }

    var opponentIDs: [EntityID: EntityID] = [:]
    var existingOpponents = try opponents.list()
    for opponent in seed.opponents {
      if let found = existingOpponents.first(where: { searchKey($0.name) == searchKey(opponent.name) }) {
        opponentIDs[opponent.id] = found.id
        continue
      }
      var logoFile: String?
      if let source = opponent.logoFile {
        logoFile = try await logos.importLogo(from: seed.logosFolder.appendingPathComponent(source), replacing: nil)
      }
      let draft = OpponentDraft(
        name: opponent.name, shortName: opponent.shortName, aliases: opponent.aliases, logoFile: logoFile)
      let created = try opponents.create(draft)
      existingOpponents.append(created)
      opponentIDs[opponent.id] = created.id
    }

    var inserted = 0
    for generated in generateMatches(today: today) {
      guard let teamID = teamIDs[generated.teamID], let opponentID = opponentIDs[generated.opponentID] else {
        continue
      }
      var draft = MatchDraft(generated)
      draft.teamID = teamID
      draft.opponentID = opponentID
      draft.source = .seed
      draft.isLocked = false
      _ = try matches.create(draft)
      inserted += 1
    }
    return DemoDataSummary(teams: seed.teams.count, opponents: seed.opponents.count, matches: inserted)
  }

  /// Removes every `.seed` match, then the seed opponents and teams that no other match uses, with
  /// their logo files.
  ///
  /// The repositories refuse some deletes with `AppError.conflict`: an opponent or team that still has
  /// matches, and the first team while other teams exist. Those are skipped, so the first team is
  /// tried last and stays when the user has other teams.
  public func remove() throws {
    let seed = try SeedCatalog(folder: seedFolder)
    _ = try matches.deleteAll(source: .seed)

    let demoOpponents = Set(seed.opponents.map { searchKey($0.name) })
    for opponent in try opponents.list() where demoOpponents.contains(searchKey(opponent.name)) {
      do {
        try opponents.delete(id: opponent.id)
      } catch AppError.conflict {
        continue
      }
      if let logoFile = opponent.logoFile {
        try logos.remove(fileName: logoFile)
      }
    }

    let demoTeams = Set(seed.teams.map { searchKey($0.name) })
    let candidates = try teams.list().filter { demoTeams.contains(searchKey($0.name)) }
    for team in candidates.sorted(by: { !$0.isFirstTeam && $1.isFirstTeam }) {
      do {
        try teams.delete(id: team.id)
      } catch AppError.conflict {
        continue
      }
    }
  }

  public func hasDemoData() throws -> Bool {
    try matches.count(source: .seed) > 0
  }
}
