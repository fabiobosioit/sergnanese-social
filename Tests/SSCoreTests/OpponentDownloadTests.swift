import Foundation
import SSCoreFakes
import Testing

@testable import SSCore

/// T4.9: source teams, review rows, duplicate pairs, the import plan and the new report lines.
@Suite struct OpponentDownloadTests {
  let valdorso = Opponent(id: "o-valdorso", name: "F.C. Valdorso", logoFile: "valdorso.png")
  let lucente = Opponent(id: "o-lucente", name: "Pol. Borgo Lucente")
  let montesello = Opponent(id: "o-montesello", name: "Atletico Montesello")
  let ilario = Opponent(id: "o-ilario", name: "G.S. Sant’Ilario Città", aliases: ["Sant'Ilario"], logoFile: "i.png")
  let gerolamo = Opponent(id: "o-gerolamo", name: "A.S.D. Oratorio San Gerolamo", logoFile: "g.png")

  func tc(_ name: String, club: String? = nil, team: EntityID = "t1") -> SourceTeam {
    SourceTeam(
      source: .tuttocampo, teamID: team, name: name, logoID: club,
      logoURL: club.flatMap { URL(string: "https://b2-content.tuttocampo.it/Teams/40/\($0).png?v=1") })
  }

  func csi(_ name: String, id: String? = nil, team: EntityID = "t8") -> SourceTeam {
    SourceTeam(
      source: .csi, teamID: team, name: name, logoID: id,
      logoURL: id.flatMap { URL(string: "https://static.centrosportivoitaliano.it/modulistica/logo/\($0)_1.jpg") })
  }

  func make(_ found: [SourceTeam], _ existing: [Opponent] = []) -> [OpponentCandidate] {
    OpponentCandidate.make(found: found, existing: existing, clubShortName: "Sergnanese")
  }

  // MARK: Duplicate key

  @Test func duplicateKeyRemovesOneTrailingAgeGroupToken() {
    let cases: [(String, String)] = [
      ("US Standard 2016", "standard"), ("Real Fontanile B", "real fontanile"), ("Aurora U14", "aurora"),
      ("Aurora u9", "aurora"), ("Aurora Under 14", "aurora"), ("Aurora 2000", "aurora"), ("Aurora 2030", "aurora"),
      ("Aurora 1999", "aurora 1999"), ("Aurora 2031", "aurora 2031"), ("Aurora U123", "aurora u123"),
      ("Real 2016 B", "real 2016"), ("US 2016", "2016"), ("Under 14", "under 14"), ("Città B", "citta"),
      ("Oratorio Sant’Elia 2015", "oratorio sant elia"),
      ("Riozzese 2015 S.r.l.", "riozzese"), ("Real Meda Sq.B", "real meda sq"), ("B", "b"), ("Aurora", "aurora"),
    ]
    for (name, key) in cases { #expect(opponentDuplicateKey(name) == key, "\(name)") }
  }

  // MARK: Rows

  @Test func rowsGroupSpellingsAndLeaveOutTheClub() {
    let first = tc("Real Fontanile", club: "1")
    let rows = make([
      first, csi("REAL   fontanile ", id: "90000001"), first, tc("A.S.D. Sergnanese", club: "917410"), tc("   "),
    ])
    #expect(rows.count == 1)
    #expect(rows.first?.id == "real fontanile")
    #expect(rows.first?.name == "Real Fontanile")
    #expect(rows.first?.sightings.count == 2)
    #expect(rows.first?.state == .new)
    #expect(rows.first?.isTickedByDefault == true)
  }

  @Test func rowStatesAgainstExistingOpponents() {
    let twinA = Opponent(id: "o-twin-a", name: "Twin Alpha", aliases: ["Twin"])
    let twinB = Opponent(id: "o-twin-b", name: "Twin Beta", aliases: ["Twin"])
    let rows = make(
      [
        tc("Oratorio San Gerolamo", club: "1"), tc("Borgo Lucente", club: "2"), tc("Atletico Montesello"),
        tc("Sant’Ilario", club: "3"), tc("Twin", club: "4"), tc("Nuova Aurora", club: "5"),
      ], [valdorso, lucente, montesello, ilario, gerolamo, twinA, twinB])
    let states = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0.state) })
    #expect(
      states == [
        "Oratorio San Gerolamo": .present, "Borgo Lucente": .missingLogo, "Atletico Montesello": .present,
        "Sant’Ilario": .present, "Twin": .present, "Nuova Aurora": .new,
      ])
    #expect(rows.map(\.id) == rows.map(\.id).sorted())
    #expect(rows.first { $0.name == "Borgo Lucente" }?.existing == lucente)
    #expect(rows.first { $0.name == "Twin" }?.existing == twinA)
    #expect(rows.first { $0.name == "Nuova Aurora" }?.existing == nil)
    #expect(rows.first { $0.name == "Twin" }?.isTickedByDefault == false)
  }

  @Test func longNamesAreCutToTheOpponentLimit() throws {
    let long = String(repeating: "Polisportiva Dilettantistica ", count: 5) + "Esempio"
    let row = try #require(make([tc(long)]).first)
    #expect(row.name.count <= FieldLimits.opponentName)
    #expect(row.name.hasSuffix("…"))
    #expect(row.id == importNameKey(row.name))
  }

  @Test func logoPrefersTuttocampoWithAClubID() {
    let urlOnly = SourceTeam(
      source: .tuttocampo, teamID: "t1", name: "X", logoURL: URL(string: "https://example.invalid/x.png"))
    let row = { (sightings: [SourceTeam]) in
      OpponentCandidate(id: "x", name: "X", sightings: sightings, existing: nil, state: .new)
    }
    #expect(row([csi("X", id: "90000001"), urlOnly, tc("X", club: "7")]).logo == tc("X", club: "7"))
    #expect(row([urlOnly, csi("X", id: "90000001")]).logo == csi("X", id: "90000001"))
    #expect(row([csi("X"), urlOnly]).logo == urlOnly)
    #expect(row([csi("X"), tc("X")]).logo == nil)
  }

  // MARK: Pairs

  @Test func possibleDuplicatesAmongNewRowsAndExistingOpponents() {
    let prato = Opponent(id: "o-prato", name: "A.C. Prato Fiorito", logoFile: "p.png")
    let existing = [valdorso, prato, ilario]
    let rows = make(
      [
        tc("Real Fontanile", club: "1"), csi("Real Fontanile B", id: "90000005"), csi("Valdorso 2016", id: "90000002"),
        tc("Prato Fiorito", club: "2"), tc("Prato Fiorito B", club: "3"), tc("Sant'Ilario U14"),
      ], existing)
    let pairs = OpponentCandidate.possibleDuplicatePairs(in: rows, existing: existing)
    #expect(
      pairs.map(\.id) == [
        "prato fiorito b|o:o-prato", "real fontanile|c:real fontanile b", "sant'ilario u14|o:o-ilario",
        "valdorso 2016|o:o-valdorso",
      ])
    #expect(pairs.first { $0.second == .opponent(ilario) }?.secondName == "G.S. Sant’Ilario Città")
    #expect(pairs.first { $0.second.candidateID != nil }?.firstName == "Real Fontanile")
    #expect(pairs.first { $0.second.candidateID != nil }?.secondName == "Real Fontanile B")
    let states = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0.state) })
    #expect(states["Prato Fiorito"] == .present)
    #expect(states["Prato Fiorito B"] == .possibleDuplicate)
    #expect(states["Real Fontanile"] == .possibleDuplicate)
    #expect(states["Real Fontanile B"] == .possibleDuplicate)
    #expect(states["Valdorso 2016"] == .possibleDuplicate)
  }

  @Test func noPairBetweenDifferentClubs() {
    let rows = make([tc("Real Fontanile"), tc("Real Fontanella"), tc("Aurora 2016"), tc("Aurora Pianengo 2016")])
    #expect(OpponentCandidate.possibleDuplicatePairs(in: rows, existing: []).isEmpty)
    #expect(rows.allSatisfy { $0.state == .new })
  }

  // MARK: Plan

  /// Rows: Aurora Pianengo (new), Borgo Lucente (missing logo), Oratorio Nuovo (new, no logo), Real Fontanile and
  /// Real Fontanile B (pair), Valdorso 2016 (pair with F.C. Valdorso).
  var review: (rows: [OpponentCandidate], pairs: [OpponentDuplicatePair], all: Set<String>) {
    let existing = [valdorso, lucente, montesello]
    let rows = make(
      [
        tc("Real Fontanile", club: "900302"), csi("Real Fontanile B", id: "90000105"),
        csi("Valdorso 2016", id: "90000102"), tc("Borgo Lucente", club: "900301"),
        tc("Aurora Pianengo", club: "900303"), tc("Oratorio Nuovo"),
      ], existing)
    return (rows, OpponentCandidate.possibleDuplicatePairs(in: rows, existing: existing), Set(rows.map(\.id)))
  }

  let fontanilePair = "real fontanile|c:real fontanile b"
  let valdorsoPair = "valdorso 2016|o:o-valdorso"

  @Test func planNeedsAChoiceForEveryPair() {
    let (rows, pairs, all) = review
    #expect(throws: OpponentPlanError.choicesMissing(pairIDs: [fontanilePair, valdorsoPair])) {
      try OpponentImportPlan.make(candidates: rows, ticked: all, pairs: pairs, choices: [:]).items.count
    }
    #expect(throws: OpponentPlanError.choicesMissing(pairIDs: [fontanilePair])) {
      try OpponentImportPlan.make(candidates: rows, ticked: all, pairs: pairs, choices: [valdorsoPair: .useFirst])
        .items.count
    }
    #expect(OpponentPlanError.choicesMissing(pairIDs: []).message == "Scegli cosa fare per ogni possibile duplicato.")
  }

  @Test func planMergesIntoTheChosenName() throws {
    let (rows, pairs, all) = review
    let plan = try OpponentImportPlan.make(
      candidates: rows, ticked: all, pairs: pairs, choices: [fontanilePair: .useFirst, valdorsoPair: .useSecond])
    #expect(
      plan.items == [
        .init(
          action: .create(name: "Aurora Pianengo", aliases: []), logo: tc("Aurora Pianengo", club: "900303"),
          candidateIDs: ["aurora pianengo"]),
        .init(
          action: .update(opponentID: "o-lucente", rename: nil, addAliases: []),
          logo: tc("Borgo Lucente", club: "900301"), candidateIDs: ["borgo lucente"]),
        .init(action: .create(name: "Oratorio Nuovo", aliases: []), logo: nil, candidateIDs: ["oratorio nuovo"]),
        .init(
          action: .create(name: "Real Fontanile", aliases: ["Real Fontanile B"]),
          logo: tc("Real Fontanile", club: "900302"), candidateIDs: ["real fontanile", "real fontanile b"]),
        .init(
          action: .update(opponentID: "o-valdorso", rename: nil, addAliases: ["Valdorso 2016"]), logo: nil,
          candidateIDs: ["valdorso 2016"]),
      ])
  }

  @Test func planRenamesWhenTheFoundNameIsChosen() throws {
    let (rows, pairs, all) = review
    let plan = try OpponentImportPlan.make(
      candidates: rows, ticked: all, pairs: pairs, choices: [fontanilePair: .useSecond, valdorsoPair: .useFirst])
    #expect(
      plan.items.map(\.action).suffix(2) == [
        .create(name: "Real Fontanile B", aliases: ["Real Fontanile"]),
        .update(opponentID: "o-valdorso", rename: "Valdorso 2016", addAliases: []),
      ])
    // The tuttocampo logo wins over the CSI one, whatever name is chosen; the existing logo is kept.
    #expect(plan.items.suffix(2).map(\.logo) == [tc("Real Fontanile", club: "900302"), nil])
  }

  @Test func planKeepsSeparateRowsSeparate() throws {
    let (rows, pairs, all) = review
    let plan = try OpponentImportPlan.make(
      candidates: rows, ticked: all, pairs: pairs,
      choices: [fontanilePair: .keepSeparate, valdorsoPair: .keepSeparate])
    #expect(
      plan.items.map(\.action).suffix(3) == [
        .create(name: "Real Fontanile", aliases: []), .create(name: "Real Fontanile B", aliases: []),
        .create(name: "Valdorso 2016", aliases: []),
      ])
    #expect(plan.items.last?.logo == csi("Valdorso 2016", id: "90000102"))
  }

  @Test func planIgnoresUntickedAndPresentRows() throws {
    let (rows, pairs, _) = review
    let ticked: Set = ["aurora pianengo", "real fontanile", "valdorso 2016"]
    let plan = try OpponentImportPlan.make(
      candidates: rows, ticked: ticked, pairs: pairs, choices: [valdorsoPair: .keepSeparate])
    #expect(plan.items.flatMap(\.candidateIDs) == ["aurora pianengo", "real fontanile", "valdorso 2016"])

    let present = make([tc("Oratorio San Gerolamo", club: "1")], [gerolamo])
    let empty = try OpponentImportPlan.make(
      candidates: present, ticked: Set(present.map(\.id)), pairs: [], choices: [:])
    #expect(empty.items.isEmpty)
  }

  /// "Real Fontanile", "Real Fontanile B" and "Real Fontanile 2016" are pairwise possible duplicates.
  var triangle: (rows: [OpponentCandidate], pairs: [OpponentDuplicatePair], all: Set<String>) {
    let rows = make([tc("Real Fontanile", club: "1"), tc("Real Fontanile B", club: "2"), tc("Real Fontanile 2016")])
    return (rows, OpponentCandidate.possibleDuplicatePairs(in: rows, existing: []), Set(rows.map(\.id)))
  }

  @Test func planMergesAChainIntoOneOpponent() throws {
    let (rows, pairs, all) = triangle
    #expect(pairs.count == 3)
    let a = "real fontanile|c:real fontanile 2016"
    let b = "real fontanile|c:real fontanile b"
    let c = "real fontanile 2016|c:real fontanile b"
    let plan = try OpponentImportPlan.make(
      candidates: rows, ticked: all, pairs: pairs, choices: [a: .useSecond, b: .useFirst, c: .useFirst])
    #expect(
      plan.items.map(\.action) == [
        .create(name: "Real Fontanile 2016", aliases: ["Real Fontanile", "Real Fontanile B"])
      ]
    )
    #expect(plan.items.first?.logo == tc("Real Fontanile", club: "1"))
  }

  @Test func planRefusesConflictingChoices() {
    let (rows, pairs, all) = triangle
    let a = "real fontanile|c:real fontanile 2016"
    let b = "real fontanile|c:real fontanile b"
    let c = "real fontanile 2016|c:real fontanile b"
    // Both others into Real Fontanile, but kept separate from each other.
    #expect(throws: OpponentPlanError.self) {
      try OpponentImportPlan.make(
        candidates: rows, ticked: all, pairs: pairs, choices: [a: .useFirst, b: .useFirst, c: .keepSeparate])
    }
    // A circle: each name set aside once.
    #expect(throws: OpponentPlanError.self) {
      try OpponentImportPlan.make(
        candidates: rows, ticked: all, pairs: pairs, choices: [a: .useSecond, b: .useFirst, c: .useSecond])
    }
    // Two new names both chosen in one group.
    do {
      _ = try OpponentImportPlan.make(
        candidates: rows, ticked: all, pairs: pairs, choices: [a: .useSecond, b: .useSecond, c: .keepSeparate])
      Issue.record("expected a conflict")
    } catch {
      guard case .conflictingChoices(let ids, let names) = error else {
        Issue.record("unexpected \(error)")
        return
      }
      #expect(Set(ids) == [a, b, c])
      #expect(Set(names) == ["Real Fontanile", "Real Fontanile B", "Real Fontanile 2016"])
      #expect(error.message.hasPrefix("Le scelte per «"))
    }
  }

  @Test func planNeverMergesTwoExistingOpponents() {
    let standard = Opponent(id: "o-standard", name: "US Standard")
    let standardB = Opponent(id: "o-standard-b", name: "Standard B")
    let existing = [standard, standardB]
    let rows = make([tc("Standard 2016", club: "1")], existing)
    let pairs = OpponentCandidate.possibleDuplicatePairs(in: rows, existing: existing)
    #expect(pairs.map(\.id) == ["standard 2016|o:o-standard", "standard 2016|o:o-standard-b"])
    #expect(throws: OpponentPlanError.self) {
      try OpponentImportPlan.make(
        candidates: rows, ticked: Set(rows.map(\.id)), pairs: pairs,
        choices: [pairs[0].id: .useSecond, pairs[1].id: .useSecond])
    }
    let plan = try? OpponentImportPlan.make(
      candidates: rows, ticked: Set(rows.map(\.id)), pairs: pairs,
      choices: [pairs[0].id: .useSecond, pairs[1].id: .keepSeparate])
    #expect(
      plan?.items.map(\.action) == [.update(opponentID: "o-standard", rename: nil, addAliases: ["Standard 2016"])])
    #expect(plan?.items.first?.logo == tc("Standard 2016", club: "1"))
  }

  @Test func planJoinsALogoOnlyRowWithAMergeOnTheSameOpponent() throws {
    let existing = [lucente]
    let rows = make([tc("Borgo Lucente", club: "1"), csi("Borgo Lucente 2016", id: "90000009")], existing)
    let pairs = OpponentCandidate.possibleDuplicatePairs(in: rows, existing: existing)
    #expect(rows.map(\.state) == [.missingLogo, .possibleDuplicate])
    let plan = try OpponentImportPlan.make(
      candidates: rows, ticked: Set(rows.map(\.id)), pairs: pairs, choices: [pairs[0].id: .useFirst])
    #expect(
      plan.items == [
        .init(
          action: .update(opponentID: "o-lucente", rename: "Borgo Lucente 2016", addAliases: []),
          logo: tc("Borgo Lucente", club: "1"), candidateIDs: ["borgo lucente", "borgo lucente 2016"])
      ])
  }

  @Test func actionDrafts() {
    let current = Opponent(
      id: "o", name: "F.C. Valdorso", shortName: "Valdorso", aliases: ["Valdorso FC"], logoFile: "v.png")
    let rename = OpponentImportPlan.Action.update(opponentID: "o", rename: "Valdorso 2016", addAliases: ["Valdorso B"])
    #expect(
      rename.draft(current: current)
        == OpponentDraft(
          name: "Valdorso 2016", shortName: "Valdorso", aliases: ["Valdorso FC", "F.C. Valdorso", "Valdorso B"],
          logoFile: "v.png"))
    #expect(rename.draft(current: nil) == nil)
    #expect(
      OpponentImportPlan.Action.create(name: "Aurora", aliases: ["Aurora B"]).draft(current: current)
        == OpponentDraft(name: "Aurora", aliases: ["Aurora B"]))
  }

  // MARK: Lists, logos, report

  @Test func listStampsItsTeamAndSource() {
    let list = SourceTeamList(teamID: "t8", source: .csi, readAt: Date(timeIntervalSince1970: 0), teams: [tc("X")])
    #expect(list.teams == [SourceTeam(source: .csi, teamID: "t8", name: "X")])
  }

  @Test func listRoundTripsThroughJSON() throws {
    let list = SourceTeamList(
      teamID: "t8", source: .csi, readAt: Date(timeIntervalSince1970: 1_800_000_000),
      teams: [csi("Valdorso 2016", id: "90000102"), csi("Borgo Lucente")])
    let data = try JSONEncoder().encode(list)
    #expect(try JSONDecoder().decode(SourceTeamList.self, from: data) == list)
  }

  @Test func logoRequestsFromSourceTeams() throws {
    let tuttocampo = try #require(LogoRequest(opponent: lucente, sourceTeam: tc("Borgo Lucente", club: "900301")))
    #expect(tuttocampo.clubID == "900301")
    #expect(tuttocampo.opponentID == "o-lucente")
    #expect(tuttocampo.fallbackURL?.absoluteString == "https://b2-content.tuttocampo.it/Teams/40/900301.png?v=1")
    var unrecognised = tc("Borgo Lucente")
    unrecognised.logoURL = URL(string: "https://b2-content.tuttocampo.it/Web/Images/stemma.png")
    #expect(LogoRequest(opponent: lucente, sourceTeam: unrecognised)?.clubID == nil)
    #expect(LogoRequest(opponent: lucente, sourceTeam: tc("Borgo Lucente")) == nil)
    #expect(LogoRequest(opponent: lucente, sourceTeam: csi("Borgo Lucente", id: "90000001")) == nil)

    let fromCSI = try #require(CSILogoRequest(opponent: montesello, sourceTeam: csi("Montesello", id: "90000104")))
    #expect(fromCSI.fileName == "csi-90000104.png")
    var noID = csi("US Esempio 2016", id: "90000104")
    noID.logoID = nil
    #expect(CSILogoRequest(opponent: montesello, sourceTeam: noID)?.fileName == "csi-90000104.png")
    var slugOnly = noID
    slugOnly.logoURL = URL(string: "https://static.centrosportivoitaliano.it/other/logo.png")
    #expect(CSILogoRequest(opponent: montesello, sourceTeam: slugOnly)?.fileName == "csi-us-esempio-2016.png")
    var placeholder = noID
    placeholder.logoURL = URL(string: "https://cdncsi.csi-net.it/risultati/img_2/csi-shield-b.svg")
    #expect(CSILogoRequest(opponent: montesello, sourceTeam: placeholder) == nil)
    #expect(CSILogoRequest(opponent: montesello, sourceTeam: csi("Montesello")) == nil)
    #expect(CSILogoRequest(opponent: montesello, sourceTeam: tc("Montesello", club: "1")) == nil)
  }

  @Test func reportLines() {
    #expect(
      ImportIssue.standingsReadFailed(team: "Juniores", reason: .network).message
        == "Tuttocampo: impossibile leggere la classifica di Juniores. Controlla la connessione a internet e riprova.")
    #expect(
      ImportIssue.standingsChanged(team: "Juniores").message
        == "Tuttocampo: impossibile leggere la classifica di Juniores. La sorgente potrebbe essere cambiata.")
    #expect(
      ImportIssue.csiTeamListMissing(team: "Pulcini").message
        == "CSI: nessuna lettura per Pulcini, usa prima Importa da CSI…")
    #expect(ImportIssue.standingsReadFailed(team: "J", reason: .timeout).isError)
    #expect(ImportIssue.standingsChanged(team: "J").isError)
    #expect(!ImportIssue.csiTeamListMissing(team: "P").isError)
  }

  @Test func containersBuiltBeforeT49HaveSafeDefaults() async throws {
    let team = Team(
      id: "t", name: "Juniores", shortLabel: "Jun", sortOrder: 0, isFirstTeam: true, isActive: true,
      tuttocampoWidgetID: "00000000-0000-4000-8000-000000000001")
    await #expect(throws: FixtureFetchError.unavailable) {
      try await UnavailableFixtureSource().fetchLeagueTeams(for: team, settings: .defaults)
    }
    let page = try #require(URL(string: FakePageFixtureParser.scenarioPageURL))
    #expect(UnavailablePageFixtureParser().teams(html: "", pageURL: page, for: team, settings: .defaults).isEmpty)
    let store = UnavailableSourceTeamListRepository()
    try store.save(teamID: "t", source: .csi, teams: [csi("X")], readAt: Date())
    #expect(try store.latest(teamID: "t", source: .csi) == nil)
  }
}
