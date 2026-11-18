import Testing

@testable import SSApp

@MainActor
struct CommandAvailabilityTests {
  @Test func unpublishedCommandsAreDisabled() {
    let published = PublishedCommands()
    for command in ShellCommand.allCases { #expect(!published.isEnabled(command)) }
  }

  @Test func publishedCommandFollowsItsEnabledFlag() {
    let published = PublishedCommands([
      .newMatch: CommandAction {}, .delete: CommandAction(isEnabled: false) {},
    ])
    #expect(published.isEnabled(.newMatch))
    #expect(!published.isEnabled(.delete))
    #expect(!published.isEnabled(.share))
  }

  @Test func performRunsOnlyEnabledActions() {
    var ran: [ShellCommand] = []
    let published = PublishedCommands([
      .newMatch: CommandAction { ran.append(.newMatch) },
      .delete: CommandAction(isEnabled: false) { ran.append(.delete) },
    ])
    published.perform(.newMatch)
    published.perform(.delete)
    published.perform(.find)
    #expect(ran == [.newMatch])
  }

  @Test func weekendCommandsApplyOnlyToWeekendSections() {
    for section in AppSection.weekendSections {
      let thisWeekend = WeekendCommandAvailability(section: section, isThisWeekend: true)
      #expect(thisWeekend.previous && thisWeekend.next && !thisWeekend.thisWeekend)
      #expect(WeekendCommandAvailability(section: section, isThisWeekend: false).thisWeekend)
    }
    for section in AppSection.librarySections {
      let availability = WeekendCommandAvailability(section: section, isThisWeekend: false)
      #expect(!availability.previous && !availability.next && !availability.thisWeekend)
    }
  }
}
