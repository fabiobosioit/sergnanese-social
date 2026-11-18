import Foundation
import SSCore
import SSRender

/// `ss-tool demo-render [--all] [--out <folder>]`: renders every template in `Resources/Templates/`
/// with the fixtures into `out/demo/` (or `<folder>`), serving `Resources/Fixtures/logos/` as the logos
/// folder. One PNG per template from the standard fixture; `--all` renders every fixture variant.
/// Exit code 1 when any template fails.
func runDemoRender(_ args: [String]) async -> Int32 {
  await DemoRender.run(args)
}

@MainActor
enum DemoRender {
  static func run(_ args: [String]) async -> Int32 {
    guard let resources = AppPaths.resolveResources() else {
      printError("demo-render: Resources folder not found (set SS_RESOURCES_DIR)")
      return 1
    }
    let templatesFolder = resources.appendingPathComponent("Templates", isDirectory: true)
    let fixtures = resources.appendingPathComponent("Fixtures", isDirectory: true)
    let logos = fixtures.appendingPathComponent("logos", isDirectory: true)
    var output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
      .appendingPathComponent("out/demo", isDirectory: true)
    if let index = args.firstIndex(of: "--out"), args.indices.contains(index + 1) {
      output = URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }
    let all = args.contains("--all")

    let templates = installedTemplates(in: templatesFolder)
    guard !templates.isEmpty else {
      printError("demo-render: no templates in \(templatesFolder.path)")
      return 1
    }
    do {
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    } catch {
      printError("demo-render: cannot create \(output.path)")
      return 1
    }

    let renderer = WebRenderer()
    let html = TemplateHTML()
    var failures = 0
    for template in templates {
      let manifest = template.manifest
      for fixture in fixtureNames(for: manifest.kind, all: all) {
        let name = all ? "\(manifest.id)__\(fixture).png" : "\(manifest.id).png"
        let file = output.appendingPathComponent(name)
        do {
          let context = try FixtureContexts.load(
            fixtures.appendingPathComponent("\(fixture).context.json"), for: manifest)
          let page = WebRenderer.Page(
            html: try html.render(template, context: context), templateFolder: template.folder, logosFolder: logos,
            width: manifest.width, height: manifest.height)
          let result = try await renderer.render(page)
          try result.png.write(to: file)
          let size = ExactImage.pixelSize(of: result.png).map { "\($0.width)×\($0.height)" } ?? "?"
          print("ok    \(file.path) (\(size))")
          for url in result.blockedURLs { print("      blocked request: \(url)") }
        } catch {
          failures += 1
          let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
          printError("FAIL  \(manifest.id) [\(fixture)]: \(message)")
        }
      }
    }
    return failures == 0 ? 0 : 1
  }

  /// Template folders with a valid manifest, ordered by id.
  static func installedTemplates(in folder: URL) -> [InstalledTemplate] {
    let children =
      (try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    return children.compactMap { child -> InstalledTemplate? in
      guard let data = try? Data(contentsOf: child.appendingPathComponent("manifest.json")) else { return nil }
      do {
        return InstalledTemplate(manifest: try TemplateManifest.decode(from: data), folder: child, isBuiltin: true)
      } catch {
        printError("skip  \(child.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
        return nil
      }
    }.sorted { $0.id < $1.id }
  }

  static func fixtureNames(for kind: TemplateKind, all: Bool) -> [String] {
    switch (kind, all) {
    case (.single, false): return ["single"]
    case (.list, false): return ["list"]
    case (.single, true):
      return ["single", "single-long-name", "single-no-logo", "single-away", "single-no-time", "single-goalless"]
    case (.list, true): return ["list", "list-23"]
    }
  }

  static func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
  }
}
