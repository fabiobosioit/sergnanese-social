import SwiftUI

/// The window content: a source-list sidebar and the selected section.
public struct RootView: View {
  @Bindable var model: AppModel
  @ViewState private var columnVisibility: NavigationSplitViewVisibility = .automatic

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      Sidebar(model: model)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
    } detail: {
      SectionContent(model: model)
        .navigationTitle(model.section.title)
    }
    .toolbar {
      if model.isDemo {
        ToolbarItem(placement: .status) {
          Label(AppStrings.demoBadge, systemImage: "testtube.2")
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(AppStrings.demoBadgeHelp)
        }
      }
    }
    .frame(minWidth: 900, minHeight: 600)
    .onChange(of: model.section) { model.persistSection() }
    .alert(
      AppStrings.Errors.title,
      isPresented: Binding(
        get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
      actions: { Button(AppStrings.Common.ok) { model.errorMessage = nil } },
      message: { Text(model.errorMessage ?? "") })
  }
}

struct Sidebar: View {
  @Bindable var model: AppModel

  var body: some View {
    List(selection: selection) {
      Section(AppStrings.sidebarWeekend) {
        ForEach(AppSection.weekendSections) { row(for: $0) }
      }
      Section(AppStrings.sidebarLibrary) {
        ForEach(AppSection.librarySections) { row(for: $0) }
      }
    }
    .listStyle(.sidebar)
  }

  /// `List` selection is optional; a click on empty space must not clear the section.
  private var selection: Binding<AppSection?> {
    Binding(
      get: { model.section },
      set: { if let section = $0 { model.section = section } })
  }

  @ViewBuilder
  private func row(for section: AppSection) -> some View {
    let label = Label(section.title, systemImage: section.symbol).tag(section)
    if section == .matches {
      label.badge(model.matchesWithWarnings)
        .accessibilityValue(
          model.matchesWithWarnings > 0 ? AppStrings.warningsBadge(model.matchesWithWarnings) : "")
    } else {
      label
    }
  }
}

/// The screen of the current section. Wave 2 tasks replace the views inside their feature folder;
/// the shell only calls `<Feature>View(app:)`.
struct SectionContent: View {
  let model: AppModel

  var body: some View {
    switch model.section {
    case .matches: MatchesView(app: model)
    case .generate: GenerateView(app: model)
    case .archive: ArchiveView(app: model)
    case .opponents: OpponentsView(app: model)
    case .teams: TeamsView(app: model)
    case .templates: TemplatesView(app: model)
    }
  }
}
