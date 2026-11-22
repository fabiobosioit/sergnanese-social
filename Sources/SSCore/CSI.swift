import Foundation

// CSI Live import (T4.8): the user opens a girone page of `live.centrosportivoitaliano.it` in an in-app
// browser window and presses "Importa questa pagina". The app never requests CSI pages itself (the site
// runs a bot check). The flow, driven by the UI:
//
// 1. the browser reads the page's HTML once (`CSIPageReadError` when it cannot);
// 2. `PageFixtureParser.parse(html:pageURL:settings:)` (`AppServices.csiPageParser`) gives a `FixtureFetch`;
//    a page that gave no fixtures becomes `ImportIssue.csiPage(team:outcome:clubShortName:)`;
// 3. staging and commit exactly as in T4.2 (`ImportCandidate.make`, `MatchRepository.upsertFromImport`);
// 4. logos: `CSILogoRequest(opponent:fixture:)` for the opponents that need one, the browser's
//    `PageLogoSource.fetchLogos` reads the bytes inside the page session, `storeCSILogos(_:in:)` stores
//    them, then `OpponentRepository.update` with each stored file name.
//
// Rules and facts: `docs/plan/tasks/wave-4-later.md` (T4.8), `docs/plan/notes/t4.8-csi-spike.md`.

// MARK: - Hosts and page addresses

/// The hosts of CSI Live.
public enum CSILive {
  /// The girone pages, behind the bot check. The only host a team's `csiPageURL` may name.
  public static let pageHost = "live.centrosportivoitaliano.it"
  /// The team logos (`/modulistica/logo/<id>_<timestamp>.jpg`). The only host a logo may be downloaded
  /// from outside the page session, and only if it is shown not to be behind the bot check (T4.8c).
  public static let logoHost = "static.centrosportivoitaliano.it"
}

/// `true` for the address of a CSI Live page a team can store: at most `FieldLimits.csiPageURL`
/// characters, no whitespace, scheme `https`, host exactly `live.centrosportivoitaliano.it` (either case),
/// no user, password or port, and a path other than `/`. The query (`?j=…`) is allowed and kept.
public func isValidCSIPageURL(_ text: String) -> Bool {
  guard !text.isEmpty, text.count <= FieldLimits.csiPageURL,
    !text.unicodeScalars.contains(where: {
      CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
    }),
    let components = URLComponents(string: text),
    components.scheme?.lowercased() == "https",
    components.host?.lowercased() == CSILive.pageHost,
    components.user == nil, components.password == nil, components.port == nil,
    components.path.count > 1
  else { return false }
  return true
}

/// The CSI page address in pasted text: surrounding whitespace removed, `https://` added when the text
/// has no scheme. `nil` when the result is not `isValidCSIPageURL`.
public func csiPageURL(from text: String) -> String? {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
  return isValidCSIPageURL(candidate) ? candidate : nil
}

/// What identifies a CSI page: host and path in lower case, without trailing `/`. The query (`?j=…`,
/// which encodes the page state) and the fragment are ignored. Two teams may not store pages with the
/// same key (`TeamRepository`), and the browser compares the open page with the team's by key.
/// `nil` when `text` is not `isValidCSIPageURL`.
public func csiPageKey(_ text: String) -> String? {
  guard isValidCSIPageURL(text), let components = URLComponents(string: text) else { return nil }
  var path = components.path.lowercased()
  while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
  return CSILive.pageHost + path
}

// MARK: - Logos

/// The 8-digit CSI team id in a logo address, or `nil` when the address does not have the expected
/// shape: scheme `https` or `http`, host `static.centrosportivoitaliano.it`, path
/// `/modulistica/logo/<8 digits>_<anything>.<extension>` (or `<8 digits>.<extension>`); the query is
/// ignored. The part after `_` is an upload timestamp and is not part of the id.
///
/// `https://static.centrosportivoitaliano.it/modulistica/logo/12345678_202609011200.jpg` → `"12345678"`.
public func csiTeamID(fromLogoURL url: URL) -> String? {
  guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
    url.host?.lowercased() == CSILive.logoHost
  else { return nil }
  let parts = url.pathComponents
  guard parts.count == 4, parts[0] == "/", parts[1] == "modulistica", parts[2] == "logo",
    let dot = parts[3].lastIndex(of: ".")
  else { return nil }
  let stem = parts[3][..<dot]
  let fileExtension = parts[3][parts[3].index(after: dot)...]
  let id = String(stem.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)[0])
  guard isCSITeamID(id), !fileExtension.isEmpty,
    fileExtension.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
  else { return nil }
  return id
}

/// `true` for the CSI placeholder shield that the page shows for a team without a logo
/// (`https://cdncsi.csi-net.it/risultati/img_2/csi-shield-b.svg`): a file name starting with
/// `csi-shield` and ending in `.svg`, on any host. It means "no logo": never fetched, never stored.
public func isCSIPlaceholderLogo(_ url: URL) -> Bool {
  let name = url.lastPathComponent.lowercased()
  return name.hasPrefix("csi-shield") && name.hasSuffix(".svg")
}

/// The name a CSI logo is stored under in the logos folder: `"csi-<id>.png"` when `id` is an 8-digit
/// CSI team id (`csiTeamID(fromLogoURL:)`), else `"csi-<slug(name)>.png"` with the slug cut to 60
/// characters (no trailing `-`). `nil` when there is no id and the name has no letter or digit.
/// Every result passes `isValidImportedLogoFileName`.
///
/// `csiLogoFileName(id: "12345678", name: "US Esempio 2016")` → `"csi-12345678.png"`;
/// `csiLogoFileName(id: nil, name: "US Esempio 2016")` → `"csi-us-esempio-2016.png"`.
public func csiLogoFileName(id: String?, name: String) -> String? {
  if let id, isCSITeamID(id) { return "csi-\(id).png" }
  var base = String(slug(name).prefix(csiLogoSlugLimit))
  while base.hasSuffix("-") { base.removeLast() }
  return base.isEmpty ? nil : "csi-\(base).png"
}

/// Longest part after `csi-` in a CSI logo file name.
let csiLogoSlugLimit = 60

/// Exactly 8 ASCII digits.
func isCSITeamID(_ text: String) -> Bool {
  text.count == 8 && text.allSatisfy(\.isASCIIDigit)
}

// MARK: - Reading the page

/// Why the browser could not read the open page's HTML. Becomes `ImportIssue.csiPageReadFailed`.
public enum CSIPageReadError: Error, Sendable, Equatable, Hashable {
  /// The HTML is larger than the browser's cap (2 MB). Nothing is parsed.
  case tooLarge
  /// The page could not be read (still loading, script error, the window closed).
  case failed
}

/// Reads our matches from the HTML of a page the user has open (T4.8: `CSIPageParser` in SSImport for
/// CSI Live girone pages; `FakePageFixtureParser` in SSCoreFakes). A pure function: no I/O, no state, no
/// network; the HTML is parsed, never rendered or run.
public protocol PageFixtureParser: Sendable {
  /// Our matches in `html` (the page's `document.documentElement.outerHTML`, read once), whose address
  /// is `pageURL` (relative links and images are resolved against it).
  ///
  /// A row is ours when one side's name equals `settings.clubShortName` (compared with `searchKey` after
  /// `stripLegalPrefixes`); that side gives `isHome`, the other side is the opponent; other rows are
  /// ignored. A match shown several times is returned once, in page order. A placeholder logo
  /// (`isCSIPlaceholderLogo`) gives `opponentLogoURL == nil`. `opponentClubID` is always `nil` (it is
  /// tuttocampo's).
  ///
  /// Returns `.fixtures` (never empty), `.sourceProblem(.structureChanged)` when the page has no
  /// recognisable match list ("not a CSI girone"), or `.sourceProblem(.noFixturesOfOurs)`. Never
  /// `.notYetAvailable`.
  func parse(html: String, pageURL: URL, settings: ClubSettings) -> FixtureFetch
}

/// The parser `AppServices` uses when none is given: every page is "not a CSI girone". Keeps the
/// containers built before T4.8 valid.
@usableFromInline
struct UnavailablePageFixtureParser: PageFixtureParser {
  @usableFromInline
  init() {}

  @usableFromInline
  func parse(html: String, pageURL: URL, settings: ClubSettings) -> FixtureFetch {
    .sourceProblem(.structureChanged)
  }
}

// MARK: - Logos from the page

/// An opponent logo to take from the CSI page the user has open. Unlike `LogoRequest` it has no ClubId:
/// the bytes come from the page session (`PageLogoSource`) and are stored under `fileName`.
/// Build it with `init?(opponent:fixture:)`.
public struct CSILogoRequest: Sendable, Codable, Equatable, Hashable {
  public var opponentID: EntityID
  /// For the report.
  public var opponentName: String
  /// The logo address the page shows (`FetchedFixture.opponentLogoURL`), `https` or `http`.
  public var logoURL: URL
  /// The name the logo is stored under (`csiLogoFileName(id:name:)`).
  public var fileName: String

  public init(opponentID: EntityID, opponentName: String, logoURL: URL, fileName: String) {
    self.opponentID = opponentID
    self.opponentName = opponentName
    self.logoURL = logoURL
    self.fileName = fileName
  }

  /// The logo of `opponent` as shown in `fixture`, stored as
  /// `csiLogoFileName(id: csiTeamID(fromLogoURL:), name: fixture.opponentName)`. `nil` when the page
  /// shows no logo (no address, the placeholder shield, a scheme other than `https`/`http`) or no file
  /// name can be made: the caller then reports `ImportIssue.csiLogoUnavailable`.
  public init?(opponent: Opponent, fixture: FetchedFixture) {
    guard let url = fixture.opponentLogoURL, let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http", !isCSIPlaceholderLogo(url),
      let fileName = csiLogoFileName(id: csiTeamID(fromLogoURL: url), name: fixture.opponentName)
    else { return nil }
    self.init(opponentID: opponent.id, opponentName: opponent.name, logoURL: url, fileName: fileName)
  }
}

/// The bytes a `PageLogoSource` read for one request: `nil` when it could not read them.
public struct CSILogoData: Sendable, Equatable, Hashable {
  public var request: CSILogoRequest
  public var data: Data?

  public init(request: CSILogoRequest, data: Data?) {
    self.request = request
    self.data = data
  }
}

/// What happened to one `CSILogoRequest`.
public struct CSILogoResult: Sendable, Equatable, Hashable {
  public var request: CSILogoRequest
  /// The file stored in the logos folder (`request.fileName`); `nil` when no logo was stored.
  public var fileName: String?
  /// `.csiLogoUnavailable` when no logo was stored; `nil` otherwise (and for a cancelled request).
  public var issue: ImportIssue?

  public init(request: CSILogoRequest, fileName: String?, issue: ImportIssue?) {
    self.request = request
    self.fileName = fileName
    self.issue = issue
  }
}

/// Reads opponent logos inside the session of the page the user has open (T4.8c: the CSI browser window;
/// `FakePageLogoSource` in SSCoreFakes). It only reads bytes: storing them is `storeCSILogos(_:in:)`.
/// Main-actor isolated because the real one drives a `WKWebView`.
@MainActor
public protocol PageLogoSource: Sendable {
  /// One `CSILogoData` per request, in request order. `data` is `nil` when the logo could not be read:
  /// not readable from the page and its host not allowed for a download, over 5 MB, the page gone, or
  /// the task cancelled. Never throws; never navigates, opens or reloads a page.
  func fetchLogos(_ requests: [CSILogoRequest]) async -> [CSILogoData]
}

/// Stores the logos a `PageLogoSource` read, one `CSILogoResult` per item in order. Each distinct
/// `request.fileName` is stored once, with `logos.importLogo(data:fileName:replacing: nil)` (which
/// replaces a file of that name and converts the image to PNG); later items with the same file name share
/// the first one's outcome. Missing bytes, or bytes the store refuses (not an image, over 5 MB), give
/// `fileName == nil` and `.csiLogoUnavailable`. Removing an opponent's previous file is the caller's
/// job, after it has updated the opponent. When the task is cancelled, the items not yet stored come
/// back with `fileName == nil` and `issue == nil`. Never throws.
public func storeCSILogos(_ items: [CSILogoData], in logos: any LogoStore) async -> [CSILogoResult] {
  var outcomes: [String: String?] = [:]
  var results: [CSILogoResult] = []
  for item in items {
    let request = item.request
    let stored: String?
    if let known = outcomes[request.fileName] {
      stored = known
    } else {
      guard !Task.isCancelled else {
        results.append(CSILogoResult(request: request, fileName: nil, issue: nil))
        continue
      }
      if let data = item.data, !data.isEmpty {
        stored = try? await logos.importLogo(data: data, fileName: request.fileName, replacing: nil)
      } else {
        stored = nil
      }
      outcomes[request.fileName] = stored
    }
    results.append(
      CSILogoResult(
        request: request, fileName: stored,
        issue: stored == nil ? .csiLogoUnavailable(opponent: request.opponentName) : nil))
  }
  return results
}
