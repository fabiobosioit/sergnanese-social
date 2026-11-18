import Foundation
import SSCore

/// One image of a plan with what is needed to render it.
struct PlanItem: Sendable {
  var image: PlannedImage
  var template: InstalledTemplate
  var context: TemplateContext
}

/// Turns a `RenderRequest` into images, contexts and warnings, without rendering.
///
/// Default plan (no selections): every `list` template with purpose `.programme` takes every match
/// in the range, and every `single` template with purpose `.prematch` takes the first team's matches;
/// postponed and cancelled matches are left out and reported as skipped. A `list` template makes one
/// set of pages per day; a `single` template one image per match.
struct RenderPlanner: Sendable {
  var templates: any TemplateStore
  var matches: any MatchRepository
  var settings: ClubSettings
  /// Logos folder used to check that opponent logo files exist.
  var logosFolder: URL?

  func plan(_ request: RenderRequest) throws -> (plan: RenderPlan, items: [PlanItem]) {
    var skipped: [EntityID] = []
    let selections: [TemplateSelection]
    if let explicit = request.selections {
      selections = explicit
    } else {
      let inRange = try matches.list(from: request.from, to: request.to, teamID: nil)
      skipped = inRange.filter { Self.isExcludedByDefault($0.match.status) }.map(\.id)
      let playable = inRange.filter { !Self.isExcludedByDefault($0.match.status) }
      selections = try templates.list().compactMap { template in
        let chosen: [MatchDetail]
        switch (template.manifest.kind, template.manifest.purpose) {
        case (.list, .programme): chosen = playable
        case (.single, .prematch): chosen = playable.filter(\.team.isFirstTeam)
        default: chosen = []
        }
        return chosen.isEmpty ? nil : TemplateSelection(templateID: template.id, matchIDs: chosen.map(\.id))
      }
    }

    var items: [PlanItem] = []
    for selection in selections {
      let template = try templates.get(id: selection.templateID)
      var seen = Set<EntityID>()
      let details = try selection.matchIDs.filter { seen.insert($0).inserted }.map { try matches.get(id: $0) }
      items += self.items(for: template, details: details)
    }

    var allWarnings: [RenderWarning] = []
    for warning in items.flatMap(\.image.warnings) where !allWarnings.contains(warning) {
      allWarnings.append(warning)
    }
    let plan = RenderPlan(
      selections: selections, images: items.map(\.image), warnings: allWarnings, skippedMatchIDs: skipped)
    return (plan, items)
  }

  func items(for template: InstalledTemplate, details: [MatchDetail]) -> [PlanItem] {
    let manifest = template.manifest
    let builder = ContextBuilder(settings: settings, manifest: manifest, logosFolder: logosFolder)
    let sorted = details.sorted(by: MatchDetail.scheduleOrder)
    switch manifest.kind {
    case .single:
      return sorted.map { detail in
        let (context, warnings) = builder.single(detail)
        let fileName = renderFileName(
          date: detail.match.date, templateID: manifest.id, teamName: detail.team.name,
          opponentName: displayName(for: detail.opponent, limit: nil).text)
        let image = PlannedImage(
          templateID: manifest.id, matchIDs: [detail.id], date: detail.match.date, page: nil, fileName: fileName,
          width: manifest.width, height: manifest.height, warnings: Self.unique(warnings))
        return PlanItem(image: image, template: template, context: .single(context))
      }
    case .list:
      let days = Dictionary(grouping: sorted, by: \.match.date)
      return days.keys.sorted().flatMap { day in
        builder.pages(days[day] ?? []).map { page in
          let info = page.context.page
          let image = PlannedImage(
            templateID: manifest.id, matchIDs: page.matches.map(\.id), date: day, page: info,
            fileName: renderFileName(date: day, templateID: manifest.id, page: info), width: manifest.width,
            height: manifest.height, warnings: Self.unique(page.warnings))
          return PlanItem(image: image, template: template, context: .list(page.context))
        }
      }
    }
  }

  static func isExcludedByDefault(_ status: MatchStatus) -> Bool {
    status == .postponed || status == .cancelled
  }

  static func unique(_ warnings: [RenderWarning]) -> [RenderWarning] {
    var result: [RenderWarning] = []
    for warning in warnings where !result.contains(warning) { result.append(warning) }
    return result
  }
}
