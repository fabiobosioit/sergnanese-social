import SSCore

/// Per-match warnings as the weekend's default plan would raise them.
///
/// The warnings that do not depend on a template (time, venue, logo) come from `matchWarnings` with no
/// name limit. The name-cut warning comes from the plan, which applies the limit of the templates the
/// match would really be rendered with, not the smallest limit of every installed template.
@MainActor
func defaultPlanWarnings(
  for details: [MatchDetail], weekend: Weekend, services: AppServices
) -> [EntityID: [RenderWarning]] {
  let planned = (try? services.renderer.plan(RenderRequest(weekend: weekend)))?.warnings ?? []
  var result: [EntityID: [RenderWarning]] = [:]
  for detail in details {
    var warnings = matchWarnings(for: detail, teamNameLimit: nil)
    for warning in planned where warning.matchID == detail.id && !warnings.contains(warning) {
      warnings.append(warning)
    }
    result[detail.id] = warnings
  }
  return result
}
