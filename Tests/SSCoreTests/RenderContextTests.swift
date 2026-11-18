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
