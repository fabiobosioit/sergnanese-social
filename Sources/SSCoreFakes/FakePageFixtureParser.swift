import Foundation
import SSCore

/// A CSI page parser with canned answers per page, for `--mock`, previews and tests. It ignores the HTML.
///
/// `AppServices.fake()` uses `scenario(referenceSaturday:)`, which covers the CSI cases against the
/// fixture data set (see the table there).
public struct FakePageFixtureParser: PageFixtureParser {
  /// Keyed by `csiPageKey` of the page address. A page with no entry, or an address that is not a CSI
  /// page, answers `.sourceProblem(.structureChanged)` ("not a CSI girone").
  public var responses: [String: FixtureFetch]

  /// `responses` is keyed by page address; each address is turned into its `csiPageKey` (addresses that
  /// are not valid CSI pages are dropped).
  public init(responses: [String: FixtureFetch] = [:]) {
    var keyed: [String: FixtureFetch] = [:]
    for (address, fetch) in responses {
      if let key = csiPageKey(address) { keyed[key] = fetch }
    }
    self.responses = keyed
  }

  public func parse(html: String, pageURL: URL, settings: ClubSettings) -> FixtureFetch {
    guard let key = csiPageKey(pageURL.absoluteString), let fetch = responses[key] else {
      return .sourceProblem(.structureChanged)
    }
    return fetch
  }

  // MARK: Scenario

  /// The CSI page of Pulcini in `Resources/Fixtures/matches.json` (fake: no such girone exists).
  public static let scenarioPageURL =
    "https://live.centrosportivoitaliano.it/26/Calcio-a-7/Lombardia/Esempio/C00001/G000008-girone-a-2016/"

  /// A logo address in the CSI shape for the fake team id `id` (8 digits).
  public static func scenarioLogoURL(_ id: String) -> URL? {
    URL(string: "https://\(CSILive.logoHost)/modulistica/logo/\(id)_202609011200.jpg")
  }

  /// The canned answer for Pulcini's page (`scenarioPageURL`), dated around `referenceSaturday` (pass
  /// the data set's, after shifting). With that data set:
  ///
  /// | Date | Side | Opponent as CSI writes it | Logo | Candidate / report |
  /// |---|---|---|---|---|
  /// | Saturday before, 16:00 | home | "Borgo Lucente", played 4–2 | placeholder (none) | `.new`; `.csiLogoUnavailable` |
  /// | reference Saturday, 10:00 | away | "Prato Fiorito" | id 90000101 | `.changed` (time); the stored venue is kept; opponent already has a logo |
  /// | next Sunday, 15:00 | home | "Valdorso 2016" | id 90000102 | `.needsReview` (opponent not found: link it to F.C. Valdorso), then `.changed` (time) |
  /// | next Saturday, 16:00 | away | "Polisportiva Fontanella" | id 90000103 | `.needsReview` (opponent not found); once created, `.new` with the CSI venue |
  /// | Saturday after, 16:00 | away | "Atletico Montesello" | id 90000104 | `.new` with the CSI venue; logo stored as `csi-90000104.png` |
  ///
  /// Every other page is "not a CSI girone".
  public static func scenario(referenceSaturday: DayDate) -> FakePageFixtureParser {
    let saturday = referenceSaturday
    func time(_ hour: Int, _ minute: Int) -> ClockTime? { ClockTime(hour: hour, minute: minute) }
    func row(
      _ date: DayDate, _ clock: ClockTime?, home: Bool, _ name: String, logo id: String?, round: Int,
      venue: String
    ) -> FetchedFixture {
      FetchedFixture(
        date: date, time: clock, isHome: home, opponentName: name,
        opponentLogoURL: id.flatMap(scenarioLogoURL), round: round, status: .scheduled, statusText: "-",
        venue: venue)
    }
    var played = row(
      saturday.adding(days: -7), time(16, 0), home: true, "Borgo Lucente", logo: nil, round: 6,
      venue: "Campo Comunale Via Roma 1 - 26000 Sergnano CR")
    played.status = .played
    played.score = Score(us: 4, them: 2)
    played.statusText = "4 - 2"
    let fixtures = [
      played,
      row(
        saturday, time(10, 0), home: false, "Prato Fiorito", logo: "90000101", round: 7,
        venue: "Oratorio Prato Fiorito Via Dante 3 - 26000 Prato Fiorito CR"),
      row(
        saturday.adding(days: 8), time(15, 0), home: true, "Valdorso 2016", logo: "90000102", round: 8,
        venue: "Campo Comunale Via Roma 1 - 26000 Sergnano CR"),
      row(
        saturday.adding(days: 7), time(16, 0), home: false, "Polisportiva Fontanella", logo: "90000103", round: 9,
        venue: "Centro Sportivo Fontanella Via Verdi 5 - 26000 Fontanella CR"),
      row(
        saturday.adding(days: 14), time(16, 0), home: false, "Atletico Montesello", logo: "90000104", round: 10,
        venue: "Campo Montesello Via Manzoni 2 - 26000 Montesello CR"),
    ]
    return FakePageFixtureParser(responses: [scenarioPageURL: .fixtures(fixtures)])
  }
}

/// A page logo source with canned bytes, for `--mock`, previews and tests. No page, no network.
@MainActor
public struct FakePageLogoSource: PageLogoSource {
  /// The bytes returned for every logo that "succeeds".
  public var data: Data
  /// Logo addresses that "fail" (`data == nil`).
  public var failingURLs: Set<URL>

  public init(data: Data = FakeFixtureSource.defaultLogoData, failingURLs: Set<URL> = []) {
    self.data = data
    self.failingURLs = failingURLs
  }

  /// `data` for every request whose address is not in `failingURLs`; `nil` for the others and, once the
  /// task is cancelled, for the rest.
  public func fetchLogos(_ requests: [CSILogoRequest]) async -> [CSILogoData] {
    requests.map { request in
      let fails = Task.isCancelled || failingURLs.contains(request.logoURL)
      return CSILogoData(request: request, data: fails ? nil : data)
    }
  }
}
