import Foundation
import Testing

@testable import SSCore

@Suite struct ValidationTests {
  @Test func teamDraft() {
    #expect(TeamDraft(name: "Juniores", shortLabel: "Jun").validate().isEmpty)
    let problems = TeamDraft(name: "  ", shortLabel: String(repeating: "x", count: 31)).normalized().validate()
    #expect(problems.map(\.field) == [.name, .shortLabel])
    #expect(problems.message(for: .name) == "Campo obbligatorio.")
  }

  @Test func opponentDraftNormalises() {
    let draft = OpponentDraft(
      name: "  F.C.   Valdorso ", shortName: "   ", aliases: ["Valdorso FC", " valdorso fc", "", "F.C. Valdorso"],
      logoFile: " ")
    let normalized = draft.normalized()
    #expect(normalized.name == "F.C. Valdorso")
    #expect(normalized.shortName == nil)
    #expect(normalized.logoFile == nil)
    #expect(normalized.aliases == ["Valdorso FC"])
    #expect(normalized.validate().isEmpty)
  }

  @Test func opponentDraftProblems() {
    let draft = OpponentDraft(name: "", shortName: String(repeating: "a", count: 31))
    #expect(draft.validate().map(\.field) == [.name, .shortName])
  }

  @Test func matchDraft() throws {
    let date = try DayDate("2026-11-22")
    var draft = MatchDraft(teamID: "t", opponentID: "o", date: date, venue: "  Campo   Comunale ", notes: "  ")
    draft = draft.normalized()
    #expect(draft.venue == "Campo Comunale")
    #expect(draft.notes == nil)
    #expect(draft.validate().isEmpty)

    var bad = MatchDraft(teamID: "", opponentID: "", date: date)
    bad.round = 0
    bad.score = Score(us: -1, them: 2)
    bad.halfTime = Score(us: 100, them: 0)
    bad.venue = String(repeating: "v", count: 61)
    #expect(bad.validate().map(\.field) == [.team, .opponent, .venue, .round, .score, .halfTime])
  }

  @Test func validatedThrowsFirstProblem() {
    #expect(throws: AppError.validation(field: .name, message: "Campo obbligatorio.")) {
      try TeamDraft(name: "", shortLabel: "").validated()
    }
    #expect(throws: Never.self) { try TeamDraft(name: " A ", shortLabel: "B").validated() }
  }

  @Test func settings() {
    #expect(ClubSettings.defaults.validate().isEmpty)
    var settings = ClubSettings.defaults
    settings.accentColor = "cf3326"
    settings.outputFolder = "  "
    let normalized = settings.normalized()
    #expect(normalized.accentColor == "#CF3326")
    #expect(normalized.outputFolder == nil)

    var bad = ClubSettings.defaults
    bad.clubName = ""
    bad.season = "2026/28"
    bad.accentColor = "red"
    bad.socialHandle = "@a b"
    bad.outputFolder = "relative/path"
    #expect(bad.validate().map(\.field) == [.clubName, .season, .accentColor, .socialHandle, .outputFolder])
  }

  @Test(arguments: [
    ("#CF3326", "#CF3326"), ("cf3326", "#CF3326"), (" #a1b2c3 ", "#A1B2C3"),
  ])
  func hexColors(_ input: String, _ expected: String) {
    #expect(normalizedHexColor(input) == expected)
  }

  @Test(arguments: ["", "#CF332", "#CF33266", "#GGGGGG", "red", "#C33"])
  func invalidHexColors(_ input: String) {
    #expect(normalizedHexColor(input) == nil)
  }

  @Test func seasons() {
    #expect(isValidSeason("2026/27"))
    #expect(isValidSeason("2099/00"))
    #expect(!isValidSeason("2026/28"))
    #expect(!isValidSeason("26/27"))
    #expect(!isValidSeason("2026-27"))
  }

  @Test func errorsHaveItalianDescriptions() {
    #expect(AppError.notFound.localizedDescription == "Elemento non trovato.")
    #expect(AppError.conflict(message: "No.").localizedDescription == "No.")
    #expect(AppError.template(problems: ["a", "b"]).localizedDescription == "Il template non è valido:\na\nb")
  }
}

@Suite struct WarningTests {
  func detail(time: String?, venue: String, logo: String?, name: String, shortName: String? = nil) throws -> MatchDetail
  {
    MatchDetail(
      match: Match(
        id: "m", teamID: "t", opponentID: "o", date: try DayDate("2026-11-22"),
        time: try time.map { try ClockTime($0) },
        isHome: true, venue: venue, createdAt: Date(), updatedAt: Date()),
      team: Team(id: "t", name: "T", shortLabel: "T", sortOrder: 0, isFirstTeam: true, isActive: true),
      opponent: Opponent(id: "o", name: name, shortName: shortName, logoFile: logo))
  }

  @Test func cleanMatchHasNoWarnings() throws {
    let clean = try detail(time: "15:00", venue: "Campo", logo: "x.png", name: "F.C. Valdorso")
    #expect(matchWarnings(for: clean, teamNameLimit: 16).isEmpty)
  }

  @Test func everyWarningInOrder() throws {
    let messy = try detail(time: nil, venue: " ", logo: nil, name: "A.C. Oratorio Sant'Eufrasio di Valfonda Bassa")
    let warnings = matchWarnings(for: messy, teamNameLimit: 16)
    #expect(warnings.map(\.kind) == [.missingTime, .missingVenue, .missingLogo, .nameTruncated])
    #expect(warnings.allSatisfy { $0.matchID == "m" })
    #expect(warnings.last?.opponentID == "o")
    #expect(warnings.last?.message.contains("Oratorio…") == true)
    #expect(matchWarnings(for: messy, teamNameLimit: nil).count == 3)
  }

  @Test func shortNameAvoidsTheCut() throws {
    let fixed = try detail(
      time: "15:00", venue: "Campo", logo: "x.png", name: "A.C. Oratorio Sant'Eufrasio di Valfonda Bassa",
      shortName: "Sant'Eufrasio")
    #expect(matchWarnings(for: fixed, teamNameLimit: 16).isEmpty)
  }
}
