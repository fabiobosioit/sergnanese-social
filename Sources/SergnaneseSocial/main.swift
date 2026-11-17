import SwiftUI

if CommandLine.arguments.contains("--smoke") {
  exit(runSmoke())
}

struct SergnaneseSocialApp: App {
  var body: some Scene {
    Window("Sergnanese Social", id: "main") {
      Color.clear.frame(minWidth: 640, minHeight: 400)
    }
  }
}

SergnaneseSocialApp.main()
