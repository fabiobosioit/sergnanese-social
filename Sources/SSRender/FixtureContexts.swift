import Foundation
import SSCore

/// Sample contexts from `Resources/Fixtures/` for previews (`RenderService.preview` without matches,
/// `ss-tool demo-render`). Fixture contexts were built for the documented example limits, so they
/// are cut again to the template's own limits before use.
public enum FixtureContexts {
  /// The standard fixture of a template: recap → `list-results.context.json`, other lists →
  /// `list.context.json`, singles → `single.context.json`.
  public static func standardFile(for manifest: TemplateManifest, in fixtures: URL) -> URL {
    let name =
      switch manifest.kind {
      case .single: "single"
      case .list: manifest.isResultsRecap ? "list-results" : "list"
      }
    return fixtures.appendingPathComponent("\(name).context.json")
  }

  /// Decodes a fixture file for `manifest`, cut to its limits. A list fixture is sliced to the
  /// first page of `pageSize` rows. `club`, when given, replaces the fixture's club (the user's
  /// accent colour and names).
  public static func load(_ file: URL, for manifest: TemplateManifest, club: ClubContext? = nil) throws
    -> TemplateContext
  {
    let data: Data
    do {
      data = try Data(contentsOf: file)
    } catch {
      throw AppError.io(message: RenderStrings.fixtureMissing)
    }
    let decoder = JSONDecoder()
    do {
      switch manifest.kind {
      case .single:
        var context = try decoder.decode(SingleContext.self, from: data)
        if let club { context.club = club }
        context.match = recut(context.match, limits: manifest.limits)
        return .single(context)
      case .list:
        let full = try decoder.decode(ListContext.self, from: data)
        let pageSize = max(manifest.pageSize ?? full.rows.count, 1)
        let total = max(Int((Double(full.rows.count) / Double(pageSize)).rounded(.up)), 1)
        let rows = full.rows.prefix(pageSize).map { recut($0, limits: manifest.limits) }
        let context = ListContext(
          club: club ?? full.club, title: full.title, dateLabel: full.dateLabel, rows: Array(rows),
          page: PageInfo(index: 1, total: total))
        return .list(context)
      }
    } catch {
      throw AppError.io(message: RenderStrings.fixtureInvalid(file.lastPathComponent, String(describing: error)))
    }
  }

  /// `match` with names, venue and category cut to `limits`.
  static func recut(_ match: MatchContext, limits: TemplateLimits) -> MatchContext {
    func cut(_ text: String, _ limit: Int?) -> String {
      guard let limit else { return text }
      return truncateAtWord(text, max: limit).text
    }
    func side(_ side: SideContext) -> SideContext {
      var side = side
      side.displayName = cut(side.displayName, limits.teamName)
      return side
    }
    var match = match
    match.category = cut(match.category, limits.category)
    match.venue = cut(match.venue, limits.venue)
    match.home = side(match.home)
    match.away = side(match.away)
    match.us = side(match.us)
    match.opponent = side(match.opponent)
    return match
  }
}
