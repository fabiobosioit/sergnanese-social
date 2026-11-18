import Foundation
import OSLog
import SSCore
import SSData
import SSRender
import SSSeed
import SSTemplates

/// Logging for startup, imports and renders. The subsystem is the bundle id.
enum Log {
  static let subsystem = Bundle.main.bundleIdentifier ?? "com.sergnanese.social"
  static let startup = Logger(subsystem: subsystem, category: "startup")
  static let imports = Logger(subsystem: subsystem, category: "import")
  static let render = Logger(subsystem: subsystem, category: "render")
}

/// Builds the real service container: database (migrations and backup), built-in templates,
/// repositories, logo store, render engine and demo-data loader.
enum Composition {
  /// `paths` are resolved by the caller (`AppPaths.resolve()`); `--smoke` passes its own.
  @MainActor
  static func makeServices(paths: AppPaths) throws -> AppServices {
    Log.startup.info("Data folder: \(paths.dataFolder.path, privacy: .public)")
    let database = try AppDatabase.open(paths: paths)
    let logos = LogoFileStore(folder: paths.logos)
    let store = FileTemplateStore(paths: paths)
    try store.installBuiltins()
    let templates = LoggingTemplateStore(base: store)
    let renderer = LoggingRenderService(
      base: TemplateRenderService(
        templates: templates, matches: database.matches, renders: database.renders,
        settings: database.settings, paths: paths))
    let demo = SeedLoader(
      seedFolder: paths.seed, teams: database.teams, opponents: database.opponents, matches: database.matches,
      logos: logos)
    Log.startup.info("Services ready")
    return AppServices(
      teams: database.teams, opponents: database.opponents, matches: database.matches,
      settings: database.settings, renders: database.renders, logos: logos, templates: templates,
      renderer: renderer, demoData: demo, paths: paths)
  }
}

/// Logs template imports and removals.
struct LoggingTemplateStore: TemplateStore {
  let base: any TemplateStore

  func installBuiltins() throws { try base.installBuiltins() }
  func list() throws -> [InstalledTemplate] { try base.list() }
  func get(id: String) throws -> InstalledTemplate { try base.get(id: id) }

  func install(from url: URL, replace: Bool) throws -> TemplateInstallOutcome {
    do {
      let outcome = try base.install(from: url, replace: replace)
      switch outcome {
      case .installed(let template): Log.imports.info("Template installed: \(template.id, privacy: .public)")
      case .invalid(let problems): Log.imports.error("Template rejected: \(problems.count) problem(s)")
      case .alreadyExists(let template): Log.imports.info("Template exists: \(template.id, privacy: .public)")
      }
      return outcome
    } catch {
      Log.imports.error("Template import failed: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }

  func remove(id: String) throws {
    try base.remove(id: id)
    Log.imports.info("Template removed: \(id, privacy: .public)")
  }

  func restoreBuiltin(id: String) throws -> InstalledTemplate {
    let template = try base.restoreBuiltin(id: id)
    Log.imports.info("Built-in restored: \(id, privacy: .public)")
    return template
  }
}

/// Logs renders: start, failed images, totals.
@MainActor
final class LoggingRenderService: RenderService {
  private let base: any RenderService

  init(base: any RenderService) { self.base = base }

  func plan(_ request: RenderRequest) throws -> RenderPlan { try base.plan(request) }

  func render(_ request: RenderRequest) -> AsyncThrowingStream<RenderEvent, any Error> {
    let inner = base.render(request)
    return AsyncThrowingStream { continuation in
      let task = Task { @MainActor in
        do {
          for try await event in inner {
            switch event {
            case .started(let total): Log.render.info("Render started: \(total) image(s)")
            case .imageFailed(let image, let message, _, _):
              Log.render.error("Image failed \(image.fileName, privacy: .public): \(message, privacy: .public)")
            case .finished(let summary):
              Log.render.info("Render finished: \(summary.produced) done, \(summary.failed) failed")
            case .imageDone: break
            }
            continuation.yield(event)
          }
          continuation.finish()
        } catch {
          Log.render.error("Render could not start: \(error.localizedDescription, privacy: .public)")
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func preview(templateID: String, matchIDs: [EntityID]) async throws -> URL {
    try await base.preview(templateID: templateID, matchIDs: matchIDs)
  }
}
