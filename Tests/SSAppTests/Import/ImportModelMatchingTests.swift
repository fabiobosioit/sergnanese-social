import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

/// T4.10b: the review of opponents that are exact, proposed, ambiguous or not found, against
/// `FakePDFCalendarParser.matchingScenario`.
@MainActor
struct ImportModelMatchingTests {
  static let today = try! DayDate("2026-11-18")  // Wednesday; the fake data's reference Saturday is 21 November

  struct Env {
    var services: AppServices
    var team: Team
    var calendar: PDFCalendar
  }

  func makeEnv() throws -> Env {
    var services = AppServices.fake(today: Self.today)
    let parser = FakePDFCalendarParser.matchingScenario(referenceSaturday: try DayDate("2026-11-21"))
    services.pdfCalendarParser = parser
    let team = try #require(try services.teams.list().first { $0.name == "Femminile" })
    let calendar = try parser.parse(pdf: Data(), settings: try services.settings.load())
    return Env(services: services, team: team, calendar: calendar)
  }

  func makeModel(_ env: Env) -> ImportModel {
    let model = ImportModel(
      services: env.services, source: .pdf(team: env.team, calendar: env.calendar, fileName: "calendario.pdf"),
      today: { Self.today })
    model.stagePDF()
    return model
  }

  func row(_ model: ImportModel, _ name: String) throws -> ImportCandidate {
    try #require(model.candidates.first { $0.fixture.opponentName == name })
  }

  func opponent(_ env: Env, _ name: String) throws -> Opponent {
    try #require(try env.services.opponents.list().first { $0.name == name })
  }

  @Test func scenarioShowsOneOfEachAndTheHeaderCounts() throws {
    let model = makeModel(try makeEnv())
    #expect(try row(model, "BORGO LUCENTE S.R.L.").opponentMatch == .exact)
    let proposed = try row(model, "VIRTUS CAMPOFELICI")
    #expect(proposed.opponentMatch == .proposed)
    #expect(proposed.opponent?.name == "Virtus Campofelice")
    let ambiguous = try row(model, "ORATORIO CALCIO")
    #expect(ambiguous.opponentMatch == .ambiguous)
    #expect(ambiguous.opponent == nil)
    #expect(ambiguous.draft == nil)
    #expect(ambiguous.proposals.count == 3)
    #expect(try row(model, "NUOVA ESEMPIO").opponentMatch == .notFound)
    #expect(model.matchCounts == ImportModel.MatchCounts(matched: 1, proposed: 1, toLink: 2))
    #expect(model.matchCountsText == "1 abbinati, 1 proposti, 2 da collegare")
  }

  @Test func confirmingLinksTheProposalWithoutChangingDraftOrTick() throws {
    let env = try makeEnv()
    let model = makeModel(env)
    let before = try row(model, "VIRTUS CAMPOFELICI")
    #expect(model.isTicked(before))
    model.confirm(before)
    let after = try row(model, "VIRTUS CAMPOFELICI")
    #expect(after.opponentMatch == .linked)
    #expect(after.opponent == before.opponent)
    #expect(after.draft == before.draft)
    #expect(after.state == before.state)
    #expect(model.isTicked(after))
    #expect(model.matchCounts == ImportModel.MatchCounts(matched: 2, proposed: 0, toLink: 2))
  }

  @Test func confirmingKeepsAnUntickedRowUnticked() throws {
    let model = makeModel(try makeEnv())
    let before = try row(model, "VIRTUS CAMPOFELICI")
    model.setTicked(before, false)
    model.confirm(before)
    #expect(!model.isTicked(try row(model, "VIRTUS CAMPOFELICI")))
  }

  @Test func confirmingOtherRowsDoesNothing() throws {
    let model = makeModel(try makeEnv())
    let exact = try row(model, "BORGO LUCENTE S.R.L.")
    model.confirm(exact)
    #expect(try row(model, "BORGO LUCENTE S.R.L.").opponentMatch == .exact)
  }

  @Test func changeOpponentOfAnExactRowRebuildsItAndWritesNothing() throws {
    let env = try makeEnv()
    let model = makeModel(env)
    let other = try opponent(env, "Virtus Campofelice")
    let exact = try row(model, "BORGO LUCENTE S.R.L.")
    #expect(model.canChangeOpponent(exact))
    let before = try env.services.opponents.list()
    model.choose(other, for: exact)
    let changed = try row(model, "BORGO LUCENTE S.R.L.")
    #expect(changed.opponentMatch == .linked)
    #expect(changed.opponent?.id == other.id)
    #expect(changed.draft?.opponentID == other.id)
    #expect(try env.services.opponents.list() == before)
  }

  @Test func everyRowWithAnOpponentCanBeChanged() throws {
    let model = makeModel(try makeEnv())
    #expect(model.canChangeOpponent(try row(model, "BORGO LUCENTE S.R.L.")))
    #expect(model.canChangeOpponent(try row(model, "VIRTUS CAMPOFELICI")))
    #expect(!model.canChangeOpponent(try row(model, "ORATORIO CALCIO")))
    #expect(!model.canChangeOpponent(try row(model, "NUOVA ESEMPIO")))
  }

  @Test func pickerListsProposalsThenEveryOtherOpponentAlphabetically() throws {
    let env = try makeEnv()
    let model = makeModel(env)
    let ambiguous = try row(model, "ORATORIO CALCIO")
    let content = model.pickerContent(for: ambiguous, matching: "")
    #expect(content.proposed.map(\.id) == ambiguous.proposals.map(\.opponent.id))
    #expect(content.proposed.allSatisfy { $0.name.localizedCaseInsensitiveContains("Oratorio") })
    let all = try env.services.opponents.list()
    #expect(content.proposed.count + content.others.count == all.count)
    #expect(Set(content.others.map(\.id)).isDisjoint(with: content.proposed.map(\.id)))
    let names = content.others.map(\.name)
    #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
  }

  @Test func pickerWithASearchIsOneFlatList() throws {
    let model = makeModel(try makeEnv())
    let content = model.pickerContent(for: try row(model, "ORATORIO CALCIO"), matching: "borgo")
    #expect(content.proposed.isEmpty)
    #expect(content.others.map(\.name) == ["Pol. Borgo Lucente"])
  }

  @Test func pickerOfARowWithoutProposalsHasNoProposedSection() throws {
    let model = makeModel(try makeEnv())
    let content = model.pickerContent(for: try row(model, "NUOVA ESEMPIO"), matching: "")
    #expect(content.proposed.isEmpty)
    #expect(!content.others.isEmpty)
  }

  @Test func choosingForAnAmbiguousRowLinksItAndSavesTheAlias() throws {
    let env = try makeEnv()
    let model = makeModel(env)
    let ambiguous = try row(model, "ORATORIO CALCIO")
    let pick = try #require(ambiguous.proposals.first).opponent
    model.choose(pick, for: ambiguous)
    let linked = try row(model, "ORATORIO CALCIO")
    #expect(linked.opponentMatch == .linked)
    #expect(linked.state == .new)
    #expect(model.isTicked(linked))
    #expect(try env.services.opponents.get(id: pick.id).aliases.contains("ORATORIO CALCIO"))
  }

  @Test func importSavesTheNamesOfAProposedRowAndTheNextStagingIsExact() async throws {
    let env = try makeEnv()
    let model = makeModel(env)
    let virtus = try opponent(env, "Virtus Campofelice")
    let borgo = try opponent(env, "Pol. Borgo Lucente")
    let before = try env.services.opponents.list()
    // Nothing is written by reviewing.
    model.confirm(try row(model, "VIRTUS CAMPOFELICI"))
    #expect(try env.services.opponents.list() == before)

    await model.commit()
    #expect(model.phase == .done)
    let afterVirtus = try env.services.opponents.get(id: virtus.id)
    #expect(afterVirtus.name == virtus.name)
    #expect(afterVirtus.aliases.contains("VIRTUS CAMPOFELICI"))
    // An exact row whose spelling is new to the opponent adds it too; the name stays.
    let afterBorgo = try env.services.opponents.get(id: borgo.id)
    #expect(afterBorgo.name == borgo.name)
    #expect(try env.services.opponents.list().count == before.count)

    let again = makeModel(env)
    #expect(try row(again, "VIRTUS CAMPOFELICI").opponentMatch == .exact)
    #expect(try row(again, "BORGO LUCENTE S.R.L.").opponentMatch == .exact)
  }

  @Test func importWithoutConfirmingAcceptsTheProposal() async throws {
    let env = try makeEnv()
    let model = makeModel(env)
    await model.commit()
    let virtus = try opponent(env, "Virtus Campofelice")
    #expect(virtus.aliases.contains("VIRTUS CAMPOFELICI"))
    let stored = try env.services.matches.list(
      from: try DayDate("2026-11-01"), to: try DayDate("2027-01-31"), teamID: env.team.id)
    #expect(stored.contains { $0.match.opponentID == virtus.id && $0.match.source == .pdf })
  }

  @Test func anUntickedRowSavesNoAlias() async throws {
    let env = try makeEnv()
    let model = makeModel(env)
    model.setTicked(try row(model, "VIRTUS CAMPOFELICI"), false)
    await model.commit()
    #expect(try !opponent(env, "Virtus Campofelice").aliases.contains("VIRTUS CAMPOFELICI"))
  }
}
