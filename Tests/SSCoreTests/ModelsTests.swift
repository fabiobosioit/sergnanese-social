import Foundation
import Testing

@testable import SSCore

@Suite struct DayDateTests {
  @Test func parsesValidDates() throws {
    let date = try DayDate("2026-11-22")
    #expect(date.value == "2026-11-22")
    #expect(date.year == 2026 && date.month == 11 && date.day == 22)
    #expect(try DayDate("2028-02-29").day == 29)
  }

  @Test(arguments: ["", "2026-2-01", "2026-02-30", "2027-02-29", "26-11-22", "2026/11/22", "2026-13-01", "abcd-ef-gh"])
  func rejectsInvalidDates(_ text: String) {
    #expect(throws: AppError.self) { try DayDate(text) }
  }

  @Test func errorPointsAtTheDateField() {
    do {
      _ = try DayDate("ieri")
      Issue.record("expected an error")
    } catch let AppError.validation(field, message) {
      #expect(field == .date)
      #expect(message.contains("ieri"))
    } catch {
      Issue.record("unexpected error \(error)")
    }
  }

  @Test func weekdaysAndArithmetic() throws {
    #expect(try DayDate("2026-11-22").isoWeekday == 7)  // Sunday
    #expect(try DayDate("2026-11-21").isoWeekday == 6)  // Saturday
    #expect(try DayDate("1970-01-01").isoWeekday == 4)  // Thursday
    #expect(try DayDate("2026-12-31").adding(days: 1) == DayDate("2027-01-01"))
    #expect(try DayDate("2028-03-01").adding(days: -1) == DayDate("2028-02-29"))
    #expect(try DayDate("2026-11-22").adding(days: 7) == DayDate("2026-11-29"))
    #expect(try DayDate("2026-11-01").days(to: DayDate("2026-12-01")) == 30)
  }

  @Test func ordersAndCodes() throws {
    let early = try DayDate("2026-01-09")
    let late = try DayDate("2026-10-01")
    #expect(early < late)
    let data = try JSONEncoder().encode([early])
    #expect(String(decoding: data, as: UTF8.self) == "[\"2026-01-09\"]")
    #expect(try JSONDecoder().decode([DayDate].self, from: data) == [early])
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode([DayDate].self, from: Data("[\"2026-02-31\"]".utf8))
    }
  }

  @Test func convertsFromAndToDates() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
    let day = try DayDate("2026-03-29")  // the day the clocks change
    let start = day.startOfDay(in: calendar)
    #expect(DayDate(start, calendar: calendar) == day)
    #expect(DayDate(start.addingTimeInterval(23 * 3600 - 1), calendar: calendar) == day)
  }
}

@Suite struct ClockTimeTests {
  @Test func parsesAndNormalises() throws {
    #expect(try ClockTime("15:30").value == "15:30")
    #expect(try ClockTime("9:05").value == "09:05")
    #expect(try ClockTime(" 15.30 ").value == "15:30")
    #expect(try ClockTime("00:00").hour == 0)
    #expect(try ClockTime("23:59").minute == 59)
  }

  @Test(arguments: ["", "24:00", "12:60", "1530", "12:5", "ab:cd", "12:30:00"])
  func rejectsInvalidTimes(_ text: String) {
    #expect(throws: AppError.self) { try ClockTime(text) }
  }

  @Test func ordersAndCodes() throws {
    #expect(try ClockTime("09:30") < ClockTime("10:00"))
    let data = try JSONEncoder().encode(try ClockTime("9:30"))
    #expect(String(decoding: data, as: UTF8.self) == "\"09:30\"")
  }
}

@Suite struct WeekendTests {
  @Test func normalisesToSaturday() throws {
    let weekend = Weekend(saturday: try DayDate("2026-11-25"))  // a Wednesday
    #expect(weekend.saturday == (try DayDate("2026-11-21")))
    #expect(weekend.sunday == (try DayDate("2026-11-22")))
    #expect(weekend.contains(try DayDate("2026-11-22")))
    #expect(!weekend.contains(try DayDate("2026-11-23")))
    #expect(weekend.next.saturday == (try DayDate("2026-11-28")))
    #expect(weekend.previous.saturday == (try DayDate("2026-11-14")))
  }
}

@Suite struct MatchDetailOrderTests {
  func detail(_ id: String, _ date: String, _ time: String?, sortOrder: Int) throws -> MatchDetail {
    let team = Team(
      id: "t\(sortOrder)", name: "T", shortLabel: "T", sortOrder: sortOrder, isFirstTeam: false, isActive: true)
    let opponent = Opponent(id: "o", name: "O")
    let match = Match(
      id: id, teamID: team.id, opponentID: "o", date: try DayDate(date), time: try time.map { try ClockTime($0) },
      isHome: true, venue: "", createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    return MatchDetail(match: match, team: team, opponent: opponent)
  }

  @Test func ordersByDateTimeThenTeam() throws {
    let items = [
      try detail("e", "2026-11-22", nil, sortOrder: 0),
      try detail("d", "2026-11-22", "15:00", sortOrder: 2),
      try detail("c", "2026-11-22", "15:00", sortOrder: 1),
      try detail("b", "2026-11-22", "09:30", sortOrder: 5),
      try detail("a", "2026-11-21", "18:00", sortOrder: 9),
    ]
    #expect(items.sorted(by: MatchDetail.scheduleOrder).map(\.id) == ["a", "b", "c", "d", "e"])
  }
}

@Suite struct DraftTests {
  @Test func draftsRoundTripEntities() throws {
    let team = Team(id: "t", name: "Juniores", shortLabel: "Jun", sortOrder: 3, isFirstTeam: false, isActive: true)
    #expect(TeamDraft(team) == TeamDraft(name: "Juniores", shortLabel: "Jun", isFirstTeam: false, isActive: true))
    let opponent = Opponent(
      id: "o", name: "F.C. Valdorso", shortName: "Valdorso", aliases: ["Valdorso FC"], logoFile: "x.png")
    #expect(OpponentDraft(opponent).shortName == "Valdorso")
    let match = Match(
      id: "m", teamID: "t", opponentID: "o", date: try DayDate("2026-11-22"), time: nil, isHome: false,
      venue: "Campo", round: 4, status: .postponed, isLocked: true, createdAt: Date(), updatedAt: Date())
    let draft = MatchDraft(match)
    #expect(draft.round == 4 && draft.status == .postponed && draft.isLocked && !draft.isHome)
    #expect(draft.importKey == "t|2026-11-22")
  }

  @Test func pageLabel() {
    #expect(PageInfo(index: 2, total: 3).label == "2/3")
  }
}
