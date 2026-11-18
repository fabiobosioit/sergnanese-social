import Foundation
import SSCore

/// The real render engine: plans with `RenderPlanner`, fills templates with Mustache, renders them
/// with one shared off-screen `WebRenderer`, writes PNGs under the output folder and stores a
/// `RenderRecord` per image.
@MainActor
public final class TemplateRenderService: RenderService {
  let templates: any TemplateStore
  let matches: any MatchRepository
  let renders: any RenderRepository
  let settings: any SettingsRepository
  let paths: AppPaths
  let html = TemplateHTML()
  private var webRenderer: WebRenderer?

  /// `renderer` is created on first use when `nil`.
  public init(
    templates: any TemplateStore, matches: any MatchRepository, renders: any RenderRepository,
    settings: any SettingsRepository, paths: AppPaths, renderer: WebRenderer? = nil
  ) {
    self.templates = templates
    self.matches = matches
    self.renders = renders
    self.settings = settings
    self.paths = paths
    self.webRenderer = renderer
  }

  /// The shared web renderer (one web view for every image).
  public var renderer: WebRenderer {
    if let webRenderer { return webRenderer }
    let created = WebRenderer()
    webRenderer = created
    return created
  }

  // MARK: Plan

  public func plan(_ request: RenderRequest) throws -> RenderPlan {
    try planner().plan(request).plan
  }

  private func planner() throws -> RenderPlanner {
    RenderPlanner(templates: templates, matches: matches, settings: try settings.load(), logosFolder: paths.logos)
  }

  // MARK: Render

  public func render(_ request: RenderRequest) -> AsyncThrowingStream<RenderEvent, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task { @MainActor in
        do {
          try await self.run(request, continuation: continuation)
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func run(_ request: RenderRequest, continuation: AsyncThrowingStream<RenderEvent, any Error>.Continuation)
    async throws
  {
    let clubSettings = try settings.load()
    let (plan, items) = try planner().plan(request)
    let output = paths.outputFolder(for: clubSettings)
    do {
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    } catch {
      throw AppError.io(message: RenderStrings.cannotCreateOutputFolder(output.path))
    }

    let total = items.count
    continuation.yield(.started(total: total))
    var produced = 0
    var failed = 0
    var allWarnings = plan.warnings
    for (offset, item) in items.enumerated() {
      // Cancelling stops between images; the images already written are kept.
      if Task.isCancelled { return }
      let index = offset + 1
      do {
        let (png, warnings) = try await renderImage(item)
        let record = try save(png, item: item, warnings: warnings, output: output)
        try renders.insert(record)
        produced += 1
        for warning in warnings where !allWarnings.contains(warning) { allWarnings.append(warning) }
        continuation.yield(
          .imageDone(RenderedImage(record: record, warnings: warnings), index: index, total: total))
      } catch {
        failed += 1
        continuation.yield(.imageFailed(item.image, message: Self.message(for: error), index: index, total: total))
      }
    }
    if Task.isCancelled { return }
    continuation.yield(.finished(RenderSummary(produced: produced, failed: failed, warnings: allWarnings)))
  }

  /// Renders one planned image; returns the PNG and the image's warnings plus one per blocked request.
  private func renderImage(_ item: PlanItem) async throws -> (Data, [RenderWarning]) {
    let filled = try html.render(item.template, context: item.context)
    let page = WebRenderer.Page(
      html: filled, templateFolder: item.template.folder, logosFolder: paths.logos, width: item.image.width,
      height: item.image.height)
    let result = try await renderer.render(page)
    return (result.png, item.image.warnings + Self.blockedWarnings(result.blockedURLs, templateID: item.template.id))
  }

  private func save(_ png: Data, item: PlanItem, warnings: [RenderWarning], output: URL) throws -> RenderRecord {
    let folder = renderFolder(outputFolder: output, date: item.image.date)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
      throw AppError.io(message: RenderStrings.cannotWrite(folder.path))
    }
    let file = try Self.writeNew(png, in: folder, preferredName: item.image.fileName)
    return RenderRecord(
      id: newEntityID(), templateID: item.template.id, templateVersion: item.template.manifest.version,
      matchIDs: item.image.matchIDs, date: item.image.date, page: item.image.page, file: file.path,
      width: item.image.width, height: item.image.height, warnings: warnings.map(\.message), createdAt: Date())
  }

  /// Writes `data` under `preferredName`, or `name-2.png`, `name-3.png`, … when taken. Never
  /// overwrites, even if another process creates the file in between.
  static func writeNew(_ data: Data, in folder: URL, preferredName: String) throws -> URL {
    var taken = Set<String>()
    for _ in 0..<1000 {
      let name = uniqueFileName(preferredName) {
        taken.contains($0) || FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
      }
      let file = folder.appendingPathComponent(name)
      do {
        try data.write(to: file, options: [.withoutOverwriting])
        return file
      } catch CocoaError.fileWriteFileExists {
        taken.insert(name)
      } catch {
        throw AppError.io(message: RenderStrings.cannotWrite(file.path))
      }
    }
    throw AppError.io(message: RenderStrings.cannotWrite(folder.appendingPathComponent(preferredName).path))
  }

  static func blockedWarnings(_ urls: [String], templateID: String) -> [RenderWarning] {
    urls.map { RenderWarning(kind: .blockedRequest, message: RenderStrings.blockedRequest($0), templateID: templateID) }
  }

  static func message(for error: any Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription { return description }
    return String(describing: error)
  }

  // MARK: Preview

  public func preview(templateID: String, matchIDs: [EntityID]) async throws -> URL {
    let template = try templates.get(id: templateID)
    let manifest = template.manifest
    let clubSettings = try settings.load()
    let context: TemplateContext
    let logosFolder: URL
    if matchIDs.isEmpty {
      let builder = ContextBuilder(settings: clubSettings, manifest: manifest)
      context = try FixtureContexts.load(
        FixtureContexts.standardFile(for: manifest.kind, in: paths.fixtures), for: manifest, club: builder.club)
      logosFolder = paths.fixtures.appendingPathComponent("logos", isDirectory: true)
    } else {
      let details = try matchIDs.map { try matches.get(id: $0) }
      var onePage = manifest
      if manifest.kind == .list { onePage.pageSize = max(details.count, 1) }
      let builder = ContextBuilder(settings: clubSettings, manifest: onePage, logosFolder: paths.logos)
      switch manifest.kind {
      case .single:
        let sorted = details.sorted(by: MatchDetail.scheduleOrder)
        guard let first = sorted.first else { throw AppError.notFound }
        context = .single(builder.single(first).context)
      case .list:
        guard let page = builder.pages(details).first else { throw AppError.notFound }
        context = .list(page.context)
      }
      logosFolder = paths.logos
    }
    let filled = try html.render(template, context: context)
    let result = try await renderer.render(
      WebRenderer.Page(
        html: filled, templateFolder: template.folder, logosFolder: logosFolder, width: manifest.width,
        height: manifest.height))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SergnanesePreview-\(templateID)-\(newEntityID()).png")
    do {
      try result.png.write(to: file, options: [.withoutOverwriting])
    } catch {
      throw AppError.io(message: RenderStrings.cannotWrite(file.path))
    }
    return file
  }
}
