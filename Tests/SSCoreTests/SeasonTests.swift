import Foundation
import SSCoreFakes
import Testing

@testable import SSCore

/// Records the pages a season run asks for.
actor PageLog {
  var requested: [Int?] = []
  var progress: [SeasonProgress] = []
  func add(_ matchday: Int?) { requested.append(matchday) }
  func add(_ step: SeasonProgress) { progress.append(step) }
}

/// A canned page per matchday for `readSeason`; `nil` key = the default page.
enum StubPage: Sendable {
  case rows([FetchedFixture])
  case bye
  case empty
  case changed
  case failure(FixtureFetchError)
  /// A page whose head names another matchday.
  case echo(Int)
}

let seasonSunday = DayDate(year: 2026, month: 11, day: 22)!

func stubFixture(_ matchday: Int, round: Int? = nil, name: String = "Avversario") -> FetchedFixture {
  FetchedFixture(
    date: seasonSunday.adding(days: 7 * (matchday - 5)), time: ClockTime(hour: 15, minute: 0), isHome: true,
    opponentName: name, round: round, status: .scheduled, statusText: "Partita da giocare")
}

/// Runs `readSeason` over `pages` (missing matchdays are rows against "Avversario <n>"). `cancelAt` cancels the
/// running task while that matchday is read (the page is still returned).
func runSeason(
  scope: SeasonScope, current: Int = 5, count: Int? = 10, pages: [Int: StubPage] = [:], cancelAt: Int? = nil,
  log: PageLog = PageLog()
) async throws -> SeasonFetch {
  try await readSeason(
    scope: scope,
    readPage: { requested in
      await log.add(requested)
      let matchday = requested ?? current
      if matchday == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
      let head = requested == nil ? current : matchday
      switch pages[matchday] ?? .rows([stubFixture(matchday, name: "Avversario \(matchday)")]) {
      case .rows(let rows): return SeasonPage(matchday: head, matchdayCount: count, outcome: .fixtures(rows))
      case .bye: return SeasonPage(matchday: head, matchdayCount: count, outcome: .sourceProblem(.noFixturesOfOurs))
      case .empty: return SeasonPage(matchday: head, matchdayCount: count, outcome: .notYetAvailable)
      case .changed: return SeasonPage(matchday: head, matchdayCount: count, outcome: .sourceProblem(.structureChanged))
      case .failure(let error): throw error
      case .echo(let other): return SeasonPage(matchday: other, matchdayCount: count, outcome: .fixtures([]))
      }
    }, onProgress: { await log.add($0) })
}

@Suite struct SeasonLengthTests {
  @Test func otherMatchdaysAndPages() {
    let length = SeasonLength(currentMatchday: 5, lastMatchday: 10)
    #expect(length.otherMatchdays(.fromCurrentMatchday) == [6, 7, 8, 9, 10])
    #expect(length.otherMatchdays(.wholeSeason) == [1, 2, 3, 4, 6, 7, 8, 9, 10])
    #expect(length.pages(.fromCurrentMatchday) == 6)
    #expect(length.pages(.wholeSeason) == 10)
    let over = SeasonLength(currentMatchday: 12, lastMatchday: 10)
    #expect(over.pages(.fromCurrentMatchday) == 1)
    #expect(over.pages(.wholeSeason) == 11)
    let huge = SeasonLength(currentMatchday: 1, lastMatchday: 100)
    #expect(huge.otherMatchdays(.wholeSeason).last == SeasonLimits.maxMatchdaysPerTeam)
    #expect(huge.pages(.wholeSeason) == 60)
  }

  @Test func estimate() {
    let known = SeasonLength(currentMatchday: 5, lastMatchday: 10)
    let whole = SeasonEstimate(scope: .wholeSeason, teams: [nil, known])
    #expect(whole == SeasonEstimate(requests: 40, minutes: 1))
    #expect(whole.message == "circa 40 richieste, circa 1 minuto")
    let many = SeasonEstimate(scope: .wholeSeason, teams: Array(repeating: nil, count: 8))
    #expect(many == SeasonEstimate(requests: 240, minutes: 6))
    #expect(many.message == "circa 240 richieste, circa 6 minuti")
    let one = SeasonEstimate(scope: .fromCurrentMatchday, teams: [SeasonLength(currentMatchday: 10, lastMatchday: 10)])
    #expect(one.message == "circa 1 richiesta, circa 1 minuto")
    #expect(SeasonEstimate(scope: .wholeSeason, teams: []) == SeasonEstimate(requests: 0, minutes: 0))
  }

  @Test func lengthOfAFetch() {
    #expect(SeasonFetch().length == nil)
    #expect(
      SeasonFetch(currentMatchday: 3, lastMatchday: 30).length == SeasonLength(currentMatchday: 3, lastMatchday: 30))
  }
}

@Suite struct ReadSeasonTests {
  @Test func wholeSeasonReadsTheDefaultPageThenAscending() async throws {
    let log = PageLog()
    let fetch = try await runSeason(
      scope: .wholeSeason, pages: [7: .bye, 3: .failure(.timeout)], log: log)
    #expect(await log.requested == [nil, 1, 2, 3, 4, 6, 7, 8, 9, 10])
    #expect(fetch.pagesRead == 10)
    #expect(fetch.currentMatchday == 5 && fetch.lastMatchday == 10)
    #expect(fetch.byes == [7])
    #expect(fetch.failedMatchdays == [MatchdayFailure(matchday: 3, error: .timeout)])
    #expect(fetch.problems.isEmpty && fetch.stoppedAfter == nil && !fetch.notYetAvailable)
    #expect(fetch.fixtures.map(\.round) == [1, 2, 4, 5, 6, 8, 9, 10])
    #expect(fetch.fixtures.map(\.date) == fetch.fixtures.map(\.date).sorted())
    let progress = await log.progress
    #expect(progress.map(\.matchday) == [5, 1, 2, 3, 4, 6, 7, 8, 9, 10])
    #expect(progress.map(\.pagesRead) == Array(1...10))
    #expect(progress.allSatisfy { $0.pagesTotal == 10 && $0.lastMatchday == 10 })
  }

  @Test func fromCurrentReadsTheRest() async throws {
    let log = PageLog()
    let fetch = try await runSeason(scope: .fromCurrentMatchday, log: log)
    #expect(await log.requested == [nil, 6, 7, 8, 9, 10])
    #expect(fetch.fixtures.count == 6 && fetch.pagesRead == 6)
    #expect(await log.progress.allSatisfy { $0.pagesTotal == 6 })
  }

  @Test func aRoundFromThePageIsKeptAndTheLaterPageWinsADate() async throws {
    let fetch = try await runSeason(
      scope: .fromCurrentMatchday, current: 9,
      pages: [9: .rows([stubFixture(9, round: 30, name: "Primo")]), 10: .rows([stubFixture(9, name: "Secondo")])])
    #expect(fetch.fixtures.map(\.opponentName) == ["Secondo"])
    #expect(fetch.fixtures.first?.round == 10)
    let kept = try await runSeason(
      scope: .fromCurrentMatchday, current: 10, pages: [10: .rows([stubFixture(10, round: 30)])])
    #expect(kept.fixtures.first?.round == 30)
  }

  @Test func theDefaultPageDecidesWhetherThereIsASeason() async throws {
    await #expect(throws: FixtureFetchError.httpStatus(500)) {
      try await runSeason(scope: .wholeSeason, pages: [5: .failure(.httpStatus(500))])
    }
    let log = PageLog()
    let empty = try await runSeason(scope: .wholeSeason, pages: [5: .empty], log: log)
    #expect(empty == SeasonFetch(notYetAvailable: true, pagesRead: 1))
    let emptyProgress = await log.progress
    #expect(await log.requested == [nil])
    #expect(emptyProgress.isEmpty)
    let changed = try await runSeason(scope: .wholeSeason, pages: [5: .changed])
    #expect(changed == SeasonFetch(problems: [MatchdayProblem(matchday: 5, problem: .structureChanged)], pagesRead: 1))
    let bye = try await runSeason(scope: .fromCurrentMatchday, pages: [5: .bye])
    #expect(bye.byes == [5] && bye.pagesRead == 6)
  }

  @Test func aDefaultPageWithoutItsNumberIsAProblem() async throws {
    let fetch = try await readSeason(
      scope: .wholeSeason,
      readPage: { _ in SeasonPage(matchday: nil, matchdayCount: 10, outcome: .fixtures([stubFixture(5)])) },
      onProgress: { _ in })
    #expect(fetch == SeasonFetch(problems: [MatchdayProblem(matchday: nil, problem: .structureChanged)], pagesRead: 1))
  }

  @Test func threeFailuresInARowStopTheTeam() async throws {
    let log = PageLog()
    let fetch = try await runSeason(
      scope: .fromCurrentMatchday, current: 1,
      pages: [2: .failure(.network), 3: .rows([]), 4: .failure(.network), 5: .changed, 6: .echo(1), 7: .bye],
      log: log)
    #expect(await log.requested == [nil, 2, 3, 4, 5, 6])
    #expect(fetch.stoppedAfter == 6)
    #expect(fetch.byes == [3])
    #expect(fetch.failedMatchdays.map(\.matchday) == [2, 4])
    #expect(fetch.problems == [5, 6].map { MatchdayProblem(matchday: $0, problem: .structureChanged) })
    #expect(fetch.lastMatchday == 10)
  }

  @Test func anEmptyPageInsideTheSeasonIsAProblem() async throws {
    let fetch = try await runSeason(scope: .fromCurrentMatchday, pages: [8: .empty])
    #expect(fetch.problems == [MatchdayProblem(matchday: 8, problem: .structureChanged)])
    #expect(fetch.pagesRead == 6)
  }

  @Test func withoutMatchesNumberTheEndIsFound() async throws {
    let log = PageLog()
    let fetch = try await runSeason(scope: .wholeSeason, current: 3, count: nil, pages: [7: .empty], log: log)
    #expect(await log.requested == [nil, 1, 2, 4, 5, 6, 7])
    #expect(fetch.lastMatchday == 6 && fetch.stoppedAfter == nil && fetch.problems.isEmpty)
    #expect(await log.progress.allSatisfy { $0.pagesTotal == nil && $0.lastMatchday == nil })
    let capped = PageLog()
    let open = try await runSeason(scope: .fromCurrentMatchday, current: 58, count: nil, log: capped)
    #expect(await capped.requested == [nil, 59, 60])
    #expect(open.lastMatchday == 60)
  }

  @Test func matchesNumberIsCapped() async throws {
    let log = PageLog()
    let fetch = try await runSeason(scope: .fromCurrentMatchday, current: 59, count: 99, log: log)
    #expect(await log.requested == [nil, 60])
    #expect(fetch.lastMatchday == 60)
  }

  @Test func cancellationReturnsWhatWasRead() async throws {
    let log = PageLog()
    let fetch = try await Task { try await runSeason(scope: .wholeSeason, cancelAt: 3, log: log) }.value
    #expect(await log.requested == [nil, 1, 2, 3])
    #expect(fetch.stoppedAfter == 3 && fetch.pagesRead == 4)
    #expect(fetch.fixtures.count == 4)

    let before = PageLog()
    let none = try await Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await runSeason(scope: .wholeSeason, log: before)
    }.value
    let noRequests = await before.requested
    #expect(none == SeasonFetch() && noRequests.isEmpty)
  }

  @Test func aRequestInterruptedByCancellationIsNotAFailure() async throws {
    let fetch = try await Task {
      try await readSeason(
        scope: .fromCurrentMatchday,
        readPage: { requested in
          guard let requested else { return SeasonPage(matchday: 5, matchdayCount: 10, outcome: .fixtures([])) }
          withUnsafeCurrentTask { $0?.cancel() }
          _ = requested
          throw FixtureFetchError.network
        }, onProgress: { _ in })
    }.value
    #expect(fetch.failedMatchdays.isEmpty && fetch.stoppedAfter == 5 && fetch.pagesRead == 1 && fetch.byes == [5])
  }
}

@Suite struct SeasonIssueTests {
  @Test func messages() {
    #expect(ImportIssue.seasonBye(team: "Pulcini", matchday: 8).message == "Pulcini, giornata 8: riposo.")
    #expect(!ImportIssue.seasonBye(team: "Pulcini", matchday: 8).isError)
    #expect(
      ImportIssue.seasonMatchdayFailed(team: "Pulcini", matchday: 3, reason: .timeout).message
        == "Tuttocampo: impossibile leggere la giornata 3 di Pulcini. Il sito non ha risposto in tempo: riprova più tardi."
    )
    #expect(
      ImportIssue.seasonMatchdayChanged(team: "Pulcini", matchday: 4).message
        == "Tuttocampo: impossibile leggere la giornata 4 di Pulcini. La sorgente potrebbe essere cambiata.")
    #expect(
      ImportIssue.seasonStopped(team: "Pulcini", afterMatchday: 6).message
        == "Tuttocampo: lettura di Pulcini interrotta dopo la giornata 6.")
    #expect(ImportIssue.seasonMatchdayFailed(team: "P", matchday: 1, reason: .network).isError)
    #expect(ImportIssue.seasonMatchdayChanged(team: "P", matchday: 1).isError)
    #expect(ImportIssue.seasonStopped(team: "P", afterMatchday: 1).isError)
  }

  @Test func notices() {
    let fetch = SeasonFetch(
      byes: [2, 9], currentMatchday: 1, lastMatchday: 10,
      failedMatchdays: [MatchdayFailure(matchday: 3, error: .network), MatchdayFailure(matchday: 6, error: .timeout)],
      problems: [MatchdayProblem(matchday: 4, problem: .structureChanged)], stoppedAfter: 6, pagesRead: 6)
    #expect(
      ImportIssue.seasonNotices(team: "P", fetch: fetch, clubShortName: "Sergnanese") == [
        .seasonMatchdayFailed(team: "P", matchday: 3, reason: .network), .seasonMatchdayChanged(team: "P", matchday: 4),
        .seasonMatchdayFailed(team: "P", matchday: 6, reason: .timeout), .seasonStopped(team: "P", afterMatchday: 6),
        .seasonBye(team: "P", matchday: 2), .seasonBye(team: "P", matchday: 9),
      ])
    #expect(
      ImportIssue.seasonNotices(team: "P", fetch: SeasonFetch(notYetAvailable: true, pagesRead: 1), clubShortName: "S")
        == [.notYetAvailable(team: "P")])
    let unusable = SeasonFetch(problems: [MatchdayProblem(matchday: nil, problem: .structureChanged)], pagesRead: 1)
    #expect(
      ImportIssue.seasonNotices(team: "P", fetch: unusable, clubShortName: "S") == [
        .sourceProblem(team: "P", problem: .structureChanged, clubShortName: "S")
      ])
    #expect(ImportIssue.seasonNotices(team: "P", fetch: SeasonFetch(), clubShortName: "S").isEmpty)
  }
}

@MainActor
@Suite struct FakeSeasonTests {
  let services: AppServices

  init() throws {
    services = try AppServices.fake(dataSet: Fixtures.dataSet().shifted(toWeekendOf: .today()), renderDelay: .zero)
  }

  func team(_ name: String) throws -> Team { try #require(try services.teams.list().first { $0.name == name }) }

  @Test func scenarioSeasonCoversEveryCase() async throws {
    let settings = try services.settings.load()
    let primiCalci = try team("Primi Calci")
    let log = PageLog()
    let fetch = try await services.fixtureSource.fetchSeason(
      for: primiCalci, settings: settings, scope: .wholeSeason, onProgress: { await log.add($0) })
    let steps = await log.progress
    #expect(fetch.pagesRead == 10 && steps.count == 10)
    #expect(fetch.byes == [7])
    #expect(fetch.failedMatchdays == [MatchdayFailure(matchday: 3, error: .timeout)])
    #expect(fetch.length == SeasonLength(currentMatchday: 5, lastMatchday: 10))
    let opponents = try services.opponents.list()
    let existing = try services.matches.list(
      from: fetch.fixtures[0].date, to: fetch.fixtures.last!.date, teamID: primiCalci.id)
    let states = fetch.fixtures.map {
      ImportCandidate.make(
        fixture: $0, team: primiCalci, opponents: opponents, existingMatches: existing, homeVenue: settings.homeVenue
      ).state
    }
    #expect(fetch.fixtures.map { $0.round ?? 0 } == [1, 2, 4, 5, 6, 8, 9, 10])
    #expect(states == [.new, .new, .new, .locked, .changed, .new, .needsReview, .new])
    #expect(fetch.fixtures.last?.time == nil)
    #expect(
      ImportIssue.seasonNotices(team: "Primi Calci", fetch: fetch, clubShortName: settings.clubShortName) == [
        .seasonMatchdayFailed(team: "Primi Calci", matchday: 3, reason: .timeout),
        .seasonBye(team: "Primi Calci", matchday: 7),
      ])

    let fromToday = try await services.fixtureSource.fetchSeason(
      for: primiCalci, settings: settings, scope: .fromCurrentMatchday, onProgress: { _ in })
    #expect(fromToday.pagesRead == 6 && fromToday.byes == [7] && fromToday.failedMatchdays.isEmpty)
    #expect(fromToday.fixtures.count == 5)
  }

  @Test func otherTeamsGiveTheirWeekendAnswer() async throws {
    let settings = try services.settings.load()
    let source = services.fixtureSource
    let prima = try await source.fetchSeason(
      for: try team("Prima Squadra"), settings: settings, scope: .wholeSeason, onProgress: { _ in })
    #expect(
      prima.pagesRead == 1 && prima.fixtures.count == 1
        && prima.length == SeasonLength(currentMatchday: 1, lastMatchday: 1))
    let u14 = try await source.fetchSeason(
      for: try team("Giovanissimi U14"), settings: settings, scope: .wholeSeason, onProgress: { _ in })
    #expect(u14.notYetAvailable)
    let u15 = try await source.fetchSeason(
      for: try team("Giovanissimi U15"), settings: settings, scope: .wholeSeason, onProgress: { _ in })
    #expect(u15.problems == [MatchdayProblem(matchday: 1, problem: .structureChanged)])
    await #expect(throws: FixtureFetchError.network) {
      try await source.fetchSeason(
        for: try team("Esordienti"), settings: settings, scope: .wholeSeason, onProgress: { _ in })
    }
    await #expect(throws: FixtureFetchError.missingWidgetID) {
      try await source.fetchSeason(
        for: try team("Veterani"), settings: settings, scope: .wholeSeason, onProgress: { _ in })
    }
  }

  @Test func unavailableSourceAndCancellation() async throws {
    let settings = try services.settings.load()
    await #expect(throws: FixtureFetchError.unavailable) {
      try await UnavailableFixtureSource().fetchSeason(
        for: try team("Primi Calci"), settings: settings, scope: .wholeSeason, onProgress: { _ in })
    }
    let source = FakeFixtureSource(
      logos: services.logos,
      seasons: [
        FakeFixtureSource.scenarioWidgetID(9): FakeFixtureSource.scenarioSeason(
          referenceSaturday: DayDate(year: 2026, month: 11, day: 21)!)
      ])
    let primiCalci = try team("Primi Calci")
    let fetch = try await Task {
      try await source.fetchSeason(
        for: primiCalci, settings: settings, scope: .wholeSeason,
        onProgress: { progress in if progress.pagesRead == 4 { withUnsafeCurrentTask { $0?.cancel() } } })
    }.value
    #expect(fetch.pagesRead == 4 && fetch.stoppedAfter == 3)
  }
}
