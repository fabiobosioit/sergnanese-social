import Foundation

// T4.11: tuttocampo season import. One run reads every matchday of one team's widget, one page at a time:
//
// 1. the UI shows `SeasonEstimate` for the ticked teams and the chosen `SeasonScope`;
// 2. after "Avvia", `FixtureSource.fetchSeason(for:settings:scope:onProgress:)` once per team, in turn; the
//    real source builds each page with its parser and hands the loop to `readSeason(scope:readPage:onProgress:)`,
//    so the fake and the real source follow the same order, stop rules and cancellation;
// 3. `ImportIssue.seasonNotices(team:fetch:clubShortName:)` for the report, `ImportCandidate.make` for every
//    fixture, then the usual review, `upsertFromImport` and logo download (deduplicated by ClubId over the run).

/// Which matchdays a season run reads. "Questo weekend" is not a season run: it is `fetchFixtures`.
public enum SeasonScope: String, Sendable, Codable, CaseIterable {
  /// "Da oggi a fine stagione": the default matchday (the site's current one), then the following ones up to the last.
  case fromCurrentMatchday
  /// "Tutta la stagione": the default matchday, then every other one from 1 to the last, results included.
  case wholeSeason
}

/// Hard limits of season runs (decisions 4 and 6 of T4.11).
public enum SeasonLimits {
  /// The highest matchday read for one team, whatever the page head says.
  public static let maxMatchdaysPerTeam = 60
  /// The most pages one run may request over all its teams. Enforced by the caller, which counts
  /// `SeasonProgress.pagesRead` and cancels the team being read when the total reaches it.
  public static let maxPagesPerRun = 400
  /// A team's run stops after this many unreadable matchdays in a row (`SeasonFetch.stoppedAfter`).
  public static let failuresInARowToStop = 3
  /// Seconds one page costs on average: the 1 s spacing between requests plus the response (T4.11 spike: about
  /// 1.3 s). Used by `SeasonEstimate` only.
  public static let secondsPerPage = 1.5
  /// Matchdays assumed for a team whose season length is not known yet (no earlier season run).
  public static let assumedMatchdays = 30
}

/// What a season run learnt about a team's league: kept by the UI after a run (`SeasonFetch.length`) to estimate
/// the next one.
public struct SeasonLength: Sendable, Codable, Equatable, Hashable {
  /// The site's current matchday (`currentMatchDay` of the default page).
  public var currentMatchday: Int
  /// The last matchday (`SeasonFetch.lastMatchday`).
  public var lastMatchday: Int

  public init(currentMatchday: Int, lastMatchday: Int) {
    self.currentMatchday = currentMatchday
    self.lastMatchday = lastMatchday
  }

  /// The matchdays `scope` reads after the default page, in request order: ascending, without the current one.
  /// `.fromCurrentMatchday`: `currentMatchday + 1 ... lastMatchday`; `.wholeSeason`: `1 ... lastMatchday`.
  /// `lastMatchday` is capped at `SeasonLimits.maxMatchdaysPerTeam`.
  public func otherMatchdays(_ scope: SeasonScope) -> [Int] {
    let last = min(lastMatchday, SeasonLimits.maxMatchdaysPerTeam)
    let first = scope == .wholeSeason ? 1 : currentMatchday + 1
    guard first <= last else { return [] }
    return (first...last).filter { $0 != currentMatchday }
  }

  /// The pages a run of `scope` requests when every page is read: the default page plus `otherMatchdays`.
  public func pages(_ scope: SeasonScope) -> Int { 1 + otherMatchdays(scope).count }
}

/// Progress of one team's season run, reported after each page.
public struct SeasonProgress: Sendable, Equatable, Hashable {
  /// The matchday of the page just read (or failed).
  public var matchday: Int
  /// The season's last matchday; `nil` while it is not known (the page head has no `matchesNumber`).
  public var lastMatchday: Int?
  /// Pages requested so far for this team, this one included (1 after the default page).
  public var pagesRead: Int
  /// The pages this run requests for the team when nothing stops it (`SeasonLength.pages`); `nil` while
  /// `lastMatchday` is not known. With `pagesRead` it drives a determinate progress bar.
  public var pagesTotal: Int?

  public init(matchday: Int, lastMatchday: Int?, pagesRead: Int, pagesTotal: Int?) {
    self.matchday = matchday
    self.lastMatchday = lastMatchday
    self.pagesRead = pagesRead
    self.pagesTotal = pagesTotal
  }
}

/// A matchday page that could not be read (network, timeout, HTTP error, size cap, address not allowed).
public struct MatchdayFailure: Sendable, Equatable, Hashable {
  public var matchday: Int
  public var error: FixtureFetchError

  public init(matchday: Int, error: FixtureFetchError) {
    self.matchday = matchday
    self.error = error
  }
}

/// A matchday page that was read but cannot be trusted. Always `.structureChanged`: a page without rows of ours
/// is a bye, not a problem.
public struct MatchdayProblem: Sendable, Equatable, Hashable {
  /// `nil` only for the default page when its matchday number could not be read.
  public var matchday: Int?
  public var problem: FixtureHealthProblem

  public init(matchday: Int?, problem: FixtureHealthProblem) {
    self.matchday = matchday
    self.problem = problem
  }
}

/// The outcome of one team's season run (`FixtureSource.fetchSeason`). Partial results are normal: a failed
/// matchday, a stop or a cancellation keeps every row already read.
public struct SeasonFetch: Sendable, Equatable, Hashable {
  /// Our matches, by date; one per date (a later-read page replaces an earlier one). A fixture whose page
  /// gave no round gets the page's matchday.
  public var fixtures: [FetchedFixture]
  /// Matchdays whose page had a results table but no row of ours ("Giornata 8: riposo"), ascending.
  public var byes: [Int]
  /// The default page's `currentMatchDay`; `nil` when the run gave no season (not yet available, the default page
  /// unusable, or cancelled before it was read).
  public var currentMatchday: Int?
  /// The season's last matchday: `matchesNumber` of the default page, capped at
  /// `SeasonLimits.maxMatchdaysPerTeam`; when the head has none, the highest matchday read whose page had a results
  /// table. `nil` exactly when `currentMatchday` is `nil`.
  public var lastMatchday: Int?
  /// Unreadable pages, ascending by matchday.
  public var failedMatchdays: [MatchdayFailure]
  /// Pages read but not trusted, ascending by matchday (`nil` first).
  public var problems: [MatchdayProblem]
  /// Set when matchdays of the scope were left unread: by `SeasonLimits.failuresInARowToStop` failures in a row
  /// (the last of them), or by cancellation (the last page requested before it; callers tell the two apart with
  /// `Task.isCancelled`). `nil` when every page of the scope was requested, or the run ended at the season's end,
  /// or before the default page was read.
  public var stoppedAfter: Int?
  /// The default page showed "Risultati non ancora disponibili.": everything else is empty. Information.
  public var notYetAvailable: Bool
  /// Pages requested, failed ones included (not one interrupted by cancellation). The request count of the run.
  public var pagesRead: Int

  public init(
    fixtures: [FetchedFixture] = [], byes: [Int] = [], currentMatchday: Int? = nil, lastMatchday: Int? = nil,
    failedMatchdays: [MatchdayFailure] = [], problems: [MatchdayProblem] = [], stoppedAfter: Int? = nil,
    notYetAvailable: Bool = false, pagesRead: Int = 0
  ) {
    self.fixtures = fixtures
    self.byes = byes
    self.currentMatchday = currentMatchday
    self.lastMatchday = lastMatchday
    self.failedMatchdays = failedMatchdays
    self.problems = problems
    self.stoppedAfter = stoppedAfter
    self.notYetAvailable = notYetAvailable
    self.pagesRead = pagesRead
  }

  /// What the next estimate uses for this team; `nil` when the run gave no season.
  public var length: SeasonLength? {
    guard let currentMatchday, let lastMatchday else { return nil }
    return SeasonLength(currentMatchday: currentMatchday, lastMatchday: lastMatchday)
  }
}

/// One results page as a source read it, for `readSeason`.
public struct SeasonPage: Sendable, Equatable, Hashable {
  /// `currentMatchDay` of the page head (`var currentMatchDay='11'`); on a matchday page it echoes the requested
  /// number. `nil` when absent or not a positive number.
  public var matchday: Int?
  /// `matchesNumber` of the page head: the number of matchdays of the season (T4.11 spike). `nil` when absent,
  /// empty (the empty state has `''`) or not a positive number.
  public var matchdayCount: Int?
  /// The page as `fetchFixtures` would return it: our rows, the empty state, or a problem. `.fixtures([])` and
  /// `.sourceProblem(.noFixturesOfOurs)` both mean a bye.
  public var outcome: FixtureFetch

  public init(matchday: Int?, matchdayCount: Int?, outcome: FixtureFetch) {
    self.matchday = matchday
    self.matchdayCount = matchdayCount
    self.outcome = outcome
  }
}

/// The season loop shared by every `FixtureSource` (T4.11). `readPage(nil)` reads the default matchday,
/// `readPage(n)` matchday `n` (the real source sends `/<id>/<n>?y=<season>`); it throws `FixtureFetchError` or
/// `CancellationError` (any other error counts as `.network`). Pages are read one at a time, in this order:
///
/// 1. The default page. It throws its `FixtureFetchError`: the team gave nothing. Cancelled before or during it:
///    an empty `SeasonFetch` (`pagesRead` 0). `.notYetAvailable`: `notYetAvailable`, nothing else.
///    `.sourceProblem(.structureChanged)`, or a table without a readable `matchday`: one `MatchdayProblem` (with
///    the page's matchday, or `nil`), nothing else. Otherwise it gives `currentMatchday`, `lastMatchday` (from
///    `matchdayCount`, capped) and its rows or bye.
/// 2. With a known `lastMatchday`: `SeasonLength.otherMatchdays(scope)`, ascending.
///    Without one (no `matchesNumber`): with `.wholeSeason`, `1 ..< current` first; then `current + 1`, `+ 2`, …
///    up to `SeasonLimits.maxMatchdaysPerTeam`, ending (no issue) at the first such page that is
///    `.notYetAvailable` or `.structureChanged`; `lastMatchday` is then the highest matchday with a results table.
///
/// Each other page: rows → `fixtures` (round filled with `n` when `nil`, within `1...FieldLimits.maxRound`); no row
/// of ours → `byes`; `FixtureFetchError` → `failedMatchdays`; `.structureChanged`, `.notYetAvailable` (inside the
/// season) or a head `matchday` other than `n` (the site ignored the number) → `problems` with `.structureChanged`.
/// Failures and problems in a row count toward `SeasonLimits.failuresInARowToStop`; a readable page resets the
/// count. At the limit the run stops with `stoppedAfter`.
///
/// Cancellation is checked before every request and after a request that throws: the run stops before the next
/// request and returns what it read, with `stoppedAfter` = the last matchday requested. It never throws
/// `CancellationError`. `onProgress` is awaited after every page, the default page included unless it ends the run.
public func readSeason(
  scope: SeasonScope,
  readPage: @Sendable (_ matchday: Int?) async throws -> SeasonPage,
  onProgress: @Sendable (SeasonProgress) async -> Void
) async throws -> SeasonFetch {
  var result = SeasonFetch()
  guard !Task.isCancelled else { return result }

  let first: SeasonPage
  do {
    first = try await readPage(nil)
  } catch {
    if Task.isCancelled || error is CancellationError { return result }
    throw (error as? FixtureFetchError) ?? .network
  }
  result.pagesRead = 1

  var byDate: [DayDate: FetchedFixture] = [:]
  func keep(_ fixtures: [FetchedFixture], matchday: Int) {
    for var fixture in fixtures {
      if fixture.round == nil, (1...FieldLimits.maxRound).contains(matchday) { fixture.round = matchday }
      byDate[fixture.date] = fixture
    }
  }

  switch first.outcome {
  case .notYetAvailable:
    result.notYetAvailable = true
    return result
  case .sourceProblem(.structureChanged):
    result.problems = [MatchdayProblem(matchday: first.matchday, problem: .structureChanged)]
    return result
  case .fixtures, .sourceProblem(.noFixturesOfOurs):
    break
  }
  guard let current = first.matchday, current >= 1 else {
    result.problems = [MatchdayProblem(matchday: nil, problem: .structureChanged)]
    return result
  }
  let knownLast = first.matchdayCount.map { min($0, SeasonLimits.maxMatchdaysPerTeam) }
  var highestWithTable = current
  result.currentMatchday = current
  if case .fixtures(let fixtures) = first.outcome, !fixtures.isEmpty {
    keep(fixtures, matchday: current)
  } else {
    result.byes.append(current)
  }

  let targets: [Int]
  let pagesTotal: Int?
  if let knownLast {
    let length = SeasonLength(currentMatchday: current, lastMatchday: knownLast)
    targets = length.otherMatchdays(scope)
    pagesTotal = length.pages(scope)
  } else {
    let below = scope == .wholeSeason ? Array(1..<min(current, SeasonLimits.maxMatchdaysPerTeam + 1)) : []
    let above =
      current < SeasonLimits.maxMatchdaysPerTeam ? Array((current + 1)...SeasonLimits.maxMatchdaysPerTeam) : []
    targets = below + above
    pagesTotal = nil
  }
  await onProgress(
    SeasonProgress(matchday: current, lastMatchday: knownLast, pagesRead: 1, pagesTotal: pagesTotal))

  var lastRequested = current
  var failuresInARow = 0
  for matchday in targets {
    if Task.isCancelled {
      result.stoppedAfter = lastRequested
      break
    }
    let probingEnd = knownLast == nil && matchday > current
    let page: SeasonPage
    do {
      page = try await readPage(matchday)
    } catch {
      if Task.isCancelled || error is CancellationError {
        result.stoppedAfter = lastRequested
        break
      }
      result.pagesRead += 1
      lastRequested = matchday
      result.failedMatchdays.append(
        MatchdayFailure(matchday: matchday, error: (error as? FixtureFetchError) ?? .network))
      failuresInARow += 1
      await onProgress(
        SeasonProgress(
          matchday: matchday, lastMatchday: knownLast, pagesRead: result.pagesRead, pagesTotal: pagesTotal))
      if failuresInARow >= SeasonLimits.failuresInARowToStop {
        result.stoppedAfter = matchday
        break
      }
      continue
    }
    result.pagesRead += 1
    lastRequested = matchday

    var trusted = true
    var seasonEnded = false
    if let echoed = page.matchday, echoed != matchday {
      trusted = false
    } else {
      switch page.outcome {
      case .fixtures(let fixtures) where !fixtures.isEmpty:
        keep(fixtures, matchday: matchday)
      case .fixtures, .sourceProblem(.noFixturesOfOurs):
        result.byes.append(matchday)
      case .notYetAvailable, .sourceProblem(.structureChanged):
        if probingEnd { seasonEnded = true } else { trusted = false }
      }
    }
    if seasonEnded { break }
    if trusted {
      failuresInARow = 0
      highestWithTable = max(highestWithTable, matchday)
    } else {
      result.problems.append(MatchdayProblem(matchday: matchday, problem: .structureChanged))
      failuresInARow += 1
    }
    await onProgress(
      SeasonProgress(
        matchday: matchday, lastMatchday: knownLast, pagesRead: result.pagesRead, pagesTotal: pagesTotal))
    if failuresInARow >= SeasonLimits.failuresInARowToStop {
      result.stoppedAfter = matchday
      break
    }
  }

  result.lastMatchday = knownLast ?? highestWithTable
  result.fixtures = byDate.values.sorted { $0.date < $1.date }
  result.byes.sort()
  result.failedMatchdays.sort { $0.matchday < $1.matchday }
  result.problems.sort { ($0.matchday ?? 0) < ($1.matchday ?? 0) }
  return result
}

/// "circa N richieste, circa M minuti" for the start panel (decision 3 of T4.11).
public struct SeasonEstimate: Sendable, Equatable, Hashable {
  /// Pages over every team.
  public var requests: Int
  /// `requests × SeasonLimits.secondsPerPage`, in minutes rounded up; 0 only when `requests` is 0.
  public var minutes: Int

  public init(requests: Int, minutes: Int) {
    self.requests = requests
    self.minutes = minutes
  }

  /// One entry per ticked team: its `SeasonLength` from the last season run, or `nil` when there was none, which
  /// counts `SeasonLimits.assumedMatchdays` pages. A known length counts `SeasonLength.pages(scope)`.
  public init(scope: SeasonScope, teams: [SeasonLength?]) {
    let requests = teams.reduce(0) { $0 + ($1?.pages(scope) ?? SeasonLimits.assumedMatchdays) }
    let seconds = Double(requests) * SeasonLimits.secondsPerPage
    self.init(requests: requests, minutes: Int((seconds / 60).rounded(.up)))
  }

  /// "circa 31 richieste, circa 1 minuto".
  public var message: String { CoreStrings.seasonEstimate(requests: requests, minutes: minutes) }
}
