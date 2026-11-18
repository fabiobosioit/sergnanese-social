import Foundation
import SSCore

/// "Carica dati demo" on the fakes: inserts the fixture data set, moved to the weekend of `today`,
/// through the repository protocols. Teams and opponents are matched by name, so loading twice
/// leaves the same number of rows; every inserted match has source `.seed`.
public struct FakeDemoDataLoader: DemoDataLoader {
  let dataSet: FakeDataSet
  let teams: any TeamRepository
  let opponents: any OpponentRepository
  let matches: any MatchRepository

  public init(
    dataSet: FakeDataSet, teams: any TeamRepository, opponents: any OpponentRepository, matches: any MatchRepository
  ) {
    self.dataSet = dataSet
    self.teams = teams
    self.opponents = opponents
    self.matches = matches
  }

  public func load(today: DayDate) async throws -> DemoDataSummary {
    _ = try matches.deleteAll(source: .seed)
    let data = dataSet.shifted(toWeekendOf: today)

    var teamIDs: [EntityID: EntityID] = [:]
    var existingTeams = try teams.list()
    for team in data.teams.sorted(by: { $0.sortOrder < $1.sortOrder }) {
      if let found = existingTeams.first(where: { searchKey($0.name) == searchKey(team.name) }) {
        teamIDs[team.id] = found.id
      } else {
        // Never take the flag from an existing first team; `create` gives it to the first team
        // created when there is none.
        var draft = TeamDraft(team)
        draft.isFirstTeam = false
        let created = try teams.create(draft)
        existingTeams.append(created)
        teamIDs[team.id] = created.id
      }
    }

    var opponentIDs: [EntityID: EntityID] = [:]
    var existingOpponents = try opponents.list()
    for opponent in data.opponents {
      if let found = existingOpponents.first(where: { searchKey($0.name) == searchKey(opponent.name) }) {
        opponentIDs[opponent.id] = found.id
      } else {
        let created = try opponents.create(OpponentDraft(opponent))
        existingOpponents.append(created)
        opponentIDs[opponent.id] = created.id
      }
    }

    var inserted = 0
    for match in data.matches {
      guard let teamID = teamIDs[match.teamID], let opponentID = opponentIDs[match.opponentID] else { continue }
      var draft = MatchDraft(match)
      draft.teamID = teamID
      draft.opponentID = opponentID
      draft.source = .seed
      _ = try matches.create(draft)
      inserted += 1
    }
    return DemoDataSummary(teams: data.teams.count, opponents: data.opponents.count, matches: inserted)
  }

  public func remove() throws {
    _ = try matches.deleteAll(source: .seed)
    let demoOpponents = Set(dataSet.opponents.map { searchKey($0.name) })
    for opponent in try opponents.list() where demoOpponents.contains(searchKey(opponent.name)) {
      do { try opponents.delete(id: opponent.id) } catch AppError.conflict { continue }
    }
    let demoTeams = Set(dataSet.teams.map { searchKey($0.name) })
    for team in try teams.list() where demoTeams.contains(searchKey(team.name)) {
      do { try teams.delete(id: team.id) } catch AppError.conflict { continue }
    }
  }

  public func hasDemoData() throws -> Bool { try matches.count(source: .seed) > 0 }
}
