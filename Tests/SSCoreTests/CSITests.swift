import Foundation
import SSCoreFakes
import Testing

@testable import SSCore

@Suite struct CSITests {
  let page = "https://live.centrosportivoitaliano.it/26/Calcio-a-11/Lombardia/Esempio/C00001/G000001-girone-a-2016/"

  // MARK: Page addresses

  @Test func pageURLShape() {
    #expect(isValidCSIPageURL(page))
    #expect(isValidCSIPageURL(page + "?j=NEU9RUZGJjRGPVBOWSY0Rz1H"))
    #expect(isValidCSIPageURL("HTTPS://LIVE.centrosportivoitaliano.it/26/x/"))
    for bad in [
      "", "http://live.centrosportivoitaliano.it/26/x/",  // not https
      "https://live.centrosportivoitaliano.it/", "https://live.centrosportivoitaliano.it",  // no page
      "https://www.centrosportivoitaliano.it/26/x/", "https://static.centrosportivoitaliano.it/26/x/",
      "https://live.centrosportivoitaliano.it.example.com/26/x/",
      "https://live.centrosportivoitaliano.it@example.com/26/x/",
      "https://user:pw@live.centrosportivoitaliano.it/26/x/", "https://live.centrosportivoitaliano.it:8443/26/x/",
      "https://live.centrosportivoitaliano.it/26/a b/", " " + page, "live.centrosportivoitaliano.it/26/x/",
      "javascript:alert(1)", "file:///26/x/",
      "https://live.centrosportivoitaliano.it/" + String(repeating: "a", count: FieldLimits.csiPageURL),
    ] {
      #expect(!isValidCSIPageURL(bad), "\(bad)")
    }
  }

  @Test func pageURLFromPastedText() {
    #expect(csiPageURL(from: "  \(page)\n") == page)
    #expect(
      csiPageURL(from: "live.centrosportivoitaliano.it/26/x/?j=abc")
        == "https://live.centrosportivoitaliano.it/26/x/?j=abc")
    #expect(csiPageURL(from: "https://example.com/26/x/") == nil)
    #expect(csiPageURL(from: "ciao") == nil)
    #expect(csiPageURL(from: "") == nil)
  }

  @Test func pageKeyIgnoresQueryCaseAndTrailingSlash() {
    let key = csiPageKey(page)
    #expect(key == "live.centrosportivoitaliano.it/26/calcio-a-11/lombardia/esempio/c00001/g000001-girone-a-2016")
    #expect(csiPageKey(page + "?j=abc#classifica") == key)
    #expect(csiPageKey(String(page.dropLast())) == key)
    #expect(csiPageKey(page.uppercased().replacingOccurrences(of: "HTTPS", with: "https")) == key)
    #expect(csiPageKey(page.replacingOccurrences(of: "G000001", with: "G000002")) != key)
    #expect(csiPageKey("https://example.com/26/x/") == nil)
  }

  @Test func teamDraftCSIPage() {
    var draft = TeamDraft(name: "Pulcini", shortLabel: "Pulcini")
    draft.csiPageURL = "  "
    #expect(draft.normalized().csiPageURL == nil)
    draft.csiPageURL = " live.centrosportivoitaliano.it/26/x/ "
    #expect(draft.normalized().csiPageURL == "https://live.centrosportivoitaliano.it/26/x/")
    #expect(draft.normalized().validate().isEmpty)
    draft.csiPageURL = "https://www.tuttocampo.it/26/x/"
    var problems = draft.normalized().validate()
    #expect(problems.map(\.field) == [.csiPageURL])
    #expect(problems.message(for: .csiPageURL) == CoreStrings.invalidCSIPageURL)
    #expect(throws: AppError.self) { try draft.validated() }
    draft.csiPageURL = page + String(repeating: "a", count: FieldLimits.csiPageURL)
    problems = draft.normalized().validate()
    #expect(problems.message(for: .csiPageURL) == CoreStrings.tooLong(FieldLimits.csiPageURL))
  }

  @Test func teamCarriesTheCSIPage() throws {
    let team = Team(
      id: "t", name: "Pulcini", shortLabel: "Pul", sortOrder: 1, isFirstTeam: false, isActive: true, csiPageURL: page)
    #expect(TeamDraft(team).csiPageURL == page)
    #expect(try JSONDecoder().decode(Team.self, from: JSONEncoder().encode(team)) == team)
    // JSON written before T4.8 has no key and decodes as nil.
    let old = Data(
      #"{"id":"t","name":"Pulcini","shortLabel":"Pul","sortOrder":1,"isFirstTeam":false,"isActive":true}"#.utf8)
    #expect(try JSONDecoder().decode(Team.self, from: old).csiPageURL == nil)
  }

  @Test func csiPageInUseError() {
    let error = AppError.csiPageURLInUse(by: "Pulcini")
    #expect(error == .validation(field: .csiPageURL, message: CoreStrings.csiPageURLInUse("Pulcini")))
    #expect(error.errorDescription?.contains("Pulcini") == true)
  }

  // MARK: Logos

  @Test func teamIDFromLogoURL() throws {
    func id(_ text: String) throws -> String? { csiTeamID(fromLogoURL: try #require(URL(string: text))) }
    #expect(try id("https://static.centrosportivoitaliano.it/modulistica/logo/12345678_202609011200.jpg") == "12345678")
    #expect(try id("https://static.centrosportivoitaliano.it/modulistica/logo/12345678.png?v=2") == "12345678")
    #expect(try id("http://STATIC.centrosportivoitaliano.it/modulistica/logo/12345678_1.jpeg") == "12345678")
    for bad in [
      "https://cdncsi.csi-net.it/risultati/img_2/csi-shield-b.svg",  // placeholder
      "https://live.centrosportivoitaliano.it/modulistica/logo/12345678_1.jpg",  // page host
      "https://static.centrosportivoitaliano.it.example.com/modulistica/logo/12345678_1.jpg",
      "https://static.centrosportivoitaliano.it/modulistica/12345678_1.jpg",  // path
      "https://static.centrosportivoitaliano.it/modulistica/logo/x/12345678_1.jpg",
      "https://static.centrosportivoitaliano.it/modulistica/logo/1234567_1.jpg",  // 7 digits
      "https://static.centrosportivoitaliano.it/modulistica/logo/123456789_1.jpg",  // 9 digits
      "https://static.centrosportivoitaliano.it/modulistica/logo/1234567a_1.jpg",
      "https://static.centrosportivoitaliano.it/modulistica/logo/12345678_1",  // no extension
      "https://static.centrosportivoitaliano.it/modulistica/logo/12345678_1.",
      "ftp://static.centrosportivoitaliano.it/modulistica/logo/12345678_1.jpg",
    ] {
      #expect(try id(bad) == nil, "\(bad)")
    }
  }

  @Test func placeholderShield() throws {
    #expect(
      isCSIPlaceholderLogo(try #require(URL(string: "https://cdncsi.csi-net.it/risultati/img_2/csi-shield-b.svg"))))
    #expect(isCSIPlaceholderLogo(try #require(URL(string: "https://example.com/img/CSI-Shield-a.svg?x=1"))))
    #expect(
      !isCSIPlaceholderLogo(
        try #require(URL(string: "https://static.centrosportivoitaliano.it/modulistica/logo/12345678_1.jpg"))))
  }

  @Test func logoFileNames() {
    #expect(csiLogoFileName(id: "12345678", name: "US Esempio 2016") == "csi-12345678.png")
    #expect(csiLogoFileName(id: nil, name: "US Esempio 2016") == "csi-us-esempio-2016.png")
    #expect(csiLogoFileName(id: "1234", name: "Sant'Ilario Città") == "csi-sant-ilario-citta.png")
    #expect(csiLogoFileName(id: "../12345678", name: "Ok") == "csi-ok.png")
    #expect(csiLogoFileName(id: nil, name: "!!!") == nil)
    let long = csiLogoFileName(id: nil, name: String(repeating: "abc ", count: 30))
    #expect(long.map { $0.count <= "csi-.png".count + 60 && !$0.contains("-.png") } == true)
    for name in ["US Esempio 2016", "Ünïcödé F.C.", String(repeating: "x-", count: 50), "a"] {
      #expect(csiLogoFileName(id: nil, name: name).map(isValidImportedLogoFileName) == true, "\(name)")
    }
  }

  @Test func importedLogoFileNamesAcceptCSINames() {
    for good in [
      "csi-12345678.png", "csi-us-esempio-2016.png", "csi-a.png", "csi-" + String(repeating: "a", count: 60) + ".png",
    ] {
      #expect(isValidImportedLogoFileName(good), "\(good)")
    }
    for bad in [
      "csi-.png", "csi-ABC.png", "CSI-12345678.png", "csi-a_b.png", "csi-a.b.png", "csi-../x.png", "csi-/x.png",
      "csi-é.png", "csi-a.PNG", "csi-a.jpg", "csi-" + String(repeating: "a", count: 61) + ".png", "xcsi-a.png",
    ] {
      #expect(!isValidImportedLogoFileName(bad), "\(bad)")
    }
    #expect(isValidImportedLogoFileName("917410.png"))  // tuttocampo names unchanged
  }

  func fixture(logo: String?, name: String = "US Esempio 2016") -> FetchedFixture {
    FetchedFixture(
      date: DayDate(year: 2026, month: 11, day: 21)!, time: nil, isHome: false, opponentName: name,
      opponentLogoURL: logo.flatMap { URL(string: $0) }, status: .scheduled, statusText: "-")
  }

  @Test func logoRequestFromFixture() throws {
    let opponent = Opponent(id: "o1", name: "U.S. Esempio")
    let request = try #require(
      CSILogoRequest(
        opponent: opponent,
        fixture: fixture(logo: "https://static.centrosportivoitaliano.it/modulistica/logo/12345678_1.jpg")))
    #expect(request.opponentID == "o1" && request.opponentName == "U.S. Esempio")
    #expect(request.fileName == "csi-12345678.png")
    let other = CSILogoRequest(opponent: opponent, fixture: fixture(logo: "https://example.com/logo/stemma.jpg"))
    #expect(other?.fileName == "csi-us-esempio-2016.png")  // no id: slug of the name CSI writes
    #expect(CSILogoRequest(opponent: opponent, fixture: fixture(logo: nil)) == nil)
    #expect(
      CSILogoRequest(
        opponent: opponent, fixture: fixture(logo: "https://cdncsi.csi-net.it/risultati/img_2/csi-shield-b.svg"))
        == nil)
    #expect(CSILogoRequest(opponent: opponent, fixture: fixture(logo: "data:image/png;base64,AAAA")) == nil)
    #expect(
      CSILogoRequest(opponent: opponent, fixture: fixture(logo: "https://example.com/x.jpg", name: "???")) == nil)
  }

  @Test func storingPageLogos() async throws {
    let paths = try AppPaths.temporary()
    let store = FakeLogoStore(folder: paths.logos)
    func request(_ id: String, _ name: String, file: String) throws -> CSILogoRequest {
      CSILogoRequest(
        opponentID: id, opponentName: name, logoURL: try #require(URL(string: "https://example.com/\(id).jpg")),
        fileName: file)
    }
    let png = FakeFixtureSource.defaultLogoData
    let one = try request("a", "Uno", file: "csi-12345678.png")
    let twin = try request("b", "Due", file: "csi-12345678.png")
    let missing = try request("c", "Tre", file: "csi-tre.png")
    let notImage = try request("d", "Quattro", file: "csi-quattro.png")
    let badName = try request("e", "Cinque", file: "../cinque.png")
    let results = await storeCSILogos(
      [
        CSILogoData(request: one, data: png), CSILogoData(request: twin, data: nil),
        CSILogoData(request: missing, data: nil), CSILogoData(request: notImage, data: Data("<html>".utf8)),
        CSILogoData(request: badName, data: png),
      ], in: store)
    #expect(results.map(\.request) == [one, twin, missing, notImage, badName])
    #expect(results.map(\.fileName) == ["csi-12345678.png", "csi-12345678.png", nil, nil, nil])
    #expect(
      results.map(\.issue) == [
        nil, nil, .csiLogoUnavailable(opponent: "Tre"), .csiLogoUnavailable(opponent: "Quattro"),
        .csiLogoUnavailable(opponent: "Cinque"),
      ])
    #expect(try FileManager.default.contentsOfDirectory(atPath: paths.logos.path) == ["csi-12345678.png"])

    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await storeCSILogos([CSILogoData(request: missing, data: png)], in: store)
    }
    let cancelled = await task.value
    #expect(cancelled.first?.fileName == nil && cancelled.first?.issue == nil)
  }

  // MARK: Report

  @Test func csiIssues() {
    let issues: [ImportIssue] = [
      .csiPageReadFailed(team: "Pulcini", reason: .tooLarge), .csiPageReadFailed(team: "Pulcini", reason: .failed),
      .csiNotAGirone(team: "Pulcini"), .csiNoFixturesOfOurs(team: "Pulcini", clubShortName: "Sergnanese"),
      .csiLogoUnavailable(opponent: "US Esempio"),
    ]
    for issue in issues {
      #expect(issue.message.hasPrefix("CSI: "), "\(issue)")
      #expect(!issue.message.contains("Tuttocampo"), "\(issue)")
    }
    #expect(issues.map(\.isError) == [true, true, true, true, false])
    #expect(issues[0].message != issues[1].message)
    #expect(issues[2].message.contains("Pulcini") && issues[2].message.contains("girone CSI"))
    #expect(issues[3].message.contains("Sergnanese") && issues[3].message.contains("Pulcini"))
    #expect(issues[4].message.contains("US Esempio"))
    // Tuttocampo messages are unchanged.
    #expect(ImportIssue.notYetAvailable(team: "Pulcini").message.hasPrefix("Tuttocampo: "))
  }

  @Test func issueForAPageWithoutFixtures() {
    func issue(_ outcome: FixtureFetch) -> ImportIssue? {
      ImportIssue.csiPage(team: "Pulcini", outcome: outcome, clubShortName: "Sergnanese")
    }
    let none = ImportIssue.csiNoFixturesOfOurs(team: "Pulcini", clubShortName: "Sergnanese")
    #expect(issue(.sourceProblem(.structureChanged)) == .csiNotAGirone(team: "Pulcini"))
    #expect(issue(.sourceProblem(.noFixturesOfOurs)) == none)
    #expect(issue(.notYetAvailable) == none)
    #expect(issue(.fixtures([])) == none)
    #expect(issue(.fixtures([fixture(logo: nil)])) == nil)
  }

  // MARK: Venue in candidates

  let team = Team(id: "team", name: "Pulcini", shortLabel: "Pul", sortOrder: 7, isFirstTeam: false, isActive: true)
  let opponent = Opponent(id: "o1", name: "U.S. Esempio 2016")

  func make(_ fixture: FetchedFixture, existing: [MatchDetail] = []) -> ImportCandidate {
    ImportCandidate.make(
      fixture: fixture, team: team, opponents: [opponent], existingMatches: existing, homeVenue: "Campo Comunale")
  }

  func withVenue(_ venue: String?, home: Bool) -> FetchedFixture {
    var fixture = fixture(logo: nil)
    fixture.isHome = home
    fixture.venue = venue
    return fixture
  }

  @Test func awayDraftsTakeTheFixtureVenue() {
    #expect(
      make(withVenue("Oratorio  Esempio Via Roma 1 - 26000 Esempio CR", home: false)).draft?.venue
        == "Oratorio Esempio Via Roma 1 - 26000 Esempio CR")
    #expect(make(withVenue("Oratorio Esempio", home: true)).draft?.venue == "Campo Comunale")  // home: homeVenue
    let away = make(withVenue(nil, home: false))  // tuttocampo: no venue
    #expect(away.draft?.venue == "" && away.isVenueMissing)
    let long = make(withVenue(String(repeating: "Campo ", count: 20), home: false)).draft?.venue ?? ""
    #expect(long.count <= FieldLimits.venue && long.hasSuffix("…"))
  }

  @Test func existingMatchVenueRules() throws {
    let date = Date(timeIntervalSince1970: 0)
    func stored(venue: String, home: Bool) -> MatchDetail {
      let match = Match(
        id: "m1", teamID: team.id, opponentID: opponent.id, date: DayDate(year: 2026, month: 11, day: 21)!,
        time: nil, isHome: home, venue: venue, status: .scheduled, createdAt: date, updatedAt: date)
      return MatchDetail(match: match, team: team, opponent: opponent)
    }
    let csi = withVenue("Oratorio Esempio", home: false)
    #expect(make(csi, existing: [stored(venue: "", home: false)]).draft?.venue == "Oratorio Esempio")
    #expect(make(csi, existing: [stored(venue: "Campo vecchio", home: false)]).draft?.venue == "Campo vecchio")
    #expect(make(csi, existing: [stored(venue: "Campo Comunale", home: true)]).draft?.venue == "Oratorio Esempio")
  }

  @Test func fixtureVenueIsOptionalInJSON() throws {
    let fixture = withVenue("Oratorio Esempio", home: false)
    #expect(try JSONDecoder().decode(FetchedFixture.self, from: JSONEncoder().encode(fixture)) == fixture)
    var object = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture)) as? [String: Any])
    object["venue"] = nil
    let old = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(FetchedFixture.self, from: old).venue == nil)
  }

  // MARK: Default parser

  @Test func servicesWithoutAParserSayNotAGirone() throws {
    let paths = try AppPaths.temporary()
    let database = FakeDatabase()
    let templates = FakeTemplateStore(folder: paths.templates)
    let teams = FakeTeamRepository(database: database)
    let opponents = FakeOpponentRepository(database: database)
    let matches = FakeMatchRepository(database: database)
    let settings = FakeSettingsRepository(database: database)
    let renders = FakeRenderRepository(database: database)
    let services = AppServices(
      teams: teams, opponents: opponents, matches: matches, settings: settings, renders: renders,
      logos: FakeLogoStore(folder: paths.logos), templates: templates,
      renderer: UnusedRenderService(),
      demoData: FakeDemoDataLoader(dataSet: .empty(), teams: teams, opponents: opponents, matches: matches),
      paths: paths)
    let url = try #require(URL(string: page))
    #expect(
      services.csiPageParser.parse(html: "<html></html>", pageURL: url, settings: .defaults)
        == .sourceProblem(.structureChanged))
  }
}

/// A render service that is never called, to build an `AppServices` without the main actor.
private struct UnusedRenderService: RenderService {
  func plan(_ request: RenderRequest) throws -> RenderPlan { throw AppError.notFound }
  func render(_ request: RenderRequest) -> AsyncThrowingStream<RenderEvent, any Error> {
    AsyncThrowingStream { $0.finish(throwing: AppError.notFound) }
  }
  func preview(templateID: String, matchIDs: [EntityID]) async throws -> URL { throw AppError.notFound }
}

// MARK: - Fakes

@MainActor
@Suite struct FakeCSITests {
  let services: AppServices

  init() throws {
    services = try AppServices.fake(dataSet: Fixtures.dataSet().shifted(toWeekendOf: .today()), renderDelay: .zero)
  }

  func team(_ name: String) throws -> Team { try #require(try services.teams.list().first { $0.name == name }) }

  /// The staging review of `team`'s CSI page, keyed by the opponent name as CSI writes it.
  func stage(_ team: Team, linking links: [String: EntityID] = [:]) throws -> [String: ImportCandidate] {
    let settings = try services.settings.load()
    let opponents = try services.opponents.list()
    let pageURL = try #require(team.csiPageURL.flatMap { URL(string: $0) })
    guard case .fixtures(let fixtures) = services.csiPageParser.parse(html: "", pageURL: pageURL, settings: settings)
    else {
      Issue.record("no fixtures")
      return [:]
    }
    var result: [String: ImportCandidate] = [:]
    for fixture in fixtures {
      let existing = try services.matches.list(from: fixture.date, to: fixture.date, teamID: team.id)
      result[fixture.opponentName] = ImportCandidate.make(
        fixture: fixture, team: team, opponents: opponents, existingMatches: existing,
        homeVenue: settings.homeVenue, linkedOpponentID: links[fixture.opponentName])
    }
    return result
  }

  @Test func scenarioCoversTheCSICases() throws {
    let pulcini = try team("Pulcini")
    #expect(pulcini.csiPageURL == FakePageFixtureParser.scenarioPageURL)
    let candidates = try stage(pulcini)
    #expect(
      candidates.mapValues(\.state) == [
        "Borgo Lucente": .new, "Prato Fiorito": .changed, "Valdorso 2016": .needsReview,
        "Polisportiva Fontanella": .needsReview, "Atletico Montesello": .new,
      ])
    #expect(candidates["Valdorso 2016"]?.reviewReasons == [.opponentNotFound])
    #expect(candidates["Borgo Lucente"]?.draft?.score == Score(us: 4, them: 2))
    #expect(candidates["Borgo Lucente"]?.fixture.opponentLogoURL == nil)
    #expect(candidates["Prato Fiorito"]?.draft?.venue == "Prato Fiorito")  // stored venue kept
    #expect(candidates["Atletico Montesello"]?.draft?.venue == "Campo Montesello Via Manzoni 2 - 26000 Montesello CR")

    let valdorso = try #require(try services.opponents.list().first { $0.name == "F.C. Valdorso" })
    let linked = try stage(pulcini, linking: ["Valdorso 2016": valdorso.id])
    #expect(linked["Valdorso 2016"]?.state == .changed)
  }

  @Test func scenarioLogos() async throws {
    let candidates = try stage(try team("Pulcini"))
    let montesello = try #require(candidates["Atletico Montesello"])
    let lucente = try #require(candidates["Borgo Lucente"])
    let montesselloOpponent = try #require(montesello.opponent)
    let lucenteOpponent = try #require(lucente.opponent)
    let request = try #require(CSILogoRequest(opponent: montesselloOpponent, fixture: montesello.fixture))
    #expect(request.fileName == "csi-90000104.png")
    #expect(CSILogoRequest(opponent: lucenteOpponent, fixture: lucente.fixture) == nil)

    let failing = try #require(FakePageFixtureParser.scenarioLogoURL("90000999"))
    let source = FakePageLogoSource(failingURLs: [failing])
    let broken = CSILogoRequest(opponentID: "x", opponentName: "Rotto", logoURL: failing, fileName: "csi-90000999.png")
    let fetched = await source.fetchLogos([request, broken])
    #expect(fetched.map(\.data) == [FakeFixtureSource.defaultLogoData, nil])
    let results = await storeCSILogos(fetched, in: services.logos)
    #expect(results.map(\.fileName) == ["csi-90000104.png", nil])
    #expect(results.map(\.issue) == [nil, .csiLogoUnavailable(opponent: "Rotto")])
    #expect(FileManager.default.fileExists(atPath: services.logos.url(for: "csi-90000104.png").path))
  }

  @Test func otherPagesAreNotAGirone() throws {
    let settings = try services.settings.load()
    for address in [
      "https://live.centrosportivoitaliano.it/26/Calcio-a-7/Lombardia/Esempio/C00001/G000009-girone-b-2016/",
      "https://example.com/x",
    ] {
      let url = try #require(URL(string: address))
      #expect(
        services.csiPageParser.parse(html: "", pageURL: url, settings: settings) == .sourceProblem(.structureChanged))
    }
    // The query is ignored.
    let withQuery = try #require(URL(string: FakePageFixtureParser.scenarioPageURL + "?j=abc"))
    #expect(
      services.csiPageParser.parse(html: "", pageURL: withQuery, settings: settings)
        != .sourceProblem(.structureChanged))
  }

  @Test func csiPagesAreStoredAndUnique() throws {
    let services = try AppServices.fake(dataSet: .empty())
    let page = "https://live.centrosportivoitaliano.it/26/Calcio-a-7/Lombardia/Esempio/C00001/G000001-girone-a/"
    let first = try services.teams.create(
      TeamDraft(
        name: "Pulcini", shortLabel: "Pulcini",
        csiPageURL: " live.centrosportivoitaliano.it/26/Calcio-a-7/Lombardia/Esempio/C00001/G000001-girone-a/ "))
    #expect(first.csiPageURL == page)
    #expect(throws: AppError.csiPageURLInUse(by: "Pulcini")) {
      try services.teams.create(
        TeamDraft(
          name: "Altra", shortLabel: "Altra",
          csiPageURL: page.uppercased().replacingOccurrences(of: "HTTPS", with: "https") + "?j=x"))
    }
    let second = try services.teams.create(TeamDraft(name: "Altra", shortLabel: "Altra"))
    var draft = TeamDraft(second)
    draft.csiPageURL = page + "?j=altro"
    #expect(throws: AppError.csiPageURLInUse(by: "Pulcini")) { try services.teams.update(id: second.id, with: draft) }
    // A team may keep its own page; clearing it frees the page.
    #expect(try services.teams.update(id: first.id, with: TeamDraft(first)).csiPageURL == page)
    var cleared = TeamDraft(first)
    cleared.csiPageURL = ""
    #expect(try services.teams.update(id: first.id, with: cleared).csiPageURL == nil)
    #expect(try services.teams.update(id: second.id, with: draft).csiPageURL == page + "?j=altro")
    #expect(throws: AppError.self) {
      try services.teams.create(TeamDraft(name: "X", shortLabel: "X", csiPageURL: "https://example.com/26/x/"))
    }
  }

  @Test func fixtureCSIPagesAreValidAndUnique() throws {
    let data = try Fixtures.dataSet()
    let pages = data.teams.compactMap(\.csiPageURL)
    #expect(pages == [FakePageFixtureParser.scenarioPageURL])
    #expect(pages.allSatisfy(isValidCSIPageURL))
    #expect(Set(pages.compactMap(csiPageKey)).count == pages.count)
    #expect(data.teams.first { $0.csiPageURL != nil }?.name == "Pulcini")
  }
}
