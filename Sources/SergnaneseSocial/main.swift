import SSApp
import SSCore
import SSCoreFakes
import SwiftUI

if CommandLine.arguments.contains("--smoke") {
  exit(runSmoke())
}

/// `--mock` runs on in-memory fake data. Without it the real services should come from
/// `Composition.makeServices()`, which is still a stub in this wave (T3.1 builds it), so the app
/// falls back to the fakes and says so with a "dati demo" badge in the toolbar.
@MainActor
func launchModel() -> AppModel {
  let services = AppServices.fake()
  return AppModel(services: services, isDemo: true)
}

struct SergnaneseSocialApp: App {
  @NSApplicationDelegateAdaptor(ShellDelegate.self) private var delegate
  @ViewState private var model = launchModel()

  var body: some Scene {
    ShellScenes(model: model)
  }
}

SergnaneseSocialApp.main()
