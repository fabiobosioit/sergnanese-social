import Foundation

// The data a template receives (`01-architecture.md` §5). Every value is already computed and cut to
// the template's limits: Mustache has no helpers. Optional values that are `nil` are left out of the
// encoded JSON, so `{{#time}}…{{/time}}` and `{{^time}}…{{/time}}` sections work.
//
// The types are `Codable` so fixtures in `Resources/Fixtures/` decode into them.

/// Relative URLs a template uses in `<img src>`. The render engine serves the template folder at the
/// page root and the logos folder under `logosPrefix`.
public enum TemplateURLs {
  /// Prefix under which the logos folder is served to a template: `"_logos/<file name>"`.
  /// The leading underscore keeps it apart from anything inside a template folder.
  public static let logosPrefix = "_logos/"

  /// The club crest. Every template ships it at this path inside its own folder, and the context
  /// builder sets `ClubContext.logo` to it.
  public static let clubLogo = "assets/club-logo.png"

  /// The relative URL of a file in the logos folder.
  public static func logo(fileName: String) -> String { logosPrefix + fileName }
}

public struct ClubContext: Sendable, Codable, Equatable, Hashable {
  /// "ASD Sergnanese".
  public var name: String
  /// "Sergnanese".
  public var shortName: String
  /// Relative URL of the crest, normally `TemplateURLs.clubLogo`.
  public var logo: String
  /// `"#CF3326"`.
  public var accent: String
  /// "2026/27".
  public var season: String
  /// "@account", may be empty.
  public var handle: String

  public init(name: String, shortName: String, logo: String, accent: String, season: String, handle: String) {
    self.name = name
    self.shortName = shortName
    self.logo = logo
    self.accent = accent
    self.season = season
    self.handle = handle
  }
}

/// One side of a match (us or the opponent).
public struct SideContext: Sendable, Codable, Equatable, Hashable {
  /// Full name.
  public var name: String
  /// `displayName(for:limit:)` with the template's `limits.teamName`; for our side the club's short name.
  public var displayName: String
  /// Relative URL (`TemplateURLs.logo(fileName:)` or `TemplateURLs.clubLogo`); absent when there is no logo.
  public var logo: String?
  /// For the circle shown when there is no logo.
  public var initials: String
  public var isUs: Bool
  /// Final score of this side; absent when there is no score.
  public var score: Int?
  /// Half-time score of this side; absent when there is none. (Added to the plan's §5 shape so the
  /// half-time story can print scores in home/away order without template logic.)
  public var halfTimeScore: Int?

  public init(
    name: String, displayName: String, logo: String?, initials: String, isUs: Bool, score: Int? = nil,
    halfTimeScore: Int? = nil
  ) {
    self.name = name
    self.displayName = displayName
    self.logo = logo
    self.initials = initials
    self.isUs = isUs
    self.score = score
    self.halfTimeScore = halfTimeScore
  }
}

public struct MatchContext: Sendable, Codable, Equatable, Hashable {
  /// Our team, cut to `limits.category`: the team's `name` in single contexts, its `shortLabel` in
  /// list rows.
  public var category: String
  public var round: Int?
  public var competition: String?
  /// "Domenica 22 novembre" (`formatDateLong`).
  public var dateLong: String
  /// "Dom 22 nov" (`formatDateShort`).
  public var dateShort: String
  /// "15:30"; absent when the match has no time.
  public var time: String?
  /// Cut to `limits.venue`. May be empty.
  public var venue: String
  public var isHome: Bool
  public var isAway: Bool
  /// In fixture order.
  public var home: SideContext
  public var away: SideContext
  /// The same two sides, by role.
  public var us: SideContext
  public var opponent: SideContext
  /// From our point of view (`us` / `them`).
  public var halfTime: Score?
  public var notes: String?
  public var isPostponed: Bool
  public var isCancelled: Bool

  public init(
    category: String, round: Int?, competition: String?, dateLong: String, dateShort: String, time: String?,
    venue: String, isHome: Bool, home: SideContext, away: SideContext, us: SideContext, opponent: SideContext,
    halfTime: Score?, notes: String?, isPostponed: Bool, isCancelled: Bool
  ) {
    self.category = category
    self.round = round
    self.competition = competition
    self.dateLong = dateLong
    self.dateShort = dateShort
    self.time = time
    self.venue = venue
    self.isHome = isHome
    self.isAway = !isHome
    self.home = home
    self.away = away
    self.us = us
    self.opponent = opponent
    self.halfTime = halfTime
    self.notes = notes
    self.isPostponed = isPostponed
    self.isCancelled = isCancelled
  }
}

/// Context of a `single` template: one match.
public struct SingleContext: Sendable, Codable, Equatable, Hashable {
  public var club: ClubContext
  public var match: MatchContext

  public init(club: ClubContext, match: MatchContext) {
    self.club = club
    self.match = match
  }
}

/// Context of a `list` template: one page of matches.
public struct ListContext: Sendable, Codable, Equatable, Hashable {
  public var club: ClubContext
  /// "Oggi in campo" / "Weekend in campo".
  public var title: String
  /// One day ("Domenica 22 novembre") or a range.
  public var dateLabel: String
  /// Already sorted and sliced to the template's `pageSize`.
  public var rows: [MatchContext]
  public var page: PageInfo
  /// `page.total > 1`.
  public var hasPages: Bool
  /// "1/3".
  public var pageLabel: String

  public init(club: ClubContext, title: String, dateLabel: String, rows: [MatchContext], page: PageInfo) {
    self.club = club
    self.title = title
    self.dateLabel = dateLabel
    self.rows = rows
    self.page = page
    self.hasPages = page.total > 1
    self.pageLabel = page.label
  }
}
