import Foundation
import SSCore
import SwiftSoup

// Reads the HTML of a tuttocampo.it "Classifica" widget for the teams of a league (T4.9). The page is parsed with
// SwiftSoup and never rendered or run. Rows: `table.table_ranking tbody tr`.

/// Every team of the league in a Classifica page except ours, in table order, or `.structureChanged` when the
/// page has no standings table, no row, or a row without a name. See `FixtureSource.fetchLeagueTeams`.
///
/// - Parameters:
///   - html: the page.
///   - pageURL: where it came from; the base for relative logo addresses when the page has no `<base href>`.
///   - team: our team whose league this is; stamped on every result.
///   - clubShortName: `ClubSettings.clubShortName`; a row is ours when it is `tr.selected` or its name equals it
///     under `searchKey(stripLegalPrefixes(_:))`.
func parseClassifica(html: String, pageURL: URL, team: Team, clubShortName: String) -> LeagueTeamsFetch {
  do {
    return try ClassificaParser(pageURL: pageURL, teamID: team.id, clubShortName: clubShortName).parse(html)
  } catch {
    // SwiftSoup only throws on markup it cannot make sense of.
    return .structureChanged
  }
}

private struct ClassificaParser {
  let pageURL: URL
  let teamID: EntityID
  let clubKey: String

  init(pageURL: URL, teamID: EntityID, clubShortName: String) {
    self.pageURL = pageURL
    self.teamID = teamID
    self.clubKey = Self.nameKey(clubShortName)
  }

  func parse(_ html: String) throws -> LeagueTeamsFetch {
    let document = try SwiftSoup.parse(html)
    guard let table = try document.select("table.table_ranking").first() else { return .structureChanged }
    let rows = try table.select("tbody tr").array()
    guard !rows.isEmpty else { return .structureChanged }
    let base = try baseURL(document)

    var seen = Set<String>()
    var teams: [SourceTeam] = []
    for row in rows {
      let name = Self.collapse(try row.select("td.team > a").first()?.text() ?? "")
      guard !name.isEmpty else { return .structureChanged }
      let key = Self.nameKey(name)
      if row.hasClass("selected") || (!clubKey.isEmpty && key == clubKey) { continue }
      guard seen.insert(key).inserted else { continue }

      let source = try row.select("td.team_logo > img").first()?.attr("src") ?? ""
      let logoURL = Self.absoluteURL(source, base: base)
      teams.append(
        SourceTeam(
          source: .tuttocampo, teamID: teamID, name: name,
          logoID: logoURL.flatMap { tuttocampoClubID(fromLogoURL: $0) },
          logoURL: logoURL))
    }
    return .teams(teams)
  }

  /// An absolute `http`/`https` address from the `src` attribute (never `srcset`); else `nil`.
  private static func absoluteURL(_ source: String, base: URL) -> URL? {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
      let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
    else { return nil }
    return url
  }

  /// `<base href>` resolved against the page address, else the page address.
  private func baseURL(_ document: Document) throws -> URL {
    let href = try document.select("base[href]").first()?.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
    if let href, !href.isEmpty, let url = URL(string: href, relativeTo: pageURL)?.absoluteURL { return url }
    return pageURL
  }

  private static func collapse(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private static func nameKey(_ name: String) -> String { searchKey(stripLegalPrefixes(name)) }
}
