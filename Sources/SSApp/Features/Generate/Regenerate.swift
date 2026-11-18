import Foundation
import SSCore

/// Renders the same matches with the same template again ("Rigenera"). Returns the new images, whose
/// records the render service already stored. A list image regenerates with the same matches on one
/// page.
@MainActor
func regenerateRecord(_ record: RenderRecord, services: AppServices) async throws -> [RenderedImage] {
  let request = RenderRequest(
    from: record.date, to: record.date,
    selections: [TemplateSelection(templateID: record.templateID, matchIDs: record.matchIDs)])
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
