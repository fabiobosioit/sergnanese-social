import Foundation
import SSCore

@testable import SSData

func makeTempFolder() throws -> URL {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ss-data-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  return folder
}

func day(_ text: String) -> DayDate {
  guard let value = try? DayDate(text) else { fatalError("bad test date \(text)") }
  return value
}

func clock(_ text: String) -> ClockTime {
  guard let value = try? ClockTime(text) else { fatalError("bad test time \(text)") }
  return value
}

/// An in-memory database with two teams (the first one is the first team) and two opponents.
struct Fixture {
  let db: AppDatabase
  let first: Team
  let second: Team
  let rossi: Opponent
  let bianchi: Opponent

  init() throws {
    db = try AppDatabase.inMemory()
    first = try db.teams.create(TeamDraft(name: "Prima Squadra", shortLabel: "Prima", isFirstTeam: true))
    second = try db.teams.create(TeamDraft(name: "Juniores", shortLabel: "Juniores"))
    rossi = try db.opponents.create(OpponentDraft(name: "ASD Rossi"))
    bianchi = try db.opponents.create(OpponentDraft(name: "Àquila Bianchi", aliases: ["Aquila B."]))
  }

  func draft(
    team: Team? = nil, opponent: Opponent? = nil, date: String = "2026-11-21", time: String? = "15:00"
  ) -> MatchDraft {
    MatchDraft(
      teamID: (team ?? first).id, opponentID: (opponent ?? rossi).id, date: day(date), time: time.map(clock),
      isHome: true, venue: "Campo comunale")
  }
}
