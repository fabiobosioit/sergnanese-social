import Foundation
import SSCoreFakes
import Testing

@testable import SSCore

/// T4.10: opponent matching (exact key, proposals, candidates). The core table is the one in
/// `docs/plan/tasks/wave-4-later.md` ("Expected results").
@Suite struct OpponentMatchingTests {
  enum Expected: Sendable, CustomStringConvertible {
    case exact(String)
    case proposed(String)
    case notFound
    case ambiguous([String])

    var description: String {
      switch self {
      case .exact(let name): "exact \(name)"
      case .proposed(let name): "proposed \(name)"
      case .notFound: "none"
      case .ambiguous(let names): "ambiguous \(names)"
      }
    }
  }

  struct Row: Sendable, CustomTestStringConvertible {
    var name: String
    var aliases: [String] = []
    var stored: [String]
    var expected: Expected
    var testDescription: String { "\(name) \(aliases) vs \(stored) → \(expected)" }
  }

  static let table: [Row] = [
    Row(name: "CREMONESE", aliases: ["CREMONESE S.P.A."], stored: ["Cremonese"], expected: .exact("Cremonese")),
    Row(
      name: "CREMONESE", aliases: ["CREMONESE S.P.A."], stored: ["U.S. Cremonese S.p.A."],
      expected: .exact("U.S. Cremonese S.p.A.")),
    Row(name: "RIOZZESE", aliases: ["RIOZZESE A R.L."], stored: ["Riozzese"], expected: .exact("Riozzese")),
    Row(
      name: "ALCIONE", aliases: ["ALCIONE MILANO SSD A RL"], stored: ["Alcione Milano"],
      expected: .exact("Alcione Milano")),
    Row(name: "ALCIONE", stored: ["Alcione Milano"], expected: .proposed("Alcione Milano")),
    Row(
      name: "S. BERNARDO CALCIO", aliases: ["SAN BERNARDO CALCIO"], stored: ["San Bernardo"],
      expected: .proposed("San Bernardo")),
    Row(name: "WOMEN RIVANAZZANESE", stored: ["Rivanazzanese"], expected: .proposed("Rivanazzanese")),
    Row(name: "PAVIA CALCIO 1911", stored: ["Pavia 1911"], expected: .proposed("Pavia 1911")),
    Row(name: "PAVIA CALCIO 1911", stored: ["Pavia 1950"], expected: .notFound),
    Row(name: "REAL MEDA CF Sq.B", stored: ["Real Meda Cf"], expected: .proposed("Real Meda Cf")),
    Row(name: "FIAMMA MONZA 1970", stored: ["Atalanta Bc"], expected: .notFound),
    Row(
      name: "ALCIONE", stored: ["Alcione Milano", "Alcione Bergamo"],
      expected: .ambiguous(["Alcione Bergamo", "Alcione Milano"])),
    Row(name: "CREMONESE", stored: ["Cremonese Women", "Cremonese"], expected: .exact("Cremonese")),
  ]

  let team = Team(id: "team", name: "Femminile", shortLabel: "Femm.", sortOrder: 1, isFirstTeam: false, isActive: true)

  func fixture(_ name: String, aliases: [String] = []) -> FetchedFixture {
    FetchedFixture(
      date: DayDate(year: 2026, month: 11, day: 29)!, time: ClockTime(hour: 10, minute: 0), isHome: true,
      opponentName: name, status: .scheduled, statusText: "", opponentAliases: aliases)
  }

  func opponents(_ names: [String]) -> [Opponent] {
    names.enumerated().map { Opponent(id: "o\($0.offset)", name: $0.element) }
  }

  func make(_ fixture: FetchedFixture, _ opponents: [Opponent], linked: EntityID? = nil) -> ImportCandidate {
    ImportCandidate.make(
      fixture: fixture, team: team, opponents: opponents, existingMatches: [], homeVenue: "Campo Comunale",
      linkedOpponentID: linked, source: .pdf)
  }

  // MARK: Core table

  @Test(arguments: table) func expectedResults(_ row: Row) throws {
    let candidate = make(fixture(row.name, aliases: row.aliases), opponents(row.stored))
    switch row.expected {
    case .exact(let name):
      #expect(candidate.opponentMatch == .exact)
      #expect(candidate.opponent?.name == name)
      #expect(candidate.state == .new && candidate.reviewReasons.isEmpty)
    case .proposed(let name):
      #expect(candidate.opponentMatch == .proposed)
      #expect(candidate.opponent?.name == name)
      #expect(candidate.draft?.opponentID == candidate.opponent?.id)
      #expect(candidate.state == .new && candidate.reviewReasons.isEmpty)
      #expect(candidate.proposals.first?.opponent.name == name)
      // Never exact: the key differs.
      #expect(opponentsMatching(name: row.name, in: opponents(row.stored)).isEmpty)
    case .notFound:
      #expect(candidate.opponentMatch == .notFound)
      #expect(candidate.opponent == nil && candidate.draft == nil)
      #expect(candidate.reviewReasons == [.opponentNotFound])
      #expect(candidate.proposals.isEmpty)
    case .ambiguous(let names):
      #expect(candidate.opponentMatch == .ambiguous)
      #expect(candidate.opponent == nil && candidate.draft == nil)
      #expect(candidate.reviewReasons == [.opponentAmbiguous])
      #expect(candidate.proposals.map(\.opponent.name) == names)
    }
  }

  // MARK: Level 1 key

  @Test(arguments: [
    ("U.S. Cremonese S.p.A.", "cremonese"), ("Cremonese SPA", "cremonese"), ("Cremonese S.r.l.", "cremonese"),
    ("Riozzese A R.L.", "riozzese"), ("Riozzese a.r.l.", "riozzese"), ("Riozzese Scarl", "riozzese"),
    ("Alcione Milano SSD A RL", "alcione milano"), ("Alcione Milano S.S.D. a r.l.", "alcione milano"),
    ("Alcione Milano SSDRL", "alcione milano"), ("Alcione Milano S.S.D.", "alcione milano"),
    ("Alcione Milano ASD", "alcione milano"), ("A. S. D. Oratorio San Gerolamo", "oratorio san gerolamo"),
    ("Pol. Borgo Lucente S.r.l.", "borgo lucente"), ("Sant’Ilario Città", "sant ilario citta"),
    ("Sant'Ilario-Città", "sant ilario citta"), ("REAL MEDA CF Sq.B", "real meda cf sq b"),
    ("  Fiamma   Monza 1970 ", "fiamma monza 1970"), ("ASD", "asd"), ("SSD a r.l.", "a r l"), ("", ""), ("…", ""),
    ("Spartak", "spartak"), ("Real Spazio", "real spazio"),
  ])
  func matchKey(_ name: String, _ key: String) {
    #expect(opponentMatchKey(name) == key)
  }

  @Test func exactMatchingUsesTheKey() {
    let stored = [Opponent(id: "a", name: "U.S. Cremonese S.p.A."), Opponent(id: "b", name: "Cremonese Women")]
    #expect(opponentsMatching(name: "CREMONESE", in: stored).map(\.id) == ["a"])
    #expect(opponentsMatching(name: "cremonese s.r.l.", in: stored).map(\.id) == ["a"])
    #expect(opponentsMatching(name: "Cremonese 1903", in: stored).isEmpty)
  }

  // MARK: Tokens

  @Test func editDistanceNeedsSixLettersOnBothSides() {
    #expect(editDistance("kitten", "sitting", limit: 5) == 3)
    #expect(editDistance("", "abc", limit: 5) == 3)
    #expect(editDistance("abc", "abc", limit: 0) == 0)
    #expect(editDistance("abcdef", "uvwxyz", limit: 1) == 2)
    #expect(matchTokensEqual("rivanazzanese", "rivanazanese"))  // one letter removed
    #expect(matchTokensEqual("monzese", "monzesi"))  // one letter changed, 7 letters
    #expect(matchTokensEqual("pavias", "paviaz"))  // 6 letters
    #expect(!matchTokensEqual("pavia", "pavio"))  // 5 letters: must be identical
    #expect(!matchTokensEqual("monzese", "monzasi"))  // distance 2
    #expect(matchTokensEqual("meda", "meda"))
  }

  @Test func tokensDropGenericWordsYearsAndSquadMarkers() {
    let pavia = MatchTokens("A.S.D. Pavia Calcio 1911")
    #expect(pavia.significant == ["pavia"] && pavia.years == ["1911"] && pavia.squad == nil)
    let meda = MatchTokens("REAL MEDA CF Sq.B")
    #expect(meda.significant == ["real", "meda"] && meda.squad == "b")
    #expect(MatchTokens("Real Meda 2").squad == "2")
    #expect(MatchTokens("Real Meda C").squad == "c")
    #expect(MatchTokens("S. Bernardo").significant == ["san", "bernardo"])
    #expect(MatchTokens("Sta Maria Sto Stefano").significant == ["santa", "maria", "santo", "stefano"])
    #expect(MatchTokens("Women Femminile Calcio").significant == ["women", "femminile", "calcio"])  // all generic
    #expect(MatchTokens("B").squad == nil)
  }

  @Test func yearsOnBothSidesMustBeEqual() {
    let stored = opponents(["Cremonese"])
    #expect(rankOpponents(name: "Cremonese 1903", aliases: [], in: stored).first?.kind == .similar)
    #expect(rankOpponents(name: "Cremonese 1903", aliases: [], in: opponents(["Cremonese 1903 B"])).count == 1)
    #expect(rankOpponents(name: "Cremonese 1903", aliases: [], in: opponents(["Cremonese 1910"])).isEmpty)
  }

  @Test func squadMarkersAllowAProposalButNeverAnExactLink() {
    for (name, stored) in [
      ("Real Meda Sq. B", "Real Meda"), ("Real Meda B", "Real Meda A"), ("Real Meda 2", "Real Meda"),
    ] {
      let candidate = make(fixture(name), opponents([stored]))
      #expect(candidate.opponentMatch == .proposed, "\(name)")
    }
    #expect(make(fixture("Real Meda B"), opponents(["Real Meda b"])).opponentMatch == .exact)
  }

  @Test func aLoneShortWordIsNeverContained() {
    // 4 and 5 letters: no proposal in either direction.
    #expect(rankOpponents(name: "MEDA", aliases: [], in: opponents(["Real Meda"])).isEmpty)
    #expect(rankOpponents(name: "FIAMMA MONZA", aliases: [], in: opponents(["Monza"])).isEmpty)
    #expect(make(fixture("WOMEN MEDA"), opponents(["Real Meda", "Meda Nova"])).opponentMatch == .notFound)
    // 7 letters: contained.
    #expect(
      rankOpponents(name: "ALCIONE", aliases: [], in: opponents(["Alcione Milano"])).map(\.kind) == [.containment])
    #expect(rankOpponents(name: "SAN ALCIONE", aliases: [], in: opponents(["Alcione"])).map(\.kind) == [.containment])
    // Two short words are enough.
    #expect(
      rankOpponents(name: "REAL MEDA", aliases: [], in: opponents(["Real Meda Nova"])).map(\.kind) == [.containment])
    // Equal word sets are .similar, whatever their length.
    #expect(rankOpponents(name: "MEDA CALCIO", aliases: [], in: opponents(["Meda"])).map(\.kind) == [.similar])
  }

  // MARK: Ranking

  @Test func rankingOrderAndKinds() {
    let stored = [
      Opponent(id: "1", name: "Alcione Milano"), Opponent(id: "2", name: "Alcione"),
      Opponent(id: "3", name: "Alcione Bergamo"), Opponent(id: "4", name: "Atalanta"),
      Opponent(id: "5", name: "Alcone"), Opponent(id: "6", name: "Alcion"),
    ]
    let ranked = rankOpponents(name: "ALCIONE", aliases: [], in: stored)
    // "Alcion" and "Alcone" are one edit from "alcione" (6+ letters): similar, score 1, by name.
    #expect(ranked.map(\.opponent.id) == ["2", "6", "5", "3", "1"])
    #expect(ranked.map(\.kind) == [.exact, .similar, .similar, .containment, .containment])
    #expect(ranked.first?.score == 1)
    #expect(abs((ranked.last?.score ?? 0) - 2.0 / 3.0) < 0.0001)
    #expect(rankOpponents(name: "", aliases: [" "], in: stored).isEmpty)
  }

  @Test func similarNeedsDiceOfPointEight() {
    let stored = [Opponent(id: "1", name: "Virtus Campo Verde Alta"), Opponent(id: "2", name: "Virtus Campo Rosso")]
    // 4 vs 4 tokens, 3 in common: 0.75 → no; 4 vs 5 with 4 in common is containment.
    #expect(rankOpponents(name: "Virtus Campo Verde Bassa", aliases: [], in: stored).isEmpty)
    let one = rankOpponents(name: "Virtus Campofelici", aliases: [], in: opponents(["Virtus Campofelice"]))
    #expect(one.map(\.kind) == [.similar] && one.first?.score == 1)
  }

  @Test func shortNamesAndAliasesOfOpponentsAreCompared() {
    let stored = [Opponent(id: "1", name: "Oratorio Esempio", shortName: "Esempio Rosa", aliases: ["Rosa Calcio"])]
    #expect(rankOpponents(name: "ROSA CALCIO", aliases: [], in: stored).first?.kind == .exact)
    #expect(rankOpponents(name: "ROSA", aliases: [], in: stored).first?.kind == .similar)
    #expect(rankOpponents(name: "ESEMPIO ROSA 2010", aliases: [], in: stored).first?.kind == .similar)
  }

  // MARK: Candidates

  @Test func proposalsAreCappedAndLinkingWins() {
    let stored = (1...7).map { Opponent(id: "o\($0)", name: "Esempio \($0)a") }
    let candidate = make(fixture("ESEMPIO"), stored)
    #expect(candidate.opponentMatch == .ambiguous && candidate.proposals.count == ImportCandidate.maxProposals)
    let linked = make(fixture("ESEMPIO"), stored, linked: "o3")
    #expect(linked.opponentMatch == .linked && linked.opponent?.id == "o3" && linked.state == .new)
    #expect(make(fixture("ESEMPIO"), stored, linked: "missing").opponentMatch == .notFound)
  }

  @Test func exactAmbiguityStaysAmbiguous() {
    let stored = [Opponent(id: "a", name: "Valdorso"), Opponent(id: "b", name: "F.C. Valdorso")]
    let candidate = make(fixture("Valdorso"), stored)
    #expect(candidate.opponentMatch == .ambiguous && candidate.reviewReasons == [.opponentAmbiguous])
    #expect(candidate.proposals.map(\.kind) == [.exact, .exact])
  }

  @Test func confirmedLinksSaveTheImportNamesSoTheNextImportIsExact() throws {
    let bernardo = Opponent(id: "o1", name: "San Bernardo")
    let fixture = fixture("S. BERNARDO CALCIO", aliases: ["SAN BERNARDO CALCIO"])
    let first = make(fixture, [bernardo])
    #expect(first.opponentMatch == .proposed)
    var saved = bernardo
    saved.aliases = bernardo.draftAddingImportNames(of: fixture).aliases
    #expect(saved.aliases == ["S. BERNARDO CALCIO", "SAN BERNARDO CALCIO"])
    #expect(make(fixture, [saved]).opponentMatch == .exact)
  }

  @Test func initDefaultsAndOlderJSON() throws {
    let candidate = make(fixture("ALCIONE"), opponents(["Alcione Milano"]))
    #expect(try JSONDecoder().decode(ImportCandidate.self, from: JSONEncoder().encode(candidate)) == candidate)
    var object = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(candidate)) as? [String: Any])
    object["opponentMatch"] = nil
    object["proposals"] = nil
    let old = try JSONDecoder().decode(ImportCandidate.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(old.opponentMatch == .exact && old.proposals.isEmpty)
    let plain = ImportCandidate(
      team: team, fixture: fixture("X"), opponent: nil, existing: nil, draft: nil, state: .needsReview,
      reviewReasons: [.opponentNotFound])
    #expect(plain.opponentMatch == .notFound)
  }

  // MARK: Fakes

  @MainActor @Test func fakeMatchingScenarioCoversEveryResult() throws {
    let data = try Fixtures.dataSet()
    let calendar = FakePDFCalendarParser.matchingScenarioCalendar(referenceSaturday: data.referenceSaturday)
    let rows = calendar.fixtures.map {
      ImportCandidate.make(
        fixture: $0, team: team, opponents: data.opponents, existingMatches: [], homeVenue: "Campo", source: .pdf)
    }
    #expect(rows.map(\.opponentMatch) == [.exact, .proposed, .ambiguous, .notFound])
    #expect(rows[0].opponent?.name == "Pol. Borgo Lucente")
    #expect(rows[1].opponent?.name == "Virtus Campofelice")
    #expect(
      Set(rows[2].proposals.map(\.opponent.name)) == [
        "A.S.D. Oratorio San Gerolamo", "A.C. Oratorio Sant'Eufrasio di Valfonda Bassa", "Oratorio Santa Lucia",
      ])
    let parsed = try FakePDFCalendarParser.matchingScenario(referenceSaturday: data.referenceSaturday)
      .parse(pdf: Data(), settings: data.settings)
    #expect(parsed == calendar)
  }
}
