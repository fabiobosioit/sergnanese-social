import Foundation
import SSCore

/// Renders the same matches with the same template again ("Rigenera"). Returns the new images, whose
/// records the render service already stored. A list image regenerates with the same matches on one
/// page. A page of a multi-page results recap is different: the recap is one set of pages over the whole
/// weekend, so every page of the set is rendered again (see `isMultiPageRecap`) and all new images are
/// returned.
@MainActor
func regenerateRecord(_ record: RenderRecord, services: AppServices) async throws -> [RenderedImage] {
  var matchIDs = record.matchIDs
  if isMultiPageRecap(record, services: services) {
    matchIDs = recapMatchIDs(of: record, services: services)
  }
  let request = RenderRequest(
    from: record.date, to: record.date,
    selections: [TemplateSelection(templateID: record.templateID, matchIDs: matchIDs)])
  var images: [RenderedImage] = []
  for try await event in services.renderer.render(request) {
    switch event {
    case .imageDone(let image, _, _): images.append(image)
    case .imageFailed(_, let message, _, _): throw AppError.render(message: message)
    default: break
    }
  }
  return images
}

/// `true` for a page of a results recap that has more than one page (page 2 of 2 alone would be planned
/// as a one-page recap with the wrong title, date and page label).
@MainActor
func isMultiPageRecap(_ record: RenderRecord, services: AppServices) -> Bool {
  guard let page = record.page, page.total > 1 else { return false }
  return (try? services.templates.get(id: record.templateID))?.manifest.isResultsRecap == true
}

/// `true` when both records are pages of the same recap run: same template, date and page count.
func isSameRecapSet(_ a: RenderRecord, _ b: RenderRecord) -> Bool {
  guard let pageA = a.page, let pageB = b.page else { return false }
  return a.templateID == b.templateID && a.date == b.date && pageA.total == pageB.total
}

/// The match ids of the whole recap `record` belongs to. For each page number, the record created closest
/// in time to `record` is taken, so an older run on the same day does not mix in. Falls back to the
/// record's own matches when no sibling is stored.
@MainActor
func recapMatchIDs(of record: RenderRecord, services: AppServices) -> [EntityID] {
  guard let total = record.page?.total,
    let stored = try? services.renders.list(from: record.date, to: record.date)
  else { return record.matchIDs }
  var closest: [Int: RenderRecord] = [:]
  for candidate in stored where isSameRecapSet(record, candidate) {
    guard let index = candidate.page?.index, (1...total).contains(index) else { continue }
    let distance = abs(candidate.createdAt.timeIntervalSince(record.createdAt))
    if let current = closest[index],
      abs(current.createdAt.timeIntervalSince(record.createdAt)) <= distance
    {
      continue
    }
    closest[index] = candidate
  }
  closest[record.page?.index ?? 0] = record
  var seen = Set<EntityID>()
  let ids = closest.keys.sorted().flatMap { closest[$0]?.matchIDs ?? [] }.filter { seen.insert($0).inserted }
  return ids.isEmpty ? record.matchIDs : ids
}
