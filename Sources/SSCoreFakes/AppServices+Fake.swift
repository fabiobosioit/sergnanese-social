import Foundation
import SSCore

extension AppServices {
  /// Services on in-memory fakes, filled from `Resources/Fixtures/matches.json` with dates moved so
  /// the fixture's reference weekend is the weekend of `today`. Everything on disk (logos, template
  /// folders, rendered PNGs) goes to a new temporary folder; the user's folders are never touched.
  ///
  /// Used by `Scripts/run.sh --mock`, by previews and by view-model tests. Stops the process with a
  /// clear message when the fixtures cannot be found: mock mode without data would only mislead.
  @MainActor
  public static func fake(today: DayDate = .today()) -> AppServices {
    do {
      return try fake(dataSet: Fixtures.dataSet().shifted(toWeekendOf: today))
    } catch {
      fatalError("AppServices.fake(): \(error.localizedDescription)")
    }
  }

  /// Services on in-memory fakes holding exactly `dataSet` (use `FakeDataSet.empty()` for an empty
  /// app). The fixture source is `FakeFixtureSource.scenario` around `dataSet.referenceSaturday`, with
  /// `renderDelay` as its fetch delay. Render `file` paths that are relative are resolved against the output folder, and a
  /// flat PNG is written for each record except those in `missingRenderFileIDs`.
  @MainActor
  public static func fake(dataSet: FakeDataSet, renderDelay: Duration = .milliseconds(150)) throws -> AppServices {
    let paths = try AppPaths.temporary()
    var data = dataSet
    data.settings.outputFolder = nil
    data.renders = try data.renders.map { record in
      var record = record
      if !record.file.hasPrefix("/") {
        record.file = paths.defaultOutputFolder.appendingPathComponent(record.file).path
      }
      if !data.missingRenderFileIDs.contains(record.id) {
        try writeFlatPNG(
          width: record.width, height: record.height,
          hexColor: FakeRenderService.color(for: record.templateID, accent: data.settings.accentColor),
          to: record.fileURL)
      }
      return record
    }
    if let logos = try? Fixtures.logosFolder(),
      let files = try? FileManager.default.contentsOfDirectory(atPath: logos.path)
    {
      for file in files where file.hasSuffix(".png") {
        try? FileManager.default.copyItem(
          at: logos.appendingPathComponent(file), to: paths.logos.appendingPathComponent(file))
      }
    }

    let database = FakeDatabase(data)
    let teams = FakeTeamRepository(database: database)
    let opponents = FakeOpponentRepository(database: database)
    let matches = FakeMatchRepository(database: database)
    let settings = FakeSettingsRepository(database: database)
    let renders = FakeRenderRepository(database: database)
    let templates = FakeTemplateStore(folder: paths.templates)
    let renderer = FakeRenderService(
      templates: templates, matches: matches, renders: renders, settings: settings, paths: paths,
      delay: renderDelay)
    let demoSource = (try? Fixtures.dataSet()) ?? dataSet
    let logos = FakeLogoStore(folder: paths.logos)
    return AppServices(
      teams: teams, opponents: opponents, matches: matches, settings: settings, renders: renders,
      logos: logos, templates: templates, renderer: renderer,
      demoData: FakeDemoDataLoader(dataSet: demoSource, teams: teams, opponents: opponents, matches: matches),
      paths: paths,
      fixtureSource: FakeFixtureSource.scenario(
        referenceSaturday: data.referenceSaturday, logos: logos, delay: renderDelay))
  }
}
