import Foundation
import Testing

@testable import SSCore

@Suite struct RenderContextTests {
  func side(_ isUs: Bool, score: Int?, half: Int?) -> SideContext {
    SideContext(name: "N", displayName: "N", logo: nil, initials: "N", isUs: isUs, score: score, halfTimeScore: half)
  }

  func context(us: SideContext, them: SideContext) -> MatchContext {
    MatchContext(
      category: "Prima Squadra", round: nil, competition: nil, dateLong: "Domenica 22 novembre",
      dateShort: "Dom 22 nov", time: nil, venue: "", isHome: true, home: us, away: them, us: us, opponent: them,
      halfTime: nil, notes: nil, isPostponed: false, isCancelled: false)
  }

  @Test func goallessScoreIsStillAScore() throws {
    let match = context(us: side(true, score: 0, half: 0), them: side(false, score: 0, half: 0))
    #expect(match.hasScore && match.hasHalfTime && match.isHome && !match.isAway)
    let json = String(decoding: try JSONEncoder().encode(match), as: UTF8.self)
    #expect(json.contains("\"hasScore\":true"))
    #expect(json.contains("\"hasHalfTime\":true"))
  }

  @Test func missingScoresAreFlaggedAndOmitted() throws {
    let match = context(us: side(true, score: 1, half: nil), them: side(false, score: nil, half: nil))
    #expect(!match.hasScore && !match.hasHalfTime)
    let json = String(decoding: try JSONEncoder().encode(match), as: UTF8.self)
    #expect(json.contains("\"hasScore\":false"))
    #expect(!json.contains("\"time\""))  // nil optionals are absent, so {{^time}} works
  }

  // MARK: Outcome (T4.5)

  @Test func outcomeFromGoals() {
    #expect(MatchOutcome(us: 2, them: 1) == .win)
    #expect(MatchOutcome(us: 10, them: 0) == .win)
    #expect(MatchOutcome(us: 0, them: 0) == .draw)
    #expect(MatchOutcome(us: 3, them: 3) == .draw)
    #expect(MatchOutcome(us: 0, them: 1) == .loss)
    #expect(MatchOutcome(us: nil, them: 1) == nil)
    #expect(MatchOutcome(us: 1, them: nil) == nil)
    #expect(MatchOutcome(us: nil, them: nil) == nil)
    #expect(MatchOutcome.allCases.map(\.rawValue) == ["win", "draw", "loss"])
  }

  @Test func contextDerivesOutcomeFromFinalScoresOnly() throws {
    #expect(context(us: side(true, score: 2, half: 0), them: side(false, score: 1, half: 1)).outcome == .win)
    #expect(context(us: side(true, score: 0, half: nil), them: side(false, score: 0, half: nil)).outcome == .draw)
    #expect(context(us: side(true, score: 1, half: 1), them: side(false, score: 4, half: 0)).outcome == .loss)
    // Away: still our point of view, whatever the fixture order.
    let us = side(true, score: 3, half: nil)
    let them = side(false, score: 0, half: nil)
    let away = MatchContext(
      category: "Juniores", round: nil, competition: nil, dateLong: "Sabato 21 novembre", dateShort: "Sab 21 nov",
      time: nil, venue: "", isHome: false, home: them, away: us, us: us, opponent: them, halfTime: nil, notes: nil,
      isPostponed: false, isCancelled: false)
    #expect(away.outcome == .win)
    // A half-time score alone gives no outcome, and nil is absent from the JSON so {{#outcome}} hides.
    let halfOnly = context(us: side(true, score: nil, half: 1), them: side(false, score: nil, half: 0))
    #expect(halfOnly.outcome == nil)
    let json = String(decoding: try JSONEncoder().encode(halfOnly), as: UTF8.self)
    #expect(!json.contains("\"outcome\""))
    let scored = String(decoding: try JSONEncoder().encode(away), as: UTF8.self)
    #expect(scored.contains("\"outcome\":\"win\""))
  }

  @Test func jsonWithoutOutcomeStillDecodes() throws {
    let match = context(us: side(true, score: 2, half: nil), them: side(false, score: 1, half: nil))
    var object = try #require(
      try JSONSerialization.jsonObject(with: try JSONEncoder().encode(match)) as? [String: Any])
    object["outcome"] = nil
    let old = try JSONDecoder().decode(MatchContext.self, from: try JSONSerialization.data(withJSONObject: object))
    #expect(old.outcome == nil)
    #expect(old.us == match.us && old.hasScore)
  }

  @Test func listContextDerivesPaging() {
    let club = ClubContext(
      name: "A", shortName: "A", logo: TemplateURLs.clubLogo, accent: "#CF3326", season: "2026/27", handle: "")
    let list = ListContext(
      club: club, title: "Oggi in campo", dateLabel: "", rows: [], page: PageInfo(index: 2, total: 3))
    #expect(list.hasPages && list.pageLabel == "2/3")
    let single = ListContext(club: club, title: "", dateLabel: "", rows: [], page: PageInfo(index: 1, total: 1))
    #expect(!single.hasPages)
    #expect(TemplateURLs.logo(fileName: "x.png") == "_logos/x.png")
  }
}
