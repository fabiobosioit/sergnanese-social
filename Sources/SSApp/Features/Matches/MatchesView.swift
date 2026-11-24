import SSCore
import SwiftUI

/// Partite: check and fix the weekend's matches before generating. The shell only calls
/// `MatchesView(app:)`.
public struct MatchesView: View {
  let app: AppModel
  @ViewState private var model: MatchesViewModel
  @ViewState private var isInspectorShown = false
  @ViewState private var importModel: ImportModel
  @ViewState private var csiLauncher: CSIImportLauncher
  @ViewState private var pdfLauncher: PDFImportLauncher
  @Environment(\.openWindow) private var openWindow
  @FocusState private var searchFocused: Bool
  @SceneStorage("matches.scope") private var storedScope = MatchesScope.weekend.rawValue

  public init(app: AppModel) {
    self.app = app
    _model = ViewState(initialValue: MatchesViewModel(app: app))
    let importModel = ImportModel(services: app.services)
    importModel.onDataChanged = { [weak app] in app?.didChangeData() }
    _importModel = ViewState(initialValue: importModel)
    _csiLauncher = ViewState(initialValue: CSIImportLauncher(services: app.services))
    let pdfLauncher = PDFImportLauncher(services: app.services)
    pdfLauncher.onDataChanged = { [weak app] in app?.didChangeData() }
    _pdfLauncher = ViewState(initialValue: pdfLauncher)
  }

  public var body: some View {
    @Bindable var vm = model
    @Bindable var importer = importModel
    @Bindable var csi = csiLauncher
    @Bindable var pdf = pdfLauncher
    content(vm)
      .safeAreaInset(edge: .bottom, spacing: 0) { summaryBar }
      .inspector(isPresented: $isInspectorShown) {
        inspector
          .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
      }
      .searchable(text: $vm.searchText, placement: .toolbar, prompt: MatchesStrings.searchPrompt)
      .searchFocused($searchFocused)
      .toolbar { toolbar(vm) }
      .sheet(
        isPresented: Binding(
          get: { vm.newMatchForm != nil },
          set: { if !$0 { vm.newMatchForm = nil } })
      ) {
        if let initial = vm.newMatchForm {
          NewMatchSheet(initial: initial, model: vm)
        }
      }
      .sheet(
        isPresented: Binding(get: { importer.isPresented }, set: { if !$0 { importer.dismiss() } })
      ) {
        ImportSheet(model: importer)
      }
      .sheet(isPresented: $csi.isPickerPresented) {
        CSITeamPickerSheet(launcher: csi) { openWindow(id: CSIImportLauncher.windowID, value: $0) }
      }
      .sheet(isPresented: $pdf.isPickerPresented) {
        PDFTeamPickerSheet(launcher: pdf)
      }
      .sheet(
        isPresented: Binding(get: { pdf.model?.isPresented ?? false }, set: { if !$0 { pdf.dismissModel() } })
      ) {
        if let pdfModel = pdf.model { ImportSheet(model: pdfModel) }
      }
      .fileImporter(isPresented: $pdf.isFileImporterPresented, allowedContentTypes: [.pdf]) { result in
        if case .success(let url) = result { Task { await pdf.begin(url: url) } }
      }
      .dropDestination(for: URL.self) { urls, _ in pdf.handleDrop(urls) }
      .overlay { if pdf.isReading { readingOverlay } }
      .confirmDelete(vm.deleteTitle, isPresented: $vm.isConfirmingDelete, onConfirm: vm.confirmDelete)
      .onAppear {
        vm.scope = MatchesScope(rawValue: storedScope) ?? .weekend
        vm.reload()
        importer.refreshAvailability()
        csi.refresh()
        pdf.refresh()
      }
      .onChange(of: app.weekend) { vm.reload() }
      .onChange(of: vm.scope) { storedScope = vm.scope.rawValue }
      .onChange(of: app.dataRevision) {
        vm.reload()
        importer.refreshAvailability()
        csi.refresh()
        pdf.refresh()
      }
      .onChange(of: vm.selection) { isInspectorShown = vm.selection.count == 1 }
      .publishCommand(.newMatch) { vm.beginNewMatch() }
      .publishCommand(.duplicate, enabled: !vm.selection.isEmpty) { vm.duplicate(vm.selection) }
      .publishCommand(.delete, enabled: !vm.selection.isEmpty) { vm.requestDelete(vm.selection) }
      .publishCommand(.generate) { vm.openGenerate() }
      .publishCommand(.find) { searchFocused = true }
      .publishCommand(.importTuttocampo, enabled: importer.canStart) { importer.present() }
      .publishCommand(.importCSI, enabled: csi.canStart) { startCSIImport() }
      .publishCommand(.importPDF, enabled: pdf.canStart) { pdf.chooseFile() }
  }

  private var readingOverlay: some View {
    VStack(spacing: 8) {
      ProgressView()
      Text(ImportStrings.readingPDF).foregroundStyle(.secondary)
    }
    .padding(20)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
  }

  /// One team with a CSI page: opens its browser window; several: asks which one.
  private func startCSIImport() {
    csiLauncher.begin { openWindow(id: CSIImportLauncher.windowID, value: $0) }
  }

  // MARK: Content

  @ViewBuilder
  private func content(_ vm: MatchesViewModel) -> some View {
    if let error = vm.loadError {
      ContentUnavailableView {
        Label(MatchesStrings.loadErrorTitle, systemImage: "exclamationmark.triangle")
      } description: {
        Text(error)
      } actions: {
        Button(MatchesStrings.retry) { vm.reload() }
      }
    } else if vm.details.isEmpty {
      emptyWeekend(vm)
    } else if vm.visibleMatches.isEmpty {
      ContentUnavailableView {
        Label(MatchesStrings.noResultsTitle, systemImage: "magnifyingglass")
      } description: {
        Text(MatchesStrings.noResultsDescription)
      } actions: {
        Button(MatchesStrings.filterReset) { vm.resetFilters() }
      }
    } else {
      table(vm)
    }
  }

  private func emptyWeekend(_ vm: MatchesViewModel) -> some View {
    ContentUnavailableView {
      Label(
        vm.scope == .all ? MatchesStrings.emptyAllTitle : MatchesStrings.emptyTitle,
        systemImage: MatchesStrings.placeholderSymbol)
    } description: {
      Text(vm.scope == .all ? MatchesStrings.emptyAllDescription : MatchesStrings.emptyDescription)
    } actions: {
      Button(MatchesStrings.addMatch) { vm.beginNewMatch() }
        .buttonStyle(.borderedProminent)
      if vm.databaseIsEmpty {
        Button(MatchesStrings.loadDemo) { Task { await vm.loadDemoData() } }
      }
    }
  }

  private func table(_ vm: MatchesViewModel) -> some View {
    @Bindable var vm = vm
    return Table(of: MatchDetail.self, selection: $vm.selection) {
      TableColumn(MatchesStrings.columnTime) { detail in
        Text(detail.match.time?.value ?? MatchesStrings.noTime)
          .monospacedDigit()
          .foregroundStyle(detail.match.time == nil ? .secondary : .primary)
          .accessibilityLabel(vm.rowSentence(for: detail))
      }
      .width(min: 48, ideal: 56, max: 72)

      TableColumn(MatchesStrings.columnTeam) { detail in
        Text(detail.team.shortLabel).accessibilityHidden(true)
      }
      .width(min: 70, ideal: 90)

      TableColumn(MatchesStrings.columnHomeAway) { detail in
        HomeAwayMarker(isHome: detail.match.isHome).accessibilityHidden(true)
      }
      .width(min: 72, ideal: 84, max: 100)

      TableColumn(MatchesStrings.columnOpponent) { detail in
        OpponentCell(detail: detail, model: vm).accessibilityHidden(true)
      }
      .width(min: 140, ideal: 200)

      TableColumn(MatchesStrings.columnVenue) { detail in
        Text(detail.match.venue)
          .lineLimit(1)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      .width(min: 90, ideal: 130)

      TableColumn(MatchesStrings.columnRound) { detail in
        Text(detail.match.round.map { String($0) } ?? "")
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      .width(min: 40, ideal: 60, max: 80)

      TableColumn(MatchesStrings.columnStatus) { detail in
        StatusBadge(detail.match.status).accessibilityHidden(true)
      }
      .width(min: 70, ideal: 90, max: 110)

      TableColumn(MatchesStrings.columnWarnings) { detail in
        WarningsCell(warnings: vm.warnings(for: detail)).accessibilityHidden(true)
      }
      .width(min: 44, ideal: 56, max: 80)

      TableColumn(MatchesStrings.columnFlags) { detail in
        FlagsCell(match: detail.match).accessibilityHidden(true)
      }
      .width(min: 40, ideal: 56, max: 80)
    } rows: {
      ForEach(vm.daySections) { section in
        Section(section.title) {
          ForEach(section.matches) { TableRow($0) }
        }
      }
    }
    .contextMenu(forSelectionType: MatchDetail.ID.self) { ids in
      contextMenu(for: ids, vm)
    } primaryAction: { ids in
      vm.selection = ids
      isInspectorShown = ids.count == 1
    }
    .onDeleteCommand { vm.requestDelete(vm.selection) }
  }

  // MARK: Context menu

  @ViewBuilder
  private func contextMenu(for ids: Set<EntityID>, _ vm: MatchesViewModel) -> some View {
    if !ids.isEmpty {
      if ids.count == 1 {
        Button(MatchesStrings.edit, systemImage: "pencil") {
          vm.selection = ids
          isInspectorShown = true
        }
      }
      Button(MatchesStrings.duplicate, systemImage: "plus.square.on.square") { vm.duplicate(ids) }
        .keyboardShortcut("d", modifiers: .command)
      Button(
        vm.shouldLock(ids) ? MatchesStrings.lock : MatchesStrings.unlock,
        systemImage: vm.shouldLock(ids) ? "lock" : "lock.open"
      ) { vm.toggleLock(ids) }
      Button(MatchesStrings.postpone, systemImage: "calendar.badge.clock") { vm.postpone(ids) }
      Divider()
      Button(MatchesStrings.delete, systemImage: "trash", role: .destructive) { vm.requestDelete(ids) }
    }
  }

  // MARK: Inspector

  @ViewBuilder
  private var inspector: some View {
    if let detail = model.singleSelected {
      MatchInspector(detail: detail, model: model)
        .id(detail.id)
    } else {
      ContentUnavailableView(
        MatchesStrings.nothingSelected, systemImage: "sidebar.trailing",
        description: Text(MatchesStrings.nothingSelectedDescription))
    }
  }

  // MARK: Toolbar and summary

  @ToolbarContentBuilder
  private func toolbar(_ vm: MatchesViewModel) -> some ToolbarContent {
    @Bindable var vm = vm
    ToolbarItem(placement: .navigation) {
      WeekendSwitcher(model: app)
        .disabled(vm.scope == .all)
        .help(vm.scope == .all ? MatchesStrings.switcherDisabledHelp : "")
    }
    ToolbarItem(placement: .principal) {
      Picker(MatchesStrings.scopePicker, selection: $vm.scope) {
        ForEach(MatchesScope.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)
      .help(MatchesStrings.scopeHelp)
    }
    ToolbarItem {
      Button {
        vm.beginNewMatch()
      } label: {
        Label(MatchesStrings.add, systemImage: "plus")
      }
      .help(MatchesStrings.addHelp)
    }
    ToolbarItem {
      Button {
        importModel.present()
      } label: {
        Label(AppStrings.Menu.importTuttocampo, systemImage: "arrow.down.circle")
      }
      .disabled(!importModel.canStart)
      .help(importModel.unavailableReason ?? ImportStrings.toolbarHelp)
    }
    ToolbarItem {
      Button {
        startCSIImport()
      } label: {
        Label(AppStrings.Menu.importCSI, systemImage: "globe")
      }
      .disabled(!csiLauncher.canStart)
      .help(csiLauncher.unavailableReason ?? ImportStrings.csiToolbarHelp)
    }
    ToolbarItem {
      Button {
        pdfLauncher.chooseFile()
      } label: {
        Label(AppStrings.Menu.importPDF, systemImage: "doc.richtext")
      }
      .disabled(!pdfLauncher.canStart)
      .help(pdfLauncher.unavailableReason ?? ImportStrings.pdfToolbarHelp)
    }
    ToolbarItem {
      Menu {
        Picker(MatchesStrings.filterTeam, selection: $vm.teamFilter) {
          Text(MatchesStrings.filterAll).tag(EntityID?.none)
          ForEach(vm.teams) { Text($0.name).tag(EntityID?.some($0.id)) }
        }
        Picker(MatchesStrings.filterStatus, selection: $vm.statusFilter) {
          Text(MatchesStrings.filterAll).tag(MatchStatus?.none)
          ForEach(MatchStatus.allCases, id: \.self) {
            Text(StatusBadge.title(for: $0)).tag(MatchStatus?.some($0))
          }
        }
        if vm.isFiltering {
          Divider()
          Button(MatchesStrings.filterReset) { vm.resetFilters() }
        }
      } label: {
        Label(
          MatchesStrings.filter,
          systemImage: vm.teamFilter != nil || vm.statusFilter != nil
            ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
      }
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        vm.openGenerate()
      } label: {
        Label(MatchesStrings.generate, systemImage: "wand.and.stars")
      }
      .buttonStyle(.borderedProminent)
      .help(MatchesStrings.generateHelp)
    }
  }

  @ViewBuilder
  private var summaryBar: some View {
    if model.loadError == nil, !model.details.isEmpty {
      HStack {
        Text(model.summary)
          .font(.callout)
          .foregroundStyle(.secondary)
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(.bar)
    }
  }
}

// MARK: - Cells

/// Opponent name with a small logo (or initials when there is none).
private struct OpponentCell: View {
  let detail: MatchDetail
  let model: MatchesViewModel

  var body: some View {
    HStack(spacing: 8) {
      logo
        .frame(width: 22, height: 22)
      Text(detail.opponent.name)
        .lineLimit(1)
        .truncationMode(.tail)
    }
  }

  @ViewBuilder
  private var logo: some View {
    if let file = detail.opponent.logoFile {
      ThumbnailView(url: model.app.services.logos.url(for: file), maxPixel: 64)
    } else {
      Text(initials(detail.opponent.name))
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 22, height: 22)
        .background(.quaternary, in: Circle())
    }
  }
}

private struct WarningsCell: View {
  let warnings: [RenderWarning]

  var body: some View {
    if !warnings.isEmpty {
      HStack(spacing: 3) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        Text("\(warnings.count)").monospacedDigit().foregroundStyle(.secondary)
      }
      .help(warnings.map(\.message).joined(separator: "\n"))
    }
  }
}

/// Lock and source as small icons, each with a help text and an accessibility label.
private struct FlagsCell: View {
  let match: Match

  var body: some View {
    HStack(spacing: 6) {
      if match.isLocked {
        Image(systemName: "lock.fill")
          .help(MatchesStrings.lockedHelp)
          .accessibilityLabel(MatchesStrings.locked)
      }
      if match.source != .manual {
        Image(systemName: sourceSymbol)
          .help(MatchesViewModel.sourceTitle(match.source))
          .accessibilityLabel(MatchesViewModel.sourceTitle(match.source))
      }
    }
    .foregroundStyle(.secondary)
  }

  private var sourceSymbol: String {
    switch match.source {
    case .manual: "hand.point.up.left"
    case .seed: "testtube.2"
    case .csv: "tablecells"
    case .scrape: "globe"
    case .pdf: "doc.richtext"
    }
  }
}
