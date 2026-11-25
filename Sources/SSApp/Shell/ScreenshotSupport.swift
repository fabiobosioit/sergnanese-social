import Foundation
import SSCore
import SwiftUI

/// One view `ss-tool screenshots` renders to a PNG.
public struct ScreenshotScene {
  public let name: String
  public let size: CGSize
  public let view: AnyView
}

/// The views `ss-tool screenshots` shows: every section inside the window shell (sidebar and
/// content, no toolbar or menu bar), Settings, and the shared components.
@MainActor
public enum ScreenshotSupport {
  /// `resultServices` is a second, separate set of fake services: the result scenes give its matches
  /// scores, so the other scenes keep the unscored weekend.
  public static func scenes(services: AppServices, resultServices: AppServices? = nil) -> [ScreenshotScene] {
    var scenes: [ScreenshotScene] = AppSection.allCases.map { section in
      let model = AppModel(services: services, isDemo: true, defaults: scratchDefaults())
      model.section = section
      return ScreenshotScene(
        name: String(describing: section), size: CGSize(width: 1200, height: 760),
        view: AnyView(RootView(model: model)))
    }
    let model = AppModel(services: services, isDemo: true, defaults: scratchDefaults())
    if let resultServices { scenes += resultScenes(services: resultServices) }
    scenes.append(
      ScreenshotScene(
        name: "settings", size: CGSize(width: 520, height: 360), view: AnyView(SettingsView(app: model))))
    scenes.append(
      ScreenshotScene(
        name: "gallery", size: CGSize(width: 900, height: 640),
        view: AnyView(GalleryShowcase(services: services))))
    scenes.append(
      ScreenshotScene(
        name: "components", size: CGSize(width: 640, height: 420),
        view: AnyView(ComponentsShowcase(model: model))))
    return scenes
  }

  /// Partite on a weekend whose matches have scores (summary bar with "Riepilogo risultati") and the
  /// "Risultato" sheet, on their own fake services so the other scenes keep the unscored weekend.
  private static func resultScenes(services: AppServices) -> [ScreenshotScene] {
    let model = AppModel(services: services, isDemo: true, defaults: scratchDefaults())
    let weekend = model.weekend
    let details = (try? services.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)) ?? []
    for (offset, detail) in details.enumerated() where detail.match.status == .scheduled {
      var draft = MatchDraft(detail.match)
      draft.score = Score(us: (offset * 2) % 5, them: (offset * 3) % 4)
      draft.halfTime = Score(us: offset % 2, them: 0)
      draft.status = MatchStatus.played
      _ = try? services.matches.update(id: detail.id, with: draft)
    }
    model.section = AppSection.matches
    var scenes: [ScreenshotScene] = [
      ScreenshotScene(
        name: "matches-results", size: CGSize(width: 1200, height: 760), view: AnyView(RootView(model: model)))
    ]
    // The scenes are built once per appearance: the second time the matches are already played.
    let playable = details.filter { detail in
      let status = detail.match.status
      return status != MatchStatus.postponed && status != MatchStatus.cancelled
    }
    if let first = playable.first {
      let sheetModel = ResultModel(detail: first, app: model, defaults: scratchDefaults())
      scenes.append(
        ScreenshotScene(
          name: "result-sheet", size: CGSize(width: 520, height: 460),
          view: AnyView(ResultSheet(model: sheetModel, close: {}))))
    }
    return scenes
  }

  private static func scratchDefaults() -> UserDefaults {
    UserDefaults(suiteName: "ss.screenshots.\(UUID().uuidString)") ?? .standard
  }
}

/// `ImageGallery` with the fake renders, two images selected.
private struct GalleryShowcase: View {
  let services: AppServices
  @ViewState private var selection = GallerySelection()

  private var images: [GalleryImage] {
    ((try? services.renders.list(from: nil, to: nil)) ?? []).map { GalleryImage(record: $0) }
  }

  var body: some View {
    ImageGallery(images: images, selection: $selection)
      .onAppear {
        let ids = images.map(\.id)
        selection.click(ids[0], in: ids)
        if ids.count > 2 { selection.click(ids[2], in: ids, command: true) }
      }
  }
}

/// The small components side by side.
private struct ComponentsShowcase: View {
  let model: AppModel

  var body: some View {
    Form {
      Section("WeekendSwitcher") { WeekendSwitcher(model: model) }
      Section("StatusBadge") {
        HStack {
          ForEach(MatchStatus.allCases, id: \.self) { StatusBadge($0, showsScheduled: true) }
        }
      }
      Section("HomeAwayMarker") {
        HStack(spacing: 16) {
          HomeAwayMarker(isHome: true, showsText: true)
          HomeAwayMarker(isHome: false, showsText: true)
        }
      }
      Section("WarningLabel") {
        WarningLabel("Manca il logo di Oratorio San Gerolamo", fixTitle: "Aggiungi logo") {}
      }
      Section("LogoWell") {
        HStack(spacing: 24) {
          LogoWell(logoURL: nil, name: "Oratorio", initials: "OS", onInput: { _ in }, onRemove: {})
          LogoWell(
            logoURL: (try? FileManager.default.contentsOfDirectory(
              at: model.services.paths.logos, includingPropertiesForKeys: nil))?.first,
            name: "Esempio", initials: "ES", onInput: { _ in }, onRemove: {})
        }
      }
      Section("ValidatedField") {
        ValidatedField(
          "Nome", problems: [FieldProblem(field: .name, message: "Il nome è obbligatorio.")], field: .name
        ) {
          TextField("", text: .constant(""))
        }
      }
    }
    .formStyle(.grouped)
  }
}
