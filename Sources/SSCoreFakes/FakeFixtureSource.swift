import Foundation
import SSCore

/// A fixture source with canned answers per widget id, for `--mock`, previews and tests. No network.
///
/// `AppServices.fake()` uses `scenario(referenceSaturday:logos:)`, which covers every staging state
/// and every report line against the fixture data set (see the table there).
public struct FakeFixtureSource: FixtureSource {
  /// The canned answer for one widget.
  public enum Response: Sendable, Equatable {
    case fetch(FixtureFetch)
    case failure(FixtureFetchError)
  }

  /// Keyed by widget id in lower case. An id with no entry throws `FixtureFetchError.httpStatus(404)`.
  public var responses: [String: Response]
  public var logos: any LogoStore
  /// The bytes stored for every logo download that succeeds.
  public var logoData: Data
  /// ClubIds whose `Teams/200` copy "fails": their fallback is stored, with `.logoFallback`.
  public var fallbackClubIDs: Set<String>
  /// ClubIds whose downloads all "fail" (`.logoFailed`).
  public var failingClubIDs: Set<String>
  /// Pause before each fetch, so progress can be seen. Cancellation during the pause throws
  /// `CancellationError`.
  public var delay: Duration

  public init(
    responses: [String: Response] = [:], logos: any LogoStore, logoData: Data = FakeFixtureSource.defaultLogoData,
    fallbackClubIDs: Set<String> = [], failingClubIDs: Set<String> = [], delay: Duration = .zero
  ) {
    self.responses = Dictionary(responses.map { ($0.key.lowercased(), $0.value) }) { _, last in last }
    self.logos = logos
    self.logoData = logoData
    self.fallbackClubIDs = fallbackClubIDs
    self.failingClubIDs = failingClubIDs
    self.delay = delay
  }

  public func fetchFixtures(for team: Team, settings: ClubSettings) async throws -> FixtureFetch {
    guard let widgetID = team.tuttocampoWidgetID else { throw FixtureFetchError.missingWidgetID }
    if delay > .zero { try await Task.sleep(for: delay) }
    try Task.checkCancellation()
    switch responses[widgetID.lowercased()] {
    case .fetch(let fetch): return fetch
    case .failure(let error): throw error
    case nil: throw FixtureFetchError.httpStatus(404)
    }
  }

  public func downloadLogos(_ requests: [LogoRequest]) async -> [LogoResult] {
    enum Outcome {
      case stored(String)
      case fallback(String)
      case failed
    }
    var outcomes: [String: Outcome] = [:]
    var results: [LogoResult] = []
    for request in requests {
      guard !Task.isCancelled else {
        results.append(LogoResult(request: request, fileName: nil, issue: nil))
        continue
      }
      guard let clubID = request.clubID, let fileName = tuttocampoLogoFileName(clubID: clubID) else {
        results.append(
          LogoResult(request: request, fileName: nil, issue: .logoNotRecognised(opponent: request.opponentName)))
        continue
      }
      let outcome: Outcome
      if let known = outcomes[clubID] {
        outcome = known
      } else {
        let usesFallback = fallbackClubIDs.contains(clubID)
        if failingClubIDs.contains(clubID) || (usesFallback && request.fallbackURL == nil) {
          outcome = .failed
        } else if (try? await logos.importLogo(data: logoData, fileName: fileName, replacing: nil)) != nil {
          outcome = usesFallback ? .fallback(fileName) : .stored(fileName)
        } else {
          outcome = .failed
        }
        outcomes[clubID] = outcome
      }
      switch outcome {
      case .stored(let name):
        results.append(LogoResult(request: request, fileName: name, issue: nil))
      case .fallback(let name):
        results.append(
          LogoResult(request: request, fileName: name, issue: .logoFallback(opponent: request.opponentName)))
      case .failed:
        results.append(LogoResult(request: request, fileName: nil, issue: .logoFailed(opponent: request.opponentName)))
      }
    }
    return results
  }

  /// A fixture crest when the fixtures can be found, otherwise a 1×1 PNG.
  public static var defaultLogoData: Data {
    if let folder = try? Fixtures.logosFolder(),
      let data = try? Data(contentsOf: folder.appendingPathComponent("fixture-lucia.png"))
    {
      return data
    }
    return Data(base64Encoded: onePixelPNG) ?? Data()
  }

  static let onePixelPNG =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

  // MARK: Scenario

  /// The widget id of the scenario entry for team number `index` (1-based, as in `matches.json`).
  public static func scenarioWidgetID(_ index: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", index) }

  /// ClubId of the opponent whose `Teams/200` logo "fails" in the scenario (Atletico Montesello).
  public static let scenarioFallbackClubID = "900209"

  /// Canned answers for the teams of `Resources/Fixtures/matches.json`, dated around
  /// `referenceSaturday` (pass the data set's, after shifting). With that data set:
  ///
  /// | Widget | Team | Answer | Candidate / report |
  /// |---|---|---|---|
  /// | 1 | Prima Squadra | Sun, home, "Oratorio San Gerolamo", as stored | `.unchanged` |
  /// | 2 | Juniores | Sun, away, time 11:00 instead of 10:30 | `.changed` |
  /// | 3 | Allievi U17 | Sat, home, played 3–1 | `.changed` (result) |
  /// | 4 | Allievi U16 | Sun, status "Partita sospesa" | `.needsReview` (unknown status) |
  /// | 5 | Giovanissimi U15 | page structure changed | `.sourceProblem(.structureChanged)` |
  /// | 6 | Giovanissimi U14 | "Risultati non ancora disponibili." | `.notYetAvailable` (information) |
  /// | 7 | Esordienti | network failure | `.fetchFailed(.network)` |
  /// | 8 | Pulcini | Sat, away, time 10:00 (stored without time) | `.changed` |
  /// | 9 | Primi Calci | Sun, time 11:30 | `.locked` (the stored match is locked); logo via fallback |
  /// | 10 | Femminile | Sun, "Partita rinviata", as stored | `.unchanged` |
  /// | 11 | Juniores Femminile | Sun, away, unknown "Atletico Nuovo Borgo", unrecognised logo address | `.needsReview` (opponent not found), away venue missing; logo not recognised |
  /// | 12 | Amatori | Sat 20:30, home, "Virtus Campofelice" | `.new` |
  ///
  /// Veterani has no widget id.
  public static func scenario(
    referenceSaturday: DayDate, logos: any LogoStore, delay: Duration = .milliseconds(250)
  ) -> FakeFixtureSource {
    let saturday = referenceSaturday
    let sunday = referenceSaturday.adding(days: 1)
    func time(_ hour: Int, _ minute: Int) -> ClockTime? { ClockTime(hour: hour, minute: minute) }
    func logo(_ clubID: String) -> URL? { URL(string: "https://b2-content.tuttocampo.it/Teams/40/\(clubID).png?v=1") }
    func scheduled(
      _ date: DayDate, _ clock: ClockTime?, home: Bool, _ name: String, club: String, round: Int? = nil
    ) -> FetchedFixture {
      FetchedFixture(
        date: date, time: clock, isHome: home, opponentName: name, opponentClubID: club, opponentLogoURL: logo(club),
        round: round, status: .scheduled, statusText: "Partita da giocare")
    }
    var played = scheduled(saturday, time(15, 0), home: true, "Castelverde Calcio", club: "900203", round: 10)
    played.status = .played
    played.score = Score(us: 3, them: 1)
    played.statusText = "Partita terminata"
    var suspended = scheduled(sunday, time(10, 0), home: true, "Novaria Bassa", club: "900204")
    suspended.status = nil
    suspended.statusText = "Partita sospesa"
    var postponed = scheduled(sunday, time(18, 0), home: true, "Sant'Ilario Città", club: "900210")
    postponed.status = .postponed
    postponed.statusText = "Partita rinviata"
    var unknown = scheduled(sunday, time(15, 30), home: false, "Atletico Nuovo Borgo", club: "900211")
    unknown.opponentClubID = nil
    unknown.opponentLogoURL = URL(string: "https://b2-content.tuttocampo.it/Web/Images/stemma.png")

    let answers: [Int: Response] = [
      1: .fetch(
        .fixtures([scheduled(sunday, time(14, 30), home: true, "Oratorio San Gerolamo", club: "900201", round: 12)])),
      2: .fetch(
        .fixtures([
          scheduled(
            sunday, time(11, 0), home: false, "Oratorio Sant'Eufrasio di Valfonda Bassa", club: "900202", round: 10)
        ])),
      3: .fetch(.fixtures([played])),
      4: .fetch(.fixtures([suspended])),
      5: .fetch(.sourceProblem(.structureChanged)),
      6: .fetch(.notYetAvailable),
      7: .failure(.network),
      8: .fetch(.fixtures([scheduled(saturday, time(10, 0), home: false, "Prato Fiorito", club: "900208")])),
      9: .fetch(
        .fixtures([scheduled(sunday, time(11, 30), home: true, "Atletico Montesello", club: scenarioFallbackClubID)])),
      10: .fetch(.fixtures([postponed])),
      11: .fetch(.fixtures([unknown])),
      12: .fetch(
        .fixtures([scheduled(saturday, time(20, 30), home: true, "Virtus Campofelice", club: "900212", round: 8)])),
    ]
    return FakeFixtureSource(
      responses: Dictionary(uniqueKeysWithValues: answers.map { (scenarioWidgetID($0.key), $0.value) }), logos: logos,
      fallbackClubIDs: [scenarioFallbackClubID], delay: delay)
  }
}
