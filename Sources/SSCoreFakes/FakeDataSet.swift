import Foundation
import SSCore

/// The data behind the fakes: the shape of `Resources/Fixtures/matches.json`.
public struct FakeDataSet: Sendable, Codable, Equatable {
  /// The Saturday the data set treats as "Questo weekend". `shifted(toWeekendOf:)` moves every date
  /// by whole weeks so this Saturday lands on the current weekend.
  public var referenceSaturday: DayDate
  public var settings: ClubSettings
  public var teams: [Team]
  public var opponents: [Opponent]
  public var matches: [Match]
  /// `file` is relative to the output folder in the JSON; `AppServices.fake()` makes it absolute.
  public var renders: [RenderRecord]
  /// Records whose PNG `AppServices.fake()` deliberately does not write ("file mancante").
  public var missingRenderFileIDs: [EntityID]

  public init(
    referenceSaturday: DayDate, settings: ClubSettings = .defaults, teams: [Team] = [], opponents: [Opponent] = [],
    matches: [Match] = [], renders: [RenderRecord] = [], missingRenderFileIDs: [EntityID] = []
  ) {
    self.referenceSaturday = referenceSaturday
    self.settings = settings
    self.teams = teams
    self.opponents = opponents
    self.matches = matches
    self.renders = renders
    self.missingRenderFileIDs = missingRenderFileIDs
  }

  /// No data at all, with default settings.
  public static func empty(today: DayDate = .today()) -> FakeDataSet {
    FakeDataSet(referenceSaturday: weekend(containing: today).saturday)
  }

  /// The same data with every match and render date moved by whole weeks, so that
  /// `referenceSaturday` becomes the Saturday of `weekend(containing: today)`. Weekdays are kept.
  public func shifted(toWeekendOf today: DayDate) -> FakeDataSet {
    let target = weekend(containing: today).saturday
    let offset = referenceSaturday.days(to: target)
    guard offset != 0 else { return self }
    var copy = self
    copy.referenceSaturday = target
    copy.matches = matches.map { match in
      var match = match
      match.date = match.date.adding(days: offset)
      return match
    }
    copy.renders = renders.map { record in
      var record = record
      record.date = record.date.adding(days: offset)
      record.createdAt = record.createdAt.addingTimeInterval(TimeInterval(offset) * 86_400)
      return record
    }
    return copy
  }
}
