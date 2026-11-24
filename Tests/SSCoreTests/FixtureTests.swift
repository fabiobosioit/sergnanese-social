import Foundation
import SSCoreFakes
import Testing

@testable import SSCore

@Suite struct FixtureTests {
  @Test(arguments: Fixtures.singleNames)
  func singleContextsDecode(_ name: String) throws {
    let context = try Fixtures.singleContext(name)
    #expect(context.club.logo == TemplateURLs.clubLogo)
    #expect(context.match.isHome != context.match.isAway)
    let match = context.match
    #expect([match.home, match.away].contains(match.us) && [match.home, match.away].contains(match.opponent))
    #expect(match.us.isUs && !match.opponent.isUs)
    #expect(match.opponent.initials == initials(match.opponent.name))
    #expect(match.hasScore == (match.us.score != nil && match.opponent.score != nil))
    #expect(match.hasHalfTime == (match.us.halfTimeScore != nil && match.opponent.halfTimeScore != nil))
  }

  @Test(arguments: Fixtures.listNames)
  func listContextsDecode(_ name: String) throws {
    let context = try Fixtures.listContext(name)
    #expect(context.hasPages == (context.page.total > 1))
    #expect(context.pageLabel == context.page.label)
    #expect(!context.rows.isEmpty)
  }

  @Test func listSizes() throws {
    #expect(try Fixtures.listContext("list").rows.count == 10)
    #expect(try Fixtures.listContext("list-23").rows.count == 23)
    #expect(try Fixtures.listContext("list-results").rows.count == 10)
  }

  /// T4.5: every context with a final score carries the outcome that agrees with it; none without.
  @Test func outcomesAgreeWithScores() throws {
    let singles = try Fixtures.singleNames.map { try Fixtures.singleContext($0).match }
    let rows = try Fixtures.listNames.flatMap { try Fixtures.listContext($0).rows }
    for match in singles + rows {
      #expect(match.outcome == MatchOutcome(us: match.us.score, them: match.opponent.score), "\(match.category)")
    }
    #expect(singles.contains { $0.outcome != nil })
  }

  @Test func resultsRecapFixtureCoversTheEdgeCases() throws {
    let recap = try Fixtures.listContext("list-results")
    #expect(recap.title == "Risultati del weekend" && recap.dateLabel == "Dal 14 al 15 novembre")
    #expect(recap.page == PageInfo(index: 1, total: 1) && !recap.hasPages)
    let rows = recap.rows
    #expect(Set(rows.map(\.dateShort)) == ["Sab 14 nov", "Dom 15 nov"])
    #expect(rows.contains { $0.isHome && $0.outcome == .win })
    #expect(rows.contains { $0.isAway && $0.outcome == .win })
    #expect(rows.contains { $0.outcome == .loss })
    #expect(rows.contains { $0.us.score == 0 && $0.opponent.score == 0 && $0.outcome == .draw })
    #expect(rows.contains { $0.us.score == 3 && $0.opponent.score == 3 })
    #expect(rows.contains { $0.us.score == 10 && $0.opponent.score == 0 })
    let long = try #require(rows.first { $0.opponent.name.count == 45 })
    #expect(long.opponent.displayName == truncateAtWord(stripLegalPrefixes(long.opponent.name), max: 22).text)
    #expect(rows.contains { $0.opponent.logo == nil })
    let postponed = rows.filter(\.isPostponed)
    #expect(postponed.count == 1 && postponed.allSatisfy { !$0.hasScore && $0.outcome == nil })
    #expect(rows.filter { !$0.isPostponed }.allSatisfy { $0.hasScore && $0.outcome != nil })
    #expect(rows.allSatisfy { $0.category.count <= 16 })
  }

  @Test func requiredEdgeCasesArePresent() throws {
    let long = try Fixtures.singleContext("single-long-name").match.opponent
    #expect(long.name.count == 45)
    #expect(long.displayName == truncateAtWord(stripLegalPrefixes(long.name), max: 16).text)
    #expect(try Fixtures.singleContext("single-no-logo").match.opponent.logo == nil)
    #expect(try Fixtures.singleContext("single-away").match.isAway)
    #expect(try Fixtures.singleContext("single-no-time").match.time == nil)
    let goalless = try Fixtures.singleContext("single-goalless").match
    #expect(goalless.hasScore && goalless.hasHalfTime)
    #expect(goalless.home.score == 0 && goalless.away.score == 0)
    #expect(goalless.home.halfTimeScore == 0 && goalless.away.halfTimeScore == 0)
    #expect(try !Fixtures.singleContext("single-no-time").match.hasScore)
    let standard = try Fixtures.singleContext().match
    #expect(standard.isHome && standard.time != nil && standard.opponent.logo != nil && standard.round != nil)
    #expect(standard.us.score != nil && standard.us.halfTimeScore != nil && standard.halfTime != nil)
  }

  @Test func datesAreFormattedBySSCoreRules() throws {
    let data = try Fixtures.dataSet()
    let contexts = try Fixtures.singleNames.map { try Fixtures.singleContext($0).match }
    for context in contexts {
      let match = try #require(data.matches.first { formatDateLong($0.date) == context.dateLong })
      #expect(formatDateShort(match.date) == context.dateShort)
    }
  }

  @Test func logosReferencedByFixturesExist() throws {
    let logos = try Fixtures.logosFolder()
    let data = try Fixtures.dataSet()
    for file in data.opponents.compactMap(\.logoFile) {
      #expect(FileManager.default.fileExists(atPath: logos.appendingPathComponent(file).path), "\(file)")
    }
    let contexts = try Fixtures.singleNames.map { try Fixtures.singleContext($0).match }
    for logo in contexts.compactMap(\.opponent.logo) {
      #expect(logo.hasPrefix(TemplateURLs.logosPrefix))
      let file = String(logo.dropFirst(TemplateURLs.logosPrefix.count))
      #expect(FileManager.default.fileExists(atPath: logos.appendingPathComponent(file).path), "\(file)")
    }
  }

  @Test func dataSetIsConsistent() throws {
    let data = try Fixtures.dataSet()
    let teamIDs = Set(data.teams.map(\.id))
    let opponentIDs = Set(data.opponents.map(\.id))
    #expect(data.referenceSaturday.isoWeekday == 6)
    #expect(data.teams.filter(\.isFirstTeam).count == 1)
    #expect(data.matches.allSatisfy { teamIDs.contains($0.teamID) && opponentIDs.contains($0.opponentID) })
    #expect(Set(data.matches.map(\.id)).count == data.matches.count)
    #expect(data.settings.validate().isEmpty)
    for team in data.teams { #expect(TeamDraft(team).validate().isEmpty) }
    for opponent in data.opponents { #expect(OpponentDraft(opponent).validate().isEmpty) }
    for match in data.matches { #expect(MatchDraft(match).validate().isEmpty) }

    // Edge cases the UI tasks rely on.
    #expect(data.opponents.contains { $0.name.count == 45 })
    #expect(data.opponents.contains { $0.logoFile == nil })
    #expect(data.opponents.contains { $0.shortName != nil })
    let thisWeekend = Weekend(saturday: data.referenceSaturday)
    let current = data.matches.filter { thisWeekend.contains($0.date) }
    #expect(current.contains { !$0.isHome })
    #expect(current.contains { $0.time == nil })
    #expect(current.contains { $0.status == .postponed })
    #expect(current.contains { $0.isLocked })
    let previous = data.matches.filter { thisWeekend.previous.contains($0.date) }
    #expect(!previous.isEmpty && previous.allSatisfy { $0.status == .played && $0.score != nil })
    let nextSunday = data.matches.filter { $0.date == thisWeekend.next.sunday }
    #expect(nextSunday.count > 10, "two programme pages on one day")
    #expect(Set(data.missingRenderFileIDs).isSubset(of: Set(data.renders.map(\.id))))
  }

  @Test func shiftingMovesByWholeWeeks() throws {
    let data = try Fixtures.dataSet()
    let today = try DayDate("2027-03-10")  // a Wednesday
    let shifted = data.shifted(toWeekendOf: today)
    #expect(shifted.referenceSaturday == weekend(containing: today).saturday)
    for (old, new) in zip(data.matches, shifted.matches) {
      #expect(new.date.isoWeekday == old.date.isoWeekday)
      #expect(old.date.days(to: new.date) == data.referenceSaturday.days(to: shifted.referenceSaturday))
    }
    #expect(data.shifted(toWeekendOf: data.referenceSaturday) == data)
  }
}
