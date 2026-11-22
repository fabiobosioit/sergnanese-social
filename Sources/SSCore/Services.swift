import Foundation

// Services: the contract between the UI and the engine. There is no HTTP API; `AppServices` is the
// one container handed to the UI.

// MARK: - Logos

/// Opponent logos in the logos folder (`AppPaths.logos`).
///
/// Imports are `async` so an implementation may rasterise SVG on the main actor; every other
/// method is synchronous.
public protocol LogoStore: Sendable {
  /// Imports an image file (PNG, JPEG, WebP, HEIC or SVG; at most 5 MB). The logo is always stored
  /// as a PNG of at most 1024 px under a newly generated file name, which is returned. When
  /// `replacing` names an existing logo, that file is removed after a successful import.
  /// Throws `AppError.validation(field: .logo, …)` for an unsupported or oversized file.
  func importLogo(from url: URL, replacing: String?) async throws -> String
  /// Same as `importLogo(from:replacing:)` for image data (a paste or a drag from a browser).
  func importLogo(data: Data, replacing: String?) async throws -> String
  /// Same as `importLogo(data:replacing:)`, but the caller chooses the stored name (T4.2: downloaded
  /// logos are stored as `"<ClubId>.png"`; T4.8: CSI logos as `"csi-<id or slug>.png"`). `fileName` must
  /// pass `isValidImportedLogoFileName`, otherwise `AppError.validation(field: .logo, …)` is thrown and
  /// nothing is written. An existing file with that name is replaced. Returns `fileName`.
  ///
  /// A default implementation exists (import under a generated name, then move the file); stores
  /// should implement it directly so the file is written in one step.
  func importLogo(data: Data, fileName: String, replacing: String?) async throws -> String
  /// Removes a logo file. Removing a file that does not exist is not an error.
  func remove(fileName: String) throws
  /// Absolute file URL of a logo, for thumbnails. The file may not exist.
  func url(for fileName: String) -> URL
}

extension LogoStore {
  /// Default for stores that do not implement it: imports under a generated name with
  /// `importLogo(data:replacing:)`, then moves that file to `fileName` (removing an existing one).
  public func importLogo(data: Data, fileName: String, replacing: String?) async throws -> String {
    guard isValidImportedLogoFileName(fileName) else {
      throw AppError.validation(field: .logo, message: CoreStrings.invalidLogoFileName(fileName))
    }
    let generated = try await importLogo(data: data, replacing: nil)
    let source = url(for: generated)
    let target = url(for: fileName)
    do {
      if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
      try FileManager.default.moveItem(at: source, to: target)
    } catch {
      try? remove(fileName: generated)
      throw AppError.io(message: CoreStrings.cannotSaveLogo(fileName))
    }
    if let replacing, replacing != fileName { try remove(fileName: replacing) }
    return fileName
  }
}

// MARK: - Templates

/// A template installed in the data folder's `templates/`.
public struct InstalledTemplate: Sendable, Equatable, Hashable, Identifiable {
  public var manifest: TemplateManifest
  /// The template folder (holds `manifest.json`, `template.html`, `assets/`).
  public var folder: URL
  /// Shipped with the app (from `Resources/Templates`). Built-ins cannot be removed, only restored.
  public var isBuiltin: Bool

  public var id: String { manifest.id }

  public init(manifest: TemplateManifest, folder: URL, isBuiltin: Bool) {
    self.manifest = manifest
    self.folder = folder
    self.isBuiltin = isBuiltin
  }
}

/// Result of `TemplateStore.install(from:replace:)`.
public enum TemplateInstallOutcome: Sendable, Equatable {
  case installed(InstalledTemplate)
  /// The folder or zip is not a valid template; one Italian sentence per problem. Nothing changed.
  case invalid(problems: [String])
  /// A template with the same id is installed and `replace` was false. Nothing changed; ask the
  /// user ("Sostituire?") and call again with `replace: true`.
  case alreadyExists(InstalledTemplate)
}

public protocol TemplateStore: Sendable {
  /// Copies each built-in template into `templates/` when it is missing or the bundled version is
  /// newer (`compareTemplateVersions`). Called at startup.
  func installBuiltins() throws
  /// Installed templates, ordered by name.
  func list() throws -> [InstalledTemplate]
  func get(id: String) throws -> InstalledTemplate
  /// Installs a template folder or `.zip` (validated: manifest, `template.html`, root size, no path
  /// traversal or symlinks, at most 20 MB and 200 files, allowed file types only). Throws only for
  /// unexpected I/O failures; validation problems are returned as `.invalid`.
  func install(from url: URL, replace: Bool) throws -> TemplateInstallOutcome
  /// Removes a user template. Throws `AppError.conflict` for a built-in.
  func remove(id: String) throws
  /// Puts back the bundled copy of a built-in template, discarding any replacement. Throws
  /// `AppError.notFound` when `id` is not a built-in.
  func restoreBuiltin(id: String) throws -> InstalledTemplate
}

// MARK: - Rendering

/// The matches one template is rendered with.
public struct TemplateSelection: Sendable, Equatable, Hashable {
  public var templateID: String
  /// A `list` template puts these matches in one set of images per day; a `single` template makes
  /// one image per match.
  public var matchIDs: [EntityID]

  public init(templateID: String, matchIDs: [EntityID]) {
    self.templateID = templateID
    self.matchIDs = matchIDs
  }
}

/// What to render.
public struct RenderRequest: Sendable, Equatable, Hashable {
  /// First day of the range (inclusive), normally the weekend's Saturday.
  public var from: DayDate
  /// Last day of the range (inclusive), normally the weekend's Sunday.
  public var to: DayDate
  /// `nil` = the default plan for the range:
  /// - every installed `list` template with purpose `.programme` takes every scheduled match in the
  ///   range, one set of images per day;
  /// - every installed `single` template with purpose `.prematch` takes the first team's scheduled
  ///   match(es) in the range.
  ///
  /// Postponed and cancelled matches are left out of the default plan and listed in
  /// `RenderPlan.skippedMatchIDs`. Explicit selections are used as given: an explicitly selected
  /// postponed or cancelled match is rendered, with a `.matchNotScheduled` warning.
  public var selections: [TemplateSelection]?

  public init(from: DayDate, to: DayDate, selections: [TemplateSelection]? = nil) {
    self.from = from
    self.to = to
    self.selections = selections
  }

  /// The default plan for a weekend.
  public init(weekend: Weekend, selections: [TemplateSelection]? = nil) {
    self.init(from: weekend.saturday, to: weekend.sunday, selections: selections)
  }
}

/// One image a render would produce.
public struct PlannedImage: Sendable, Equatable, Hashable, Identifiable {
  /// Stable within a plan: `"<templateID>|<matchIDs joined by ,>|<page index>"`.
  public var id: String { "\(templateID)|\(matchIDs.joined(separator: ","))|\(page?.index ?? 0)" }
  public var templateID: String
  /// Matches on this image, in `MatchDetail.scheduleOrder`.
  public var matchIDs: [EntityID]
  /// The match date, or the first date for a list image.
  public var date: DayDate
  /// `nil` for single images.
  public var page: PageInfo?
  /// File name per `renderFileName…`; the real render may add `-2`, `-3` to avoid overwriting.
  public var fileName: String
  public var width: Int
  public var height: Int
  public var warnings: [RenderWarning]

  public init(
    templateID: String, matchIDs: [EntityID], date: DayDate, page: PageInfo?, fileName: String, width: Int,
    height: Int, warnings: [RenderWarning]
  ) {
    self.templateID = templateID
    self.matchIDs = matchIDs
    self.date = date
    self.page = page
    self.fileName = fileName
    self.width = width
    self.height = height
    self.warnings = warnings
  }
}

/// Dry run of a request: what would be produced, without rendering.
public struct RenderPlan: Sendable, Equatable, Hashable {
  /// The selections actually used: the request's, or the default plan's when it had none. The
  /// Genera screen pre-checks its match and template lists from these.
  public var selections: [TemplateSelection]
  /// In selection order, then page order.
  public var images: [PlannedImage]
  /// Every warning of every image, without duplicates, in image order.
  public var warnings: [RenderWarning]
  /// Postponed or cancelled matches in the range that the default plan left out.
  public var skippedMatchIDs: [EntityID]

  public init(
    selections: [TemplateSelection], images: [PlannedImage], warnings: [RenderWarning], skippedMatchIDs: [EntityID]
  ) {
    self.selections = selections
    self.images = images
    self.warnings = warnings
    self.skippedMatchIDs = skippedMatchIDs
  }
}

/// A finished image of a render.
public struct RenderedImage: Sendable, Equatable, Hashable, Identifiable {
  /// The record already stored through `RenderRepository`; `record.file` is the PNG.
  public var record: RenderRecord
  public var warnings: [RenderWarning]

  public var id: EntityID { record.id }

  public init(record: RenderRecord, warnings: [RenderWarning]) {
    self.record = record
    self.warnings = warnings
  }
}

/// Totals of a render that ran to the end.
public struct RenderSummary: Sendable, Equatable, Hashable {
  public var produced: Int
  public var failed: Int
  public var warnings: [RenderWarning]

  public init(produced: Int, failed: Int, warnings: [RenderWarning]) {
    self.produced = produced
    self.failed = failed
    self.warnings = warnings
  }
}

/// Progress of `RenderService.render`. `index` is 1-based: image 3 of 12 is `index: 3, total: 12`.
public enum RenderEvent: Sendable, Equatable {
  case started(total: Int)
  case imageDone(RenderedImage, index: Int, total: Int)
  /// One image failed; the render goes on with the next one.
  case imageFailed(PlannedImage, message: String, index: Int, total: Int)
  case finished(RenderSummary)
}

/// The render engine. Main-actor isolated because it drives a `WKWebView`.
@MainActor
public protocol RenderService: Sendable {
  /// Dry run. Throws `AppError.notFound` for an unknown template or match id.
  func plan(_ request: RenderRequest) throws -> RenderPlan
  /// Renders the plan of `request`: `.started`, one `.imageDone` or `.imageFailed` per image, then
  /// `.finished`. Files are written under the output folder with `renderFileName…` names (never
  /// overwriting) and a `RenderRecord` is inserted for each image. Cancelling the consuming task
  /// stops after the current image; the images already made are kept. The stream throws only when
  /// the whole run cannot start (unknown template, unwritable output folder).
  func render(_ request: RenderRequest) -> AsyncThrowingStream<RenderEvent, any Error>
  /// Renders one image of a template to a temporary PNG and returns its URL. Without match ids the
  /// fixture context is used (thumbnails, Templates screen). For a `list` template, every given
  /// match goes on the first page.
  func preview(templateID: String, matchIDs: [EntityID]) async throws -> URL
}

// MARK: - Demo data

/// Counts of what `DemoDataLoader.load(today:)` inserted.
public struct DemoDataSummary: Sendable, Equatable, Hashable {
  public var teams: Int
  public var opponents: Int
  public var matches: Int

  public init(teams: Int, opponents: Int, matches: Int) {
    self.teams = teams
    self.opponents = opponents
    self.matches = matches
  }
}

/// Fake matches for trying the app ("Carica dati demo").
public protocol DemoDataLoader: Sendable {
  /// Removes earlier demo matches, then inserts the demo teams, opponents (with logos) and matches
  /// for the weekends around `today`, all matches with source `.seed`. Teams and opponents that
  /// already exist with the same name are reused, so loading twice leaves the same number of rows.
  func load(today: DayDate) async throws -> DemoDataSummary
  /// Removes every `.seed` match, then the demo teams and opponents that no other match uses.
  func remove() throws
  /// `true` when at least one `.seed` match exists.
  func hasDemoData() throws -> Bool
}

// MARK: - Container

/// Everything the UI needs, built once at startup (`Composition.makeServices()` or `AppServices.fake()`).
public struct AppServices: Sendable {
  public var teams: any TeamRepository
  public var opponents: any OpponentRepository
  public var matches: any MatchRepository
  public var settings: any SettingsRepository
  public var renders: any RenderRepository
  public var logos: any LogoStore
  public var templates: any TemplateStore
  public var renderer: any RenderService
  public var demoData: any DemoDataLoader
  public var paths: AppPaths
  /// Tuttocampo import (T4.2). Containers built without one get a source whose fetches throw
  /// `FixtureFetchError.unavailable`.
  public var fixtureSource: any FixtureSource
  /// CSI Live import (T4.8): parses the page the user opened in the CSI browser window. Containers built
  /// without one get a parser that answers "not a CSI girone" for every page.
  public var csiPageParser: any PageFixtureParser

  public init(
    teams: any TeamRepository, opponents: any OpponentRepository, matches: any MatchRepository,
    settings: any SettingsRepository, renders: any RenderRepository, logos: any LogoStore,
    templates: any TemplateStore, renderer: any RenderService, demoData: any DemoDataLoader, paths: AppPaths,
    fixtureSource: any FixtureSource = UnavailableFixtureSource(),
    csiPageParser: any PageFixtureParser = UnavailablePageFixtureParser()
  ) {
    self.teams = teams
    self.opponents = opponents
    self.matches = matches
    self.settings = settings
    self.renders = renders
    self.logos = logos
    self.templates = templates
    self.renderer = renderer
    self.demoData = demoData
    self.paths = paths
    self.fixtureSource = fixtureSource
    self.csiPageParser = csiPageParser
  }
}
