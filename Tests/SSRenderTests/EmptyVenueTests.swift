import Foundation
import SSCore
import SSCoreFakes
import SSTemplates
import Testing

@testable import SSRender

/// QA row V1: a match without a venue reaches the templates as `""`. swift-mustache treats every
/// `String` as true, so `TemplateHTML` must leave blank strings out for the templates' "no venue"
/// branches to run. Checked on the four built-in templates, home and away.
@Suite struct EmptyVenueTests {
  /// The bundled templates, installed in a temporary data folder.
  func builtin(_ id: String) throws -> InstalledTemplate {
    let root = try makeTemporaryFolder("EmptyVenueTests")
    let paths = AppPaths(
      dataFolder: root.appendingPathComponent("data", isDirectory: true),
      resources: try #require(AppPaths.resolveResources()),
      defaultOutputFolder: root.appendingPathComponent("output", isDirectory: true))
    try paths.createFolders()
    let store = FileTemplateStore(paths: paths)
    try store.installBuiltins()
    return try store.get(id: id)
  }

  func single(venue: String, isHome: Bool, time: String? = "14:30") throws -> TemplateContext {
    var context = try Fixtures.singleContext()
    context.match.venue = venue
    context.match.isHome = isHome
    context.match.isAway = !isHome
    context.match.time = time
    return .single(context)
  }

  @Test func blankStringsAreAbsentAndOthersKept() throws {
    var context = try Fixtures.singleContext()
    context.match.venue = "  \n"
    context.club.handle = ""
    let value = try TemplateHTML.mustacheValue(of: .single(context))
    let match = try #require(value["match"] as? [String: Any])
    let club = try #require(value["club"] as? [String: Any])
    #expect(match["venue"] == nil)
    #expect(club["handle"] == nil)
    #expect(match["category"] as? String == context.match.category)
    #expect(match["isHome"] as? Bool == true)

    let template = try installedInline("{{#match.venue}}V{{/match.venue}}{{^match.venue}}none{{/match.venue}}")
    #expect(try TemplateHTML().render(template, context: .single(context)) == "none")
  }

  @Test(arguments: [true, false])
  func postPrematchShowsADash(isHome: Bool) throws {
    let template = try builtin("post-prematch")
    let empty = try TemplateHTML().render(template, context: try single(venue: "", isHome: isHome))
    #expect(empty.contains("overflow-wrap: anywhere\">—</div>"))

    let filled = try TemplateHTML().render(template, context: try single(venue: "Campo Comunale", isHome: isHome))
    #expect(filled.contains("overflow-wrap: anywhere\">Campo Comunale</div>"))
    #expect(!filled.contains("overflow-wrap: anywhere\">—</div>"))
  }

  @Test(arguments: [true, false])
  func storyFulltimeFooterHasNoLeadingDot(isHome: Bool) throws {
    let template = try builtin("story-fulltime")
    let context = try single(venue: "", isHome: isHome)
    guard case .single(let single) = context else { return }
    let html = try TemplateHTML().render(template, context: context)
    #expect(html.contains("<span style=\"flex-shrink: 0\">\(single.match.dateShort)</span>"))
    #expect(!html.contains(">·</span>"))
  }

  @Test(arguments: [true, false])
  func storyHalftimeFooterHasNoLeadingDot(isHome: Bool) throws {
    let template = try builtin("story-halftime")
    let html = try TemplateHTML().render(template, context: try single(venue: "", isHome: isHome))
    #expect(html.contains("<span style=\"flex-shrink: 0\">14:30</span>"))
    #expect(!html.contains(">·</span>"))

    let neither = try TemplateHTML().render(template, context: try single(venue: "", isHome: isHome, time: nil))
    #expect(!neither.contains(">14:30</span>"))
    #expect(!neither.contains(">·</span>"))
  }

  @Test func storyProgrammeRowsPrintNoVenue() throws {
    let template = try builtin("story-programme")
    var context = try Fixtures.listContext()
    context.rows = context.rows.prefix(4).enumerated().map { index, row in
      var row = row
      row.venue = ""
      row.isHome = index.isMultiple(of: 2)
      row.isAway = !row.isHome
      return row
    }
    let html = try TemplateHTML().render(template, context: .list(context))
    // The venue cell starts with the venue name; with no venue it starts with a dash, then the (C)/(T) badge.
    let cells = html.components(separatedBy: "color: #CF3326\"><div>").dropFirst()
    #expect(cells.count == 4)
    for cell in cells { #expect(cell.hasPrefix("— <span")) }

    // A row-level "no venue" branch works with blank strings absent.
    let rows = try installedInline("{{#rows}}{{#venue}}V{{/venue}}{{^venue}}-{{/venue}}{{/rows}}")
    #expect(try TemplateHTML().render(rows, context: .list(context)) == "----")
  }

  func installedInline(_ html: String) throws -> InstalledTemplate {
    let folder = try makeTemporaryFolder()
    try FixtureTemplates.write(folder: folder, files: ["template.html": html])
    let manifest = TemplateManifest(
      id: "inline", name: "inline", version: "1.0.0", format: .post, width: 100, height: 100, kind: .single,
      purpose: .other)
    return InstalledTemplate(manifest: manifest, folder: folder, isBuiltin: false)
  }
}
