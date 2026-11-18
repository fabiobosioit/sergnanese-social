import AppKit
import SSCore
import SwiftUI
import UniformTypeIdentifiers

/// The Settings window (⌘,): a `TabView` of grouped `Form`s. Changes apply immediately.
public struct SettingsView: View {
  let app: AppModel
  @ViewState private var model: SettingsModel

  public init(app: AppModel) {
    self.app = app
    _model = ViewState(initialValue: SettingsModel(services: app.services))
  }

  public var body: some View {
    TabView {
      ClubTab(model: model)
        .tabItem { Label(SettingsStrings.tabClub, systemImage: "building.2") }
      ImagesTab(model: model)
        .tabItem { Label(SettingsStrings.tabImages, systemImage: "photo") }
      DataTab(app: app, model: model)
        .tabItem { Label(SettingsStrings.tabData, systemImage: "externaldrive") }
    }
    .frame(width: 520)
    .frame(minHeight: 340)
  }
}

private struct ClubTab: View {
  @Bindable var model: SettingsModel

  var body: some View {
    Form {
      field(SettingsStrings.clubName, "", $model.draft.clubName, .clubName)
      field(SettingsStrings.clubShortName, "", $model.draft.clubShortName, .clubShortName)
      field(SettingsStrings.season, SettingsStrings.seasonPrompt, $model.draft.season, .season)
      field(SettingsStrings.socialHandle, SettingsStrings.socialHandlePrompt, $model.draft.socialHandle, .socialHandle)
      field(SettingsStrings.homeVenue, "", $model.draft.homeVenue, .homeVenue)
      Text(SettingsStrings.homeVenueFooter).font(.caption).foregroundStyle(.secondary)
      if let message = model.errorMessage { ProblemText(message) }
    }
    .formStyle(.grouped)
  }

  private func field(_ title: String, _ prompt: String, _ text: Binding<String>, _ field: ValidationField)
    -> some View
  {
    ValidatedField(title, problems: model.problems, field: field) {
      TextField(title, text: text, prompt: Text(prompt))
        .labelsHidden()
        .multilineTextAlignment(.trailing)
        .onSubmit { model.commit() }
        .onChange(of: text.wrappedValue) { model.commit() }
    }
  }
}

private struct ImagesTab: View {
  @Bindable var model: SettingsModel
  @ViewState private var choosingFolder = false

  var body: some View {
    Form {
      Section {
        LabeledContent(SettingsStrings.accentColor) {
          HStack {
            ColorPicker(SettingsStrings.accentColor, selection: colorBinding, supportsOpacity: false)
              .labelsHidden()
            TextField(
              SettingsStrings.accentColorField, text: $model.draft.accentColor,
              prompt: Text(SettingsStrings.accentColorPrompt)
            )
            .labelsHidden()
            .frame(width: 90)
            .onSubmit { model.commit() }
            .onChange(of: model.draft.accentColor) { model.commit() }
            Button(SettingsStrings.resetAccent) { model.resetAccentColor() }
          }
        }
        if let message = model.problem(for: .accentColor) { ProblemText(message) }
        Text(SettingsStrings.accentFooter).font(.caption).foregroundStyle(.secondary)
      }
      Section {
        LabeledContent(SettingsStrings.outputFolder) {
          HStack {
            Label(model.outputFolder.lastPathComponent, systemImage: "folder")
              .help(model.outputFolder.path)
              .accessibilityLabel(SettingsStrings.pathLabel + " " + model.outputFolder.path)
            Button(SettingsStrings.chooseFolder) { choosingFolder = true }
          }
        }
        HStack {
          Button(SettingsStrings.showInFinder) { revealInFinder(model.outputFolder) }
          Button(SettingsStrings.resetFolder) { model.setOutputFolder(nil) }
            .disabled(model.usesDefaultOutputFolder)
        }
        if let message = model.problem(for: .outputFolder) { ProblemText(message) }
      }
    }
    .formStyle(.grouped)
    .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
      if case .success(let url) = result { model.setOutputFolder(url) }
    }
  }

  private var colorBinding: Binding<Color> {
    Binding(
      get: { Color(hex: model.effectiveAccent) },
      set: { if let hex = $0.hexString { model.setAccentColor(hex: hex) } })
  }
}

private struct DataTab: View {
  let app: AppModel
  @Bindable var model: SettingsModel
  @ViewState private var confirmRemove = false

  var body: some View {
    Form {
      Section {
        LabeledContent(SettingsStrings.dataFolder) {
          Text(model.dataFolder.path)
            .font(.callout).foregroundStyle(.secondary)
            .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
        }
        Button(SettingsStrings.showInFinder) { revealInFinder(model.dataFolder) }
        LabeledContent(SettingsStrings.lastBackup) {
          if let date = model.lastBackup {
            Text(date, format: .dateTime.day().month(.wide).year().hour().minute())
          } else {
            Text(SettingsStrings.noBackup).foregroundStyle(.secondary)
          }
        }
      }
      Section(SettingsStrings.demoData) {
        Text(model.hasDemoData ? SettingsStrings.demoLoaded : SettingsStrings.demoNotLoaded)
          .foregroundStyle(.secondary)
        HStack {
          Button(SettingsStrings.loadDemo) {
            Task {
              await app.loadDemoData()
              model.refreshDataInfo()
            }
          }
          Button(SettingsStrings.removeDemo, role: .destructive) { confirmRemove = true }
            .disabled(!model.hasDemoData)
        }
      }
      Section {
        LabeledContent(SettingsStrings.version, value: Self.versionText)
      }
      if let message = model.errorMessage { ProblemText(message) }
    }
    .formStyle(.grouped)
    .confirmDelete(
      SettingsStrings.removeDemoTitle, isPresented: $confirmRemove, message: SettingsStrings.removeDemoMessage,
      confirmTitle: SettingsStrings.removeDemo
    ) {
      model.removeDemoData()
      app.didChangeData()
    }
  }

  static var versionText: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? SettingsStrings.versionUnknown
  }
}

@MainActor
private func revealInFinder(_ url: URL) {
  try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  NSWorkspace.shared.activateFileViewerSelecting([url])
}

extension Color {
  /// `"#RRGGBB"` to an sRGB colour; black when malformed (callers pass validated values).
  init(hex: String) {
    let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    let value = UInt32(digits, radix: 16) ?? 0
    self.init(
      .sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255, opacity: 1)
  }

  /// `"#RRGGBB"` in sRGB, upper case.
  var hexString: String? {
    guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
    func byte(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
    return String(
      format: "#%02X%02X%02X", byte(color.redComponent), byte(color.greenComponent), byte(color.blueComponent))
  }
}
