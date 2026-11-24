import Foundation
import SSCore

/// The context of one image and the warnings collected while building it.
public enum TemplateContext: Sendable, Equatable {
  case single(SingleContext)
  case list(ListContext)
}

/// Builds the data a template receives (`01-architecture.md` §5) from matches, the club settings and
/// the template's manifest. Every value is computed here and cut to the manifest's `limits`, because
/// Mustache has no helpers.
public struct ContextBuilder: Sendable {
  public var settings: ClubSettings
  public var manifest: TemplateManifest
  /// When set, an opponent logo is used only if its file exists in this folder; a missing file is
  /// treated like no logo (initials and a warning). `nil` trusts `Opponent.logoFile`.
  public var logosFolder: URL?

  public init(settings: ClubSettings, manifest: TemplateManifest, logosFolder: URL? = nil) {
    self.settings = settings
    self.manifest = manifest
    self.logosFolder = logosFolder
  }

  /// One page of a list template.
  public struct Page: Sendable, Equatable {
    public var context: ListContext
    /// The matches on the page, in schedule order.
    public var matches: [MatchDetail]
    public var warnings: [RenderWarning]
  }

  public var club: ClubContext {
    ClubContext(
      name: settings.clubName, shortName: settings.clubShortName, logo: TemplateURLs.clubLogo,
      accent: normalizedHexColor(settings.accentColor) ?? ClubSettings.defaultAccentColor, season: settings.season,
      handle: settings.socialHandle)
  }

  /// The context of a `single` template for one match.
  public func single(_ detail: MatchDetail) -> (context: SingleContext, warnings: [RenderWarning]) {
    let (match, warnings) = matchContext(detail, listRow: false)
    return (SingleContext(club: club, match: match), warnings)
  }

  /// The pages of a `list` template: matches sorted by `MatchDetail.scheduleOrder` and sliced to the
  /// manifest's `pageSize`. The title and date label describe all the given matches (one day: "Oggi in
  /// campo" and the long date; several days: "Weekend in campo" and the range). A results recap
  /// (`manifest.isResultsRecap`) is titled "Risultati del weekend" for one Saturday + Sunday, else
  /// "Risultati". Empty input → no pages.
  public func pages(_ details: [MatchDetail]) -> [Page] {
    let sorted = details.sorted(by: MatchDetail.scheduleOrder)
    guard let first = sorted.first?.match.date, let last = sorted.last?.match.date else { return [] }
    let title: String
    if manifest.isResultsRecap {
      let oneWeekend = first.isoWeekday == 6 && last == first.adding(days: 1)
      title = oneWeekend ? RenderStrings.recapTitleWeekend : RenderStrings.recapTitle
    } else {
      title = first == last ? RenderStrings.titleOneDay : RenderStrings.titleManyDays
    }
    let dateLabel = first == last ? formatDateLong(first) : Self.rangeLabel(from: first, to: last)
    let pageSize = max(manifest.pageSize ?? 10, 1)
    let chunks = stride(from: 0, to: sorted.count, by: pageSize).map {
      Array(sorted[$0..<min($0 + pageSize, sorted.count)])
    }
    return chunks.enumerated().map { offset, chunk in
      let built = chunk.map { matchContext($0, listRow: true) }
      let context = ListContext(
        club: club, title: title, dateLabel: dateLabel, rows: built.map(\.0),
        page: PageInfo(index: offset + 1, total: chunks.count))
      return Page(context: context, matches: chunk, warnings: built.flatMap(\.1))
    }
  }

  /// `"Dal 14 al 29 novembre"`, `"Dal 31 ottobre al 1 novembre"`, `"Dal 28 dicembre 2026 al 3 gennaio 2027"`.
  static func rangeLabel(from first: DayDate, to last: DayDate) -> String {
    let months = [
      "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre",
      "novembre", "dicembre",
    ]
    let lastText = "\(last.day) \(months[last.month - 1])"
    if first.year != last.year {
      return "Dal \(first.day) \(months[first.month - 1]) \(first.year) al \(lastText) \(last.year)"
    }
    if first.month != last.month { return "Dal \(first.day) \(months[first.month - 1]) al \(lastText)" }
    return "Dal \(first.day) al \(lastText)"
  }

  // MARK: Match

  func matchContext(_ detail: MatchDetail, listRow: Bool) -> (MatchContext, [RenderWarning]) {
    let match = detail.match
    let team = detail.team
    let opponent = detail.opponent
    let limits = manifest.limits
    var warnings = matchWarnings(for: detail, teamNameLimit: limits.teamName)

    let categorySource = listRow && !team.shortLabel.isEmpty ? team.shortLabel : team.name
    let category = cut(categorySource, limit: limits.category, matchID: match.id, warnings: &warnings)
    let venue = cut(match.venue, limit: limits.venue, matchID: match.id, warnings: &warnings)

    let ourName = cut(settings.clubShortName, limit: limits.teamName, matchID: match.id, warnings: &warnings)
    let us = SideContext(
      name: settings.clubName, displayName: ourName, logo: TemplateURLs.clubLogo,
      initials: initials(settings.clubShortName), isUs: true, score: match.score?.us,
      halfTimeScore: match.halfTime?.us)

    var opponentLogo = opponent.logoFile.map(TemplateURLs.logo(fileName:))
    if let file = opponent.logoFile, let logosFolder, !Self.logoExists(file, in: logosFolder) {
      opponentLogo = nil
      warnings.append(
        RenderWarning(
          kind: .missingLogo, message: RenderStrings.logoFileMissing(opponent.name), matchID: match.id,
          opponentID: opponent.id))
    }
    let them = SideContext(
      name: opponent.name, displayName: displayName(for: opponent, limit: limits.teamName).text, logo: opponentLogo,
      initials: initials(opponent.name), isUs: false, score: match.score?.them, halfTimeScore: match.halfTime?.them)

    let notPlayed = match.status == .postponed || match.status == .cancelled
    // In a results recap a postponed or cancelled row is shown as such ("Rinviata"), not warned about.
    let quiet = manifest.isResultsRecap && notPlayed
    if !quiet { warnings += requiredFieldWarnings(match) }
    switch match.status {
    case _ where quiet:
      break
    case .postponed:
      warnings.append(RenderWarning(kind: .matchNotScheduled, message: RenderStrings.matchPostponed, matchID: match.id))
    case .cancelled:
      warnings.append(RenderWarning(kind: .matchNotScheduled, message: RenderStrings.matchCancelled, matchID: match.id))
    case .scheduled, .played:
      break
    }

    let context = MatchContext(
      category: category, round: match.round, competition: Self.nonEmpty(match.competition),
      dateLong: formatDateLong(match.date), dateShort: formatDateShort(match.date), time: match.time?.value,
      venue: venue, isHome: match.isHome, home: match.isHome ? us : them, away: match.isHome ? them : us, us: us,
      opponent: them, halfTime: match.halfTime, notes: Self.nonEmpty(match.notes),
      isPostponed: match.status == .postponed, isCancelled: match.status == .cancelled)
    return (context, warnings)
  }

  private func requiredFieldWarnings(_ match: Match) -> [RenderWarning] {
    manifest.requires.compactMap { field -> RenderWarning? in
      let message: String?
      switch field {
      case .time, .venue: message = nil  // already in `matchWarnings`
      case .round: message = match.round == nil ? RenderStrings.missingRound : nil
      case .competition: message = Self.nonEmpty(match.competition) == nil ? RenderStrings.missingCompetition : nil
      case .score: message = match.score == nil ? RenderStrings.missingScore : nil
      case .halfTime: message = match.halfTime == nil ? RenderStrings.missingHalfTime : nil
      case .notes: message = Self.nonEmpty(match.notes) == nil ? RenderStrings.missingNotes : nil
      }
      guard let message else { return nil }
      return RenderWarning(kind: .missingRequiredField, message: message, matchID: match.id, templateID: manifest.id)
    }
  }

  private func cut(_ text: String, limit: Int?, matchID: EntityID, warnings: inout [RenderWarning]) -> String {
    guard let limit else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
    let result = truncateAtWord(text, max: limit)
    if result.wasCut {
      warnings.append(
        RenderWarning(
          kind: .textTruncated, message: RenderStrings.textCut(text, result.text), matchID: matchID,
          templateID: manifest.id))
    }
    return result.text
  }

  static func nonEmpty(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
  }

  static func logoExists(_ fileName: String, in folder: URL) -> Bool {
    guard !fileName.contains("/"), !fileName.hasPrefix(".") else { return false }
    let values = try? folder.appendingPathComponent(fileName).resourceValues(forKeys: [.isRegularFileKey])
    return values?.isRegularFile == true
  }
}
