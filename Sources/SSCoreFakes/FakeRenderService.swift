import CoreGraphics
import Foundation
import ImageIO
import SSCore

/// A render service that "renders" by writing a flat-colour PNG of the template's exact size after a
/// short delay. It follows the documented planning rules (default plan, one set per day for list
/// templates, pagination, warnings, skipped matches), names files like the real engine, never
/// overwrites, stores a `RenderRecord` per image and stops after the current image when cancelled.
@MainActor
public final class FakeRenderService: RenderService {
  let templates: any TemplateStore
  let matches: any MatchRepository
  let renders: any RenderRepository
  let settings: any SettingsRepository
  let paths: AppPaths
  /// Pause before each image, so progress and cancellation can be seen and tested.
  public var delay: Duration
  /// Images of these templates fail with `.imageFailed` (for testing the failure path).
  public var failingTemplateIDs: Set<String>
  /// Awaited before each image (1-based index), after `delay` and before the cancellation check.
  /// Tests use it to hold a run at a known point instead of relying on timing.
  public var beforeEachImage: (@MainActor @Sendable (_ index: Int) async -> Void)?
  /// Render runs still going; each removes itself when it stops.
  private var runs: [UUID: Task<Void, Never>] = [:]

  public init(
    templates: any TemplateStore, matches: any MatchRepository, renders: any RenderRepository,
    settings: any SettingsRepository, paths: AppPaths, delay: Duration = .milliseconds(150),
    failingTemplateIDs: Set<String> = []
  ) {
    self.templates = templates
    self.matches = matches
    self.renders = renders
    self.settings = settings
    self.paths = paths
    self.delay = delay
    self.failingTemplateIDs = failingTemplateIDs
  }

  // MARK: Plan

  public func plan(_ request: RenderRequest) throws -> RenderPlan {
    let inRange = try matches.list(from: request.from, to: request.to, teamID: nil)
    let excluded = inRange.filter { $0.match.status == .postponed || $0.match.status == .cancelled }
    var skipped: [EntityID] = []
    let selections: [TemplateSelection]
    if let explicit = request.selections {
      selections = explicit
    } else {
      skipped = excluded.map(\.id)
      let playable = inRange.filter { !skipped.contains($0.id) }
      selections = try templates.list().compactMap { template in
        let manifest = template.manifest
        let chosen: [MatchDetail]
        switch (manifest.kind, manifest.purpose) {
        case (.list, .programme): chosen = playable
        case (.single, .prematch): chosen = playable.filter(\.team.isFirstTeam)
        default: chosen = []
        }
        return chosen.isEmpty ? nil : TemplateSelection(templateID: template.id, matchIDs: chosen.map(\.id))
      }
    }

    var images: [PlannedImage] = []
    for selection in selections {
      let manifest = try templates.get(id: selection.templateID).manifest
      let details = try selection.matchIDs.map { try matches.get(id: $0) }.sorted(by: MatchDetail.scheduleOrder)
      switch manifest.kind {
      case .single:
        for detail in details {
          images.append(
            PlannedImage(
              templateID: manifest.id, matchIDs: [detail.id], date: detail.match.date, page: nil,
              fileName: renderFileName(
                date: detail.match.date, templateID: manifest.id, teamName: detail.team.name,
                opponentName: displayName(for: detail.opponent, limit: nil).text),
              width: manifest.width, height: manifest.height, warnings: warnings(for: [detail], manifest: manifest)))
        }
      case .list:
        let pageSize = manifest.pageSize ?? 10
        let days = Dictionary(grouping: details, by: \.match.date)
        for day in days.keys.sorted() {
          let rows = days[day] ?? []
          let pages = stride(from: 0, to: rows.count, by: pageSize).map {
            Array(rows[$0..<min($0 + pageSize, rows.count)])
          }
          for (offset, pageRows) in pages.enumerated() {
            let page = PageInfo(index: offset + 1, total: pages.count)
            images.append(
              PlannedImage(
                templateID: manifest.id, matchIDs: pageRows.map(\.id), date: day, page: page,
                fileName: renderFileName(date: day, templateID: manifest.id, page: page), width: manifest.width,
                height: manifest.height, warnings: warnings(for: pageRows, manifest: manifest)))
          }
        }
      }
    }

    var allWarnings: [RenderWarning] = []
    for warning in images.flatMap(\.warnings) where !allWarnings.contains(warning) { allWarnings.append(warning) }
    return RenderPlan(selections: selections, images: images, warnings: allWarnings, skippedMatchIDs: skipped)
  }

  private func warnings(for details: [MatchDetail], manifest: TemplateManifest) -> [RenderWarning] {
    details.flatMap { detail in
      var list = matchWarnings(for: detail, teamNameLimit: manifest.limits.teamName)
      if detail.match.status == .postponed || detail.match.status == .cancelled {
        list.append(
          RenderWarning(kind: .matchNotScheduled, message: FakeStrings.warningNotScheduled, matchID: detail.id))
      }
      return list
    }
  }

  // MARK: Render

  public func render(_ request: RenderRequest) -> AsyncThrowingStream<RenderEvent, any Error> {
    AsyncThrowingStream { continuation in
      let runID = UUID()
      let task = Task { @MainActor in
        defer { self.runs[runID] = nil }
        do {
          let plan = try self.plan(request)
          let output = self.paths.outputFolder(for: try self.settings.load())
          let accent = try self.settings.load().accentColor
          let total = plan.images.count
          continuation.yield(.started(total: total))
          var produced = 0
          var failed = 0
          for (offset, image) in plan.images.enumerated() {
            try await Task.sleep(for: self.delay)
            let index = offset + 1
            await self.beforeEachImage?(index)
            try Task.checkCancellation()
            if self.failingTemplateIDs.contains(image.templateID) {
              failed += 1
              continuation.yield(
                .imageFailed(
                  image, message: FakeStrings.fakeRenderFailure(image.templateID), index: index, total: total))
              continue
            }
            let record = try self.write(image, output: output, accent: accent)
            try self.renders.insert(record)
            produced += 1
            continuation.yield(
              .imageDone(RenderedImage(record: record, warnings: image.warnings), index: index, total: total))
          }
          continuation.yield(.finished(RenderSummary(produced: produced, failed: failed, warnings: plan.warnings)))
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      runs[runID] = task
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Returns when every render run started so far has stopped (finished, failed or cancelled), so
  /// tests can check what a cancelled run left behind without waiting on the clock.
  public func waitUntilIdle() async {
    while let run = runs.values.first { await run.value }
  }

  private func write(_ image: PlannedImage, output: URL, accent: String) throws -> RenderRecord {
    let folder = renderFolder(outputFolder: output, date: image.date)
    let manifest = try templates.get(id: image.templateID).manifest
    let name = uniqueFileName(image.fileName) {
      FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
    }
    let file = folder.appendingPathComponent(name)
    try writeFlatPNG(
      width: image.width, height: image.height, hexColor: Self.color(for: image.templateID, accent: accent), to: file)
    return RenderRecord(
      id: newEntityID(), templateID: image.templateID, templateVersion: manifest.version, matchIDs: image.matchIDs,
      date: image.date, page: image.page, file: file.path, width: image.width, height: image.height,
      warnings: image.warnings.map(\.message), createdAt: Date())
  }

  // MARK: Preview

  public func preview(templateID: String, matchIDs: [EntityID]) async throws -> URL {
    let manifest = try templates.get(id: templateID).manifest
    for id in matchIDs { _ = try matches.get(id: id) }
    try await Task.sleep(for: delay)
    let accent = (try? settings.load().accentColor) ?? ClubSettings.defaultAccentColor
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("SergnanesePreview-\(templateID)-\(newEntityID()).png")
    try writeFlatPNG(
      width: manifest.width, height: manifest.height, hexColor: Self.color(for: templateID, accent: accent), to: file)
    return file
  }

  /// The accent colour for list templates, a stable shade per id for the others, so thumbnails differ.
  static func color(for templateID: String, accent: String) -> String {
    let palette = ["#2F5D8A", "#3C7A4E", "#8A5A2F", "#6A3C7A", "#7A7A7A"]
    if templateID.contains("programme") { return accent }
    let sum = templateID.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[sum % palette.count]
  }
}

/// Writes a PNG of exactly `width × height` pixels filled with `hexColor` (sRGB). Creates the folder.
public func writeFlatPNG(width: Int, height: Int, hexColor: String, to url: URL) throws {
  let hex = normalizedHexColor(hexColor) ?? ClubSettings.defaultAccentColor
  let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
  let red = CGFloat((value >> 16) & 0xFF) / 255
  let green = CGFloat((value >> 8) & 0xFF) / 255
  let blue = CGFloat(value & 0xFF) / 255
  guard let space = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { throw AppError.render(message: FakeStrings.cannotWrite(url.path)) }
  context.setFillColor(CGColor(colorSpace: space, components: [red, green, blue, 1]) ?? CGColor(gray: 0.5, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  do {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  } catch {
    throw AppError.io(message: FakeStrings.cannotWrite(url.path))
  }
  guard let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
  else { throw AppError.io(message: FakeStrings.cannotWrite(url.path)) }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { throw AppError.io(message: FakeStrings.cannotWrite(url.path)) }
}
