import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSRender

@Suite struct ContextBuilderTests {
  let single = TemplateManifest(
    id: "post", name: "Post", version: "1.0.0", format: .post, width: 1080, height: 1350, kind: .single,
    purpose: .prematch, requires: [.time, .venue, .score], limits: TemplateLimits(teamName: 16, venue: 10, category: 22)
  )
  let list = TemplateManifest(
    id: "programme", name: "Programma", version: "1.0.0", format: .story, width: 1080, height: 1920, kind: .list,
    purpose: .programme, pageSize: 10, limits: TemplateLimits(teamName: 22, venue: 14, category: 16))

  @Test func singleContextFollowsHomeAndAway() throws {
    let builder = ContextBuilder(settings: .defaults, manifest: single)
    let away = TestData.detail(
      TestData.match("a", isHome: false, score: Score(us: 0, them: 2), halfTime: Score(us: 0, them: 0)))
    let (context, _) = builder.single(away)
    #expect(context.club.logo == TemplateURLs.clubLogo)
    #expect(context.club.accent == "#CF3326")
    #expect(context.match.isAway)
    #expect(context.match.home.name == TestData.withLogo.name)
    #expect(context.match.away.isUs)
    #expect(context.match.us.displayName == "Sergnanese")
    #expect(context.match.us.score == 0)
    #expect(context.match.opponent.logo == "_logos/fixture-gerolamo.png")
    #expect(context.match.opponent.displayName == "San Gerolamo")
    #expect(context.match.opponent.initials == "OSG")
    #expect(context.match.hasScore && context.match.hasHalfTime)
    #expect(context.match.dateLong == "Domenica 22 novembre")
    #expect(context.match.time == "14:30")
    #expect(context.match.category == "Prima Squadra")
  }

  @Test func appliesLimitsAndCollectsWarnings() throws {
    let builder = ContextBuilder(settings: .defaults, manifest: single)
    let match = TestData.match("b", opponent: TestData.longName, time: nil, venue: "Centro Sportivo Comunale")
    let (context, warnings) = builder.single(TestData.detail(match, opponent: TestData.longName))
    #expect(context.match.opponent.displayName.count <= 16)
    #expect(context.match.opponent.displayName.hasSuffix("…"))
    #expect(context.match.venue.count <= 10)
    #expect(context.match.time == nil)
    let kinds = warnings.map(\.kind)
    #expect(kinds.contains(.missingTime))
    #expect(kinds.contains(.missingLogo))
    #expect(kinds.contains(.nameTruncated))
    #expect(kinds.contains(.textTruncated))
    #expect(warnings.contains { $0.kind == .missingRequiredField && $0.templateID == "post" })
  }

  @Test func missingLogoFileFallsBackToInitials() throws {
    let logos = try makeTemporaryFolder()
    let builder = ContextBuilder(settings: .defaults, manifest: single, logosFolder: logos)
    let (context, warnings) = builder.single(
      TestData.detail(TestData.match("c", opponent: TestData.missingFile), opponent: TestData.missingFile))
    #expect(context.match.opponent.logo == nil)
    #expect(context.match.opponent.initials == "CN")
    #expect(warnings.contains { $0.kind == .missingLogo && $0.opponentID == TestData.missingFile.id })
  }

  @Test func notScheduledMatchesAreFlagged() {
    let builder = ContextBuilder(settings: .defaults, manifest: single)
    let (context, warnings) = builder.single(TestData.detail(TestData.match("d", status: .postponed)))
    #expect(context.match.isPostponed)
    #expect(warnings.contains { $0.kind == .matchNotScheduled })
  }

  @Test func paginates23RowsIntoThreePages() {
    let builder = ContextBuilder(settings: .defaults, manifest: list)
    let details = TestData.manyMatches(23).reversed().map { TestData.detail($0, team: TestData.juniors) }
    let pages = builder.pages(Array(details))
    #expect(pages.count == 3)
    #expect(pages.map(\.context.pageLabel) == ["1/3", "2/3", "3/3"])
    #expect(pages.map(\.context.rows.count) == [10, 10, 3])
    #expect(pages.allSatisfy { $0.context.hasPages })
    #expect(pages[0].context.rows.first?.time == "08:00")  // sorted, not in input order
    #expect(pages[0].context.rows.first?.category == "Juniores")  // list rows use the short label
    #expect(pages[0].context.title == "Oggi in campo")
    #expect(pages[0].context.dateLabel == "Domenica 22 novembre")
    #expect(pages.flatMap(\.matches).map(\.id) == TestData.manyMatches(23).map(\.id))
  }

  // MARK: Results recap (T4.5a)

  var recap: TemplateManifest {
    var manifest = list
    manifest.id = "results"
    manifest.purpose = .fulltime
    manifest.requires = [.score]
    return manifest
  }

  @Test func recapTitlesAndLabels() throws {
    let builder = ContextBuilder(settings: .defaults, manifest: recap)
    func page(_ matches: [Match]) -> ListContext { builder.pages(matches.map { TestData.detail($0) })[0].context }
    let weekend = page([TestData.match("s", date: TestData.saturday), TestData.match("u")])
    #expect(weekend.title == "Risultati del weekend")
    #expect(weekend.dateLabel == "Dal 21 al 22 novembre")
    let oneDay = page([TestData.match("u")])
    #expect(oneDay.title == "Risultati")
    #expect(oneDay.dateLabel == "Domenica 22 novembre")
    let twoWeekends = page([
      TestData.match("a", date: TestData.saturday), TestData.match("b", date: TestData.sunday.adding(days: 7)),
    ])
    #expect(twoWeekends.title == "Risultati")
    #expect(twoWeekends.dateLabel == "Dal 21 al 29 novembre")
    // Sunday + next Saturday is not one weekend.
    let split = page([TestData.match("a"), TestData.match("b", date: TestData.sunday.adding(days: 6))])
    #expect(split.title == "Risultati")
    // The programme keeps its titles.
    let programme = ContextBuilder(settings: .defaults, manifest: list).pages([
      TestData.detail(TestData.match("s", date: TestData.saturday)), TestData.detail(TestData.match("u")),
    ])[0].context
    #expect(programme.title == "Weekend in campo")
  }

  @Test func recapWarnings() {
    let builder = ContextBuilder(settings: .defaults, manifest: recap)
    let rows = [
      TestData.match("p", status: .postponed), TestData.match("c", status: .cancelled),
      TestData.match("n"), TestData.match("w", score: Score(us: 2, them: 1)),
    ]
    let page = builder.pages(rows.map { TestData.detail($0) })[0]
    #expect(
      !page.warnings.contains {
        $0.matchID == "p" && ($0.kind == .matchNotScheduled || $0.kind == .missingRequiredField)
      })
    #expect(
      !page.warnings.contains {
        $0.matchID == "c" && ($0.kind == .matchNotScheduled || $0.kind == .missingRequiredField)
      })
    #expect(page.warnings.filter { $0.matchID == "n" && $0.kind == .missingRequiredField }.count == 1)
    #expect(!page.warnings.contains { $0.matchID == "w" && $0.kind == .missingRequiredField })
    // Outside a recap the postponed row is still warned about.
    let programme = ContextBuilder(settings: .defaults, manifest: list).pages([TestData.detail(rows[0])])[0]
    #expect(programme.warnings.contains { $0.kind == .matchNotScheduled })
  }

  @Test func recapRowsCarryTheOutcome() {
    let builder = ContextBuilder(settings: .defaults, manifest: recap)
    let rows = [
      TestData.match("a", time: "10:00", score: Score(us: 2, them: 1)),
      TestData.match("b", time: "11:00", score: Score(us: 0, them: 0)),
      TestData.match("c", time: "12:00", isHome: false, score: Score(us: 0, them: 3)),
      TestData.match("d", time: "13:00"),
    ]
    let context = builder.pages(rows.map { TestData.detail($0) })[0].context
    #expect(context.rows.map(\.outcome) == [.win, .draw, .loss, nil])
  }

  @Test func onePageHasNoPagesFlagAndRangeLabels() {
    let builder = ContextBuilder(settings: .defaults, manifest: list)
    let pages = builder.pages([
      TestData.detail(TestData.match("s", date: TestData.saturday)), TestData.detail(TestData.match("u")),
    ])
    #expect(pages.count == 1)
    #expect(!pages[0].context.hasPages)
    #expect(pages[0].context.title == "Weekend in campo")
    #expect(pages[0].context.dateLabel == "Dal 21 al 22 novembre")
    #expect(builder.pages([]).isEmpty)
    let oct31 = try! DayDate("2026-10-31")
    let jan = try! DayDate("2027-01-02")
    #expect(ContextBuilder.rangeLabel(from: oct31, to: oct31.adding(days: 1)) == "Dal 31 ottobre al 1 novembre")
    #expect(
      ContextBuilder.rangeLabel(from: try! DayDate("2026-12-31"), to: jan) == "Dal 31 dicembre 2026 al 2 gennaio 2027")
  }
}

@Suite struct TemplateHTMLTests {
  func installed(_ html: String, id: String = "t", version: String = "1.0.0") throws -> InstalledTemplate {
    let folder = try makeTemporaryFolder()
    try FixtureTemplates.write(folder: folder, files: ["template.html": html])
    let manifest = TemplateManifest(
      id: id, name: id, version: version, format: .post, width: 100, height: 100, kind: .single, purpose: .other)
    return InstalledTemplate(manifest: manifest, folder: folder, isBuiltin: false)
  }

  @Test func rendersSectionsZerosAndEscapes() throws {
    let context = try Fixtures.singleContext("single-goalless")
    let template = try installed(
      "{{#match.hasScore}}[{{match.home.score}}-{{match.away.score}}]{{/match.hasScore}}"
        + "{{^match.time}}no-time{{/match.time}}{{#match.isHome}}H{{/match.isHome}}{{club.name}}")
    let html = try TemplateHTML().render(template, context: .single(context))
    #expect(html.hasPrefix("[0-0]"))
    #expect(html.hasSuffix("ASD Sergnanese"))

    var tricky = context
    tricky.club.name = "<b>&</b>"
    let escaped = try TemplateHTML().render(try installed("{{club.name}}"), context: .single(tricky))
    #expect(!escaped.contains("<b>"))
  }

  @Test func absentOptionalsUseInvertedSections() throws {
    let context = try Fixtures.singleContext("single-no-logo")
    let template = try installed(
      "{{#match.opponent.logo}}LOGO{{/match.opponent.logo}}{{^match.opponent.logo}}{{match.opponent.initials}}{{/match.opponent.logo}}"
    )
    let html = try TemplateHTML().render(template, context: .single(context))
    #expect(html == context.match.opponent.initials)
  }

  @Test func cachesCompiledTemplatesAndNoticesChanges() throws {
    let renderer = TemplateHTML()
    let template = try installed("A{{club.name}}")
    let context = TemplateContext.single(try Fixtures.singleContext())
    #expect(try renderer.render(template, context: context) == "AASD Sergnanese")
    #expect(try renderer.render(template, context: context) == "AASD Sergnanese")
    #expect(renderer.cachedCount == 1)
    try Data("B{{club.name}}".utf8).write(to: template.folder.appendingPathComponent("template.html"))
    #expect(try renderer.render(template, context: context) == "BASD Sergnanese")
    #expect(renderer.cachedCount == 1)
  }

  @Test func reportsInvalidMustache() throws {
    let template = try installed("{{#open}} never closed")
    #expect(throws: AppError.self) {
      _ = try TemplateHTML().render(template, context: .single(try Fixtures.singleContext()))
    }
  }

  @Test func fixtureContextsAreCutToTemplateLimits() throws {
    let fixtures = try Fixtures.folder()
    let manifest = TemplateManifest(
      id: "t", name: "t", version: "1.0.0", format: .post, width: 100, height: 100, kind: .single, purpose: .other,
      limits: TemplateLimits(teamName: 6))
    guard
      case .single(let context) = try FixtureContexts.load(
        fixtures.appendingPathComponent("single.context.json"), for: manifest)
    else {
      Issue.record("expected single")
      return
    }
    #expect(context.match.opponent.displayName.count <= 6)
    let listManifest = TemplateManifest(
      id: "l", name: "l", version: "1.0.0", format: .story, width: 100, height: 100, kind: .list, purpose: .programme,
      pageSize: 10)
    guard
      case .list(let list) = try FixtureContexts.load(
        fixtures.appendingPathComponent("list-23.context.json"), for: listManifest)
    else {
      Issue.record("expected list")
      return
    }
    #expect(list.rows.count == 10)
    #expect(list.pageLabel == "1/3")
  }
}
