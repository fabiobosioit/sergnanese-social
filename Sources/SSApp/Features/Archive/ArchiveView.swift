import SSCore
import SwiftUI

/// Archivio: past renders grouped by weekend. The shell only calls `ArchiveView(app:)`.
public struct ArchiveView: View {
  let app: AppModel
  @ViewState private var model: ArchiveViewModel

  public init(app: AppModel) {
    self.app = app
    self._model = ViewState(initialValue: ArchiveViewModel(app: app))
  }

  public var body: some View {
    Group {
      switch model.load {
      case .loading:
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      case .failed(let message):
        ContentUnavailableView {
          Label(ArchiveStrings.loadFailedTitle, systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button(ArchiveStrings.retry) { model.reload() }
        }
      case .loaded:
        if model.isEmpty {
          ContentUnavailableView {
            Label(ArchiveStrings.emptyTitle, systemImage: ArchiveStrings.placeholderSymbol)
          } description: {
            Text(ArchiveStrings.emptyDescription)
          } actions: {
            Button(ArchiveStrings.goToGenerate) { app.open(.generate) }
          }
        } else {
          content
        }
      }
    }
    .toolbar { toolbar }
    .task(id: app.dataRevision) { model.reload() }
    .alert(
      AppStrings.Errors.title,
      isPresented: Binding(
        get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
      actions: { Button(AppStrings.Common.ok) { model.errorMessage = nil } },
      message: { Text(model.errorMessage ?? "") }
    )
    .confirmationDialog(
      ArchiveStrings.deleteTitle,
      isPresented: Binding(
        get: { !model.pendingDelete.isEmpty }, set: { if !$0 { model.cancelDelete() } }),
      titleVisibility: .visible,
      actions: {
        Button(ArchiveStrings.trashToo, role: .destructive) { model.confirmDelete(trashFiles: true) }
        Button(ArchiveStrings.keepFile) { model.confirmDelete(trashFiles: false) }
        Button(ArchiveStrings.cancel, role: .cancel) { model.cancelDelete() }
      },
      message: { Text(ArchiveStrings.deleteMessage(model.pendingDelete.count)) }
    )
    .publishCommand(.delete, enabled: !model.selection.isEmpty) {
      model.requestDelete(Array(model.selection.selected))
    }
  }

  private var content: some View {
    HStack(spacing: 0) {
      weekendList
        .frame(width: 220)
      Divider()
      VStack(spacing: 0) {
        if !model.missingVisible.isEmpty { missingBanner }
        if model.visibleRecords.isEmpty {
          ContentUnavailableView(
            ArchiveStrings.emptyFilteredTitle, systemImage: "line.3.horizontal.decrease.circle",
            description: Text(ArchiveStrings.emptyFilteredDescription))
        } else {
          ImageGallery(
            images: model.galleryImages, selection: Binding(get: { model.selection }, set: { model.selection = $0 })
          ) { targets in
            extraMenu(targets)
          }
          .onDeleteCommand {
            if !model.selection.isEmpty { model.requestDelete(Array(model.selection.selected)) }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  // MARK: Weekends

  private var weekendList: some View {
    List(
      selection: Binding(
        get: { model.selectedGroupID },
        set: { if let id = $0 { model.selectedGroupID = id } })
    ) {
      Section(ArchiveStrings.weekendsHeader) {
        Label(ArchiveStrings.allWeekends, systemImage: "photo.stack")
          .badge(model.filteredRecords.count)
          .tag(ArchiveViewModel.allGroupsID)
        ForEach(model.groups) { group in
          Label(model.weekendTitle(group), systemImage: "calendar")
            .badge(group.records.count)
            .tag(group.id)
            .accessibilityLabel("\(model.weekendTitle(group)), \(ArchiveStrings.imageCount(group.records.count))")
        }
      }
    }
    .listStyle(.sidebar)
  }

  // MARK: Missing files

  private var missingBanner: some View {
    let ids = model.missingVisible.map(\.id)
    return HStack(spacing: 8) {
      WarningLabel(ArchiveStrings.missingBanner(ids.count))
      Spacer()
      Button(ArchiveStrings.regenerateMissing) { Task { await model.regenerate(ids) } }
      Button(ArchiveStrings.removeMissing) { model.removeMissing(ids) }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.bar)
  }

  // MARK: Menus

  @ViewBuilder
  private func extraMenu(_ targets: [GalleryImage]) -> some View {
    let ids = targets.map(\.id)
    Divider()
    Button(ArchiveStrings.regenerate, systemImage: "arrow.clockwise") {
      Task { await model.regenerate(ids) }
    }
    if ids.contains(where: { model.missingIDs.contains($0) }) {
      Button(ArchiveStrings.removeMissing, systemImage: "xmark.bin") { model.removeMissing(ids) }
    }
    Button(ArchiveStrings.deleteFromArchive, systemImage: "trash", role: .destructive) {
      model.requestDelete(ids)
    }
  }

  // MARK: Toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Picker(
        ArchiveStrings.rangeMenu,
        selection: Binding(get: { model.dateRange }, set: { model.dateRange = $0 })
      ) {
        ForEach(ArchiveDateRange.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      .pickerStyle(.menu)
      .help(ArchiveStrings.rangeMenu)
    }
    ToolbarItem(placement: .primaryAction) {
      Picker(
        ArchiveStrings.templateMenu,
        selection: Binding(get: { model.templateFilter }, set: { model.templateFilter = $0 })
      ) {
        Text(ArchiveStrings.allTemplates).tag(String?.none)
        ForEach(model.templates) { Text($0.manifest.name).tag(Optional($0.id)) }
      }
      .pickerStyle(.menu)
      .help(ArchiveStrings.templateMenu)
    }
  }
}
