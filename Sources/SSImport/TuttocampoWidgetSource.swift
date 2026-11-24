import Foundation
import SSCore

/// Reads our matches from a team's tuttocampo.it widget and downloads opponents' logos.
///
/// Requests are made only when `fetchFixtures` or `downloadLogos` is called. The fetched HTML is
/// parsed (SwiftSoup), never rendered or run. Nothing here writes outside the logos folder, which is
/// reached only through `LogoStore`.
public struct TuttocampoWidgetSource: FixtureSource {
  private let client: TuttocampoHTTPClient
  private let logos: any LogoStore

  /// - Parameters:
  ///   - logos: where downloaded logos are stored.
  ///   - configuration: the session configuration to start from (cookies and cache are switched off
  ///     and timeouts set whatever it says). Tests pass one whose `protocolClasses` holds a stub.
  ///   - minimumInterval: the shortest time between two page requests.
  public init(
    logos: any LogoStore, configuration: URLSessionConfiguration = .ephemeral, minimumInterval: Duration = .seconds(1)
  ) {
    self.init(
      logos: logos, client: TuttocampoHTTPClient(configuration: configuration, minimumInterval: minimumInterval))
  }

  init(logos: any LogoStore, client: TuttocampoHTTPClient) {
    self.logos = logos
    self.client = client
  }

  // MARK: FixtureSource

  public func fetchFixtures(for team: Team, settings: ClubSettings) async throws -> FixtureFetch {
    guard let widgetID = team.tuttocampoWidgetID, isValidTuttocampoWidgetID(widgetID),
      let url = URL(string: "https://www.tuttocampo.it/WidgetV2/Risultati/\(widgetID)")
    else { throw FixtureFetchError.missingWidgetID }
    let data = try await client.page(url)
    return parseResults(
      html: String(decoding: data, as: UTF8.self), pageURL: url, clubShortName: settings.clubShortName,
      season: settings.season)
  }

  public func fetchSeason(
    for team: Team, settings: ClubSettings, scope: SeasonScope, onProgress: @Sendable (SeasonProgress) async -> Void
  ) async throws -> SeasonFetch {
    guard let widgetID = team.tuttocampoWidgetID, isValidTuttocampoWidgetID(widgetID),
      let defaultURL = URL(string: "https://www.tuttocampo.it/WidgetV2/Risultati/\(widgetID)")
    else { throw FixtureFetchError.missingWidgetID }
    let client = self.client
    return try await readSeason(
      scope: scope,
      readPage: { matchday in
        let url: URL
        if let matchday {
          guard let built = tuttocampoMatchdayURL(widgetID: widgetID, matchday: matchday, season: settings.season)
          else { throw FixtureFetchError.network }
          url = built
        } else {
          url = defaultURL
        }
        // Throws FixtureFetchError or CancellationError only (the client maps URLError.cancelled).
        let data = try await client.page(url)
        return parseResultsPage(
          html: String(decoding: data, as: UTF8.self), pageURL: url, clubShortName: settings.clubShortName,
          season: settings.season)
      }, onProgress: onProgress)
  }

  public func fetchLeagueTeams(for team: Team, settings: ClubSettings) async throws -> LeagueTeamsFetch {
    guard let widgetID = team.tuttocampoWidgetID, isValidTuttocampoWidgetID(widgetID),
      let url = URL(string: "https://www.tuttocampo.it/WidgetV2/Classifica/\(widgetID)")
    else { throw FixtureFetchError.missingWidgetID }
    let data = try await client.page(url)
    return parseClassifica(
      html: String(decoding: data, as: UTF8.self), pageURL: url, team: team, clubShortName: settings.clubShortName)
  }

  public func downloadLogos(_ requests: [LogoRequest]) async -> [LogoResult] {
    // One download per distinct, valid ClubId; the first request with a ClubId supplies the fallback.
    var order: [String] = []
    var fallbacks: [String: URL] = [:]
    for request in requests {
      guard let clubID = request.clubID, tuttocampoLogoURL(clubID: clubID) != nil else { continue }
      if !order.contains(clubID) { order.append(clubID) }
      if fallbacks[clubID] == nil, let url = request.fallbackURL, TuttocampoHTTPClient.isAllowed(url) {
        fallbacks[clubID] = url
      }
    }

    let fallbackURLs = fallbacks
    var outcomes: [String: Outcome] = [:]
    await withTaskGroup(of: (String, Outcome).self) { group in
      var pending = order[...]
      func startNext() {
        guard let clubID = pending.popFirst() else { return }
        group.addTask { (clubID, await download(clubID: clubID, fallback: fallbackURLs[clubID])) }
      }
      for _ in 0..<Self.maxConcurrentDownloads { startNext() }
      while let (clubID, outcome) = await group.next() {
        outcomes[clubID] = outcome
        if Task.isCancelled {
          // Requests not started yet stay without an outcome; running ones end themselves.
          pending = []
        } else {
          startNext()
        }
      }
    }

    return requests.map { request in
      guard let clubID = request.clubID, tuttocampoLogoURL(clubID: clubID) != nil else {
        return LogoResult(request: request, fileName: nil, issue: .logoNotRecognised(opponent: request.opponentName))
      }
      switch outcomes[clubID] {
      case .stored(let fileName, let usedFallback):
        return LogoResult(
          request: request, fileName: fileName,
          issue: usedFallback ? .logoFallback(opponent: request.opponentName) : nil)
      case .failed:
        return LogoResult(request: request, fileName: nil, issue: .logoFailed(opponent: request.opponentName))
      case .cancelled, nil:
        return LogoResult(request: request, fileName: nil, issue: nil)
      }
    }
  }

  // MARK: Logos

  private static let maxConcurrentDownloads = 3
  private static let imageTypes: Set<String> = ["image/png", "image/jpeg", "image/webp"]

  private enum Outcome: Sendable {
    case stored(fileName: String, usedFallback: Bool)
    case failed
    case cancelled
  }

  private func download(clubID: String, fallback: URL?) async -> Outcome {
    guard let primary = tuttocampoLogoURL(clubID: clubID), let fileName = tuttocampoLogoFileName(clubID: clubID) else {
      return .failed
    }
    switch await fetchAndStore(primary, as: fileName) {
    case .success: return .stored(fileName: fileName, usedFallback: false)
    case .cancelled: return .cancelled
    case .failure: break
    }
    guard let fallback else { return .failed }
    switch await fetchAndStore(fallback, as: fileName) {
    case .success: return .stored(fileName: fileName, usedFallback: true)
    case .cancelled: return .cancelled
    case .failure: return .failed
    }
  }

  private enum Attempt { case success, failure, cancelled }

  private func fetchAndStore(_ url: URL, as fileName: String) async -> Attempt {
    if Task.isCancelled { return .cancelled }
    do {
      let download = try await client.logo(url)
      guard Self.imageTypes.contains(download.contentType) else { return .failure }
      _ = try await logos.importLogo(data: download.data, fileName: fileName, replacing: nil)
      return .success
    } catch is CancellationError {
      return .cancelled
    } catch {
      return Task.isCancelled ? .cancelled : .failure
    }
  }
}
