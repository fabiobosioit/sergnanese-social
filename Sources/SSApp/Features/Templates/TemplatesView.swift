import AppKit
import SSCore
import SwiftUI
import UniformTypeIdentifiers

/// The Template screen: a grid of template cards, an import button, an inspector with the preview.
public struct TemplatesView: View {
  let app: AppModel
  @ViewState private var model: TemplatesViewModel
  @ViewState private var showInspector = true
  @ViewState private var isImporting = false
  @ViewState private var isDropTargeted = false
  @FocusState private var gridFocused: Bool

  public init(app: AppModel) {
    self.app = app
    self._model = ViewState(initialValue: TemplatesViewModel(services: app.services))
  }

  public var body: some View {
    content
      .navigationTitle(TemplatesStrings.title)
      .toolbar { toolbar }
      .inspector(isPresented: inspectorBinding) {
        TemplateInspector(model: model)
          .inspectorColumnWidth(min: 260, ideal: 320, max: 460)
      }
      .dropDestination(for: URL.self) { urls, _ in
        model.importItems(urls)
        return !urls.isEmpty
      } isTargeted: {
        isDropTargeted = $0
      }
      .overlay {
        if isDropTargeted { DropOverlay() }
      }
      .fileImporter(
        isPresented: $isImporting, allowedContentTypes: [.zip, .folder], allowsMultipleSelection: true
      ) { result in
        if case .success(let urls) = result { model.importItems(urls) }
      }
      .quickLookPreview($model.quickLookURL)
      .sheet(item: problemsBinding) { problems in
        ImportProblemsSheet(problems: problems.items) { model.importProblems = nil }
      }
      .confirmationDialog(
        model.replaceRequest.map { TemplatesStrings.replaceTitle($0.existing.manifest.name) } ?? "",
        isPresented: replaceBinding, titleVisibility: .visible
      ) {
        Button(TemplatesStrings.replace, role: .destructive) { model.confirmReplace() }
        Button(AppStrings.Common.cancel, role: .cancel) { model.cancelReplace() }
      } message: {
        if let request = model.replaceRequest {
          Text(TemplatesStrings.replaceMessage(request.existing.manifest.version, request.newName))
        }
      }
      .confirmDelete(
        model.selected.map { TemplatesStrings.deleteTitle($0.manifest.name) } ?? "",
        isPresented: $model.confirmingDelete
      ) { model.deleteSelected() }
      .confirmationDialog(
        model.selected.map { TemplatesStrings.restoreTitle($0.manifest.name) } ?? "",
        isPresented: $model.confirmingRestore, titleVisibility: .visible
      ) {
        Button(TemplatesStrings.restore, role: .destructive) { model.restoreSelected() }
        Button(AppStrings.Common.cancel, role: .cancel) {}
      } message: {
        Text(TemplatesStrings.restoreMessage)
      }
      .alert(
        TemplatesStrings.errorTitle, isPresented: errorBinding,
        actions: { Button(AppStrings.Common.ok) { model.errorMessage = nil } },
        message: { Text(model.errorMessage ?? "") }
      )
      .publishCommand(.importTemplate) { isImporting = true }
      .publishCommand(.delete, enabled: model.canDelete) { model.requestDelete() }
      .publishCommand(.quickLook, enabled: model.selected != nil) { model.openQuickLook() }
      .task {
        model.load()
        await model.loadThumbnails()
      }
      .task(id: app.dataRevision) { model.loadCandidates(weekend: app.weekend) }
      .onChange(of: model.selectedID) {
        model.previewSource = .fixture
        model.refreshPreview()
      }
      .onChange(of: model.previewSource) { model.refreshPreview() }
  }

  // MARK: Content

  @ViewBuilder
  private var content: some View {
    switch model.loadState {
    case .loading:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let message):
      ContentUnavailableView {
        Label(TemplatesStrings.loadFailedTitle, systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button(TemplatesStrings.retry) { model.load() }
      }
    case .loaded where model.templates.isEmpty:
      ContentUnavailableView {
        Label(TemplatesStrings.emptyTitle, systemImage: TemplatesStrings.placeholderSymbol)
      } description: {
        Text(TemplatesStrings.emptyDescription)
      } actions: {
        Button(TemplatesStrings.importButton) { isImporting = true }
      }
    case .loaded:
      grid
    }
  }

  private var grid: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 16)], spacing: 16) {
        ForEach(model.templates) { template in
          TemplateCard(
            template: template, thumbnail: model.thumbnails[template.id],
            isSelected: model.selectedID == template.id
          )
          .onTapGesture {
            gridFocused = true
            model.selectedID = template.id
          }
          .contextMenu { menu(for: template) }
        }
      }
      .padding(20)
    }
    .background(Color(nsColor: .controlBackgroundColor))
    .focusable()
    .focused($gridFocused)
    .focusEffectDisabled()
    .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .space]) { press in
      handle(press)
    }
  }

  private func handle(_ press: KeyPress) -> KeyPress.Result {
    let ids = model.templates.map(\.id)
    guard !ids.isEmpty else { return .ignored }
    if press.key == .space {
      guard model.selected != nil else { return .ignored }
      model.openQuickLook()
      return .handled
    }
    let step = (press.key == .leftArrow || press.key == .upArrow) ? -1 : 1
    let current = model.selectedID.flatMap { ids.firstIndex(of: $0) }
    let next = current.map { min(max($0 + step, 0), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
    model.selectedID = ids[next]
    return .handled
  }

  @ViewBuilder
  private func menu(for template: InstalledTemplate) -> some View {
    Button(TemplatesStrings.preview) {
      model.selectedID = template.id
      showInspector = true
      model.refreshPreview()
    }
    Button(TemplatesStrings.revealInFinder) {
      NSWorkspace.shared.activateFileViewerSelecting([template.folder])
    }
    Divider()
    if template.isBuiltin {
      Button(TemplatesStrings.restore) {
        model.selectedID = template.id
        model.requestRestore()
      }
    } else {
      Button(TemplatesStrings.delete, role: .destructive) {
        model.selectedID = template.id
        model.requestDelete()
      }
    }
  }

  // MARK: Toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      Link(destination: TemplatesStrings.guideURL) {
        Label(TemplatesStrings.guideLink, systemImage: "questionmark.circle")
      }
      .help(TemplatesStrings.guideLink)
      Button {
        isImporting = true
      } label: {
        Label(TemplatesStrings.importButton, systemImage: "square.and.arrow.down")
      }
      .help(TemplatesStrings.importHelp)
      Button {
        showInspector.toggle()
      } label: {
        Label(TemplatesStrings.showInspector, systemImage: "sidebar.trailing")
      }
      .help(TemplatesStrings.showInspector)
    }
  }

  // MARK: Bindings

  private var inspectorBinding: Binding<Bool> {
    Binding(get: { showInspector && model.selected != nil }, set: { showInspector = $0 })
  }

  private var problemsBinding: Binding<ProblemList?> {
    Binding(
      get: { model.importProblems.map(ProblemList.init) },
      set: { if $0 == nil { model.importProblems = nil } })
  }

  private var replaceBinding: Binding<Bool> {
    Binding(get: { model.replaceRequest != nil }, set: { if !$0 { model.cancelReplace() } })
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
  }
}

private struct ProblemList: Identifiable {
  let items: [String]
  var id: String { items.joined(separator: "\n") }
}

// MARK: - Card

private struct TemplateCard: View {
  let template: InstalledTemplate
  let thumbnail: URL?
  let isSelected: Bool

  private var manifest: TemplateManifest { template.manifest }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack {
        RoundedRectangle(cornerRadius: 6).fill(.quaternary)
        if let thumbnail {
          ThumbnailView(url: thumbnail, maxPixel: 480)
        } else {
          ProgressView().controlSize(.small)
        }
      }
      .aspectRatio(CGFloat(manifest.width) / CGFloat(manifest.height), contentMode: .fit)
      .frame(maxHeight: 240)
      .frame(maxWidth: .infinity)

      Text(manifest.name).font(.headline).lineLimit(2)
      HStack(spacing: 6) {
        Badge(TemplatesStrings.formatBadge(manifest))
        Badge(TemplatesStrings.kind(manifest.kind))
        Spacer(minLength: 0)
      }
      HStack(spacing: 6) {
        if template.isBuiltin { Badge(TemplatesStrings.builtinBadge, prominent: true) }
        Spacer(minLength: 0)
        Text(TemplatesStrings.version(manifest.version)).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .windowBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1)
    )
    .contentShape(RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(TemplatesStrings.cardLabel(template))
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }
}

private struct Badge: View {
  let text: String
  let prominent: Bool

  init(_ text: String, prominent: Bool = false) {
    self.text = text
    self.prominent = prominent
  }

  var body: some View {
    Text(text)
      .font(.caption2.weight(.medium))
      .foregroundStyle(prominent ? Color.accentColor : Color.secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background((prominent ? Color.accentColor : Color.secondary).opacity(0.15), in: Capsule())
      .lineLimit(1)
      .fixedSize()
  }
}

private struct DropOverlay: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 12)
      .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
      .background(Color.accentColor.opacity(0.08))
      .overlay {
        Label(TemplatesStrings.dropHint, systemImage: "square.and.arrow.down")
          .font(.title3)
          .padding()
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
      }
      .padding(8)
      .allowsHitTesting(false)
  }
}

// MARK: - Import problems

private struct ImportProblemsSheet: View {
  let problems: [String]
  let close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(TemplatesStrings.importFailedTitle, systemImage: "exclamationmark.triangle.fill")
        .font(.headline)
      Text(TemplatesStrings.importFailedMessage).foregroundStyle(.secondary)
      List(Array(problems.enumerated()), id: \.offset) { _, problem in
        Label(problem, systemImage: "exclamationmark.circle")
          .foregroundStyle(.primary)
      }
      .frame(minHeight: 120)
      HStack {
        Spacer()
        Button(TemplatesStrings.close, action: close)
          .keyboardShortcut(.defaultAction)
          .keyboardShortcut(.cancelAction)
      }
    }
    .padding(20)
    .frame(width: 460, height: 320)
  }
}

// MARK: - Inspector

private struct TemplateInspector: View {
  @Bindable var model: TemplatesViewModel

  var body: some View {
    if let template = model.selected {
      Form {
        previewSection(template)
        Section(TemplatesStrings.manifestSection) {
          row(TemplatesStrings.nameLabel, template.manifest.name)
          row(TemplatesStrings.idLabel, template.manifest.id)
          row(TemplatesStrings.versionLabel, template.manifest.version)
          row(TemplatesStrings.formatLabel, TemplatesStrings.formatBadge(template.manifest))
          row(TemplatesStrings.kindLabel, TemplatesStrings.kind(template.manifest.kind))
          row(TemplatesStrings.purposeLabel, TemplatesStrings.purpose(template.manifest.purpose))
          if let pageSize = template.manifest.pageSize {
            row(TemplatesStrings.pageSizeLabel, "\(pageSize)")
          }
        }
        Section(TemplatesStrings.limitsSection) {
          row(TemplatesStrings.limitTeamName, limit(template.manifest.limits.teamName))
          row(TemplatesStrings.limitVenue, limit(template.manifest.limits.venue))
          row(TemplatesStrings.limitCategory, limit(template.manifest.limits.category))
        }
        Section(TemplatesStrings.requiresSection) {
          if template.manifest.requires.isEmpty {
            Text(TemplatesStrings.requiresNone).foregroundStyle(.secondary)
          } else {
            ForEach(template.manifest.requires, id: \.self) { field in
              Text(TemplatesStrings.field(field))
            }
          }
        }
      }
      .formStyle(.grouped)
    } else {
      ContentUnavailableView(TemplatesStrings.noSelection, systemImage: TemplatesStrings.placeholderSymbol)
    }
  }

  private func limit(_ value: Int?) -> String {
    value.map(TemplatesStrings.characters) ?? TemplatesStrings.noLimit
  }

  private func row(_ title: String, _ value: String) -> some View {
    LabeledContent(title) {
      Text(value).textSelection(.enabled)
    }
  }

  @ViewBuilder
  private func previewSection(_ template: InstalledTemplate) -> some View {
    Section(TemplatesStrings.previewSection) {
      Picker(TemplatesStrings.previewSourceLabel, selection: $model.previewSource) {
        Text(TemplatesStrings.previewFixture).tag(PreviewSource.fixture)
        if template.manifest.kind == .list, !model.candidates.isEmpty {
          Text(TemplatesStrings.previewWeekend).tag(PreviewSource.weekend)
        }
        ForEach(model.candidates) { detail in
          Text(model.matchLabel(detail)).tag(PreviewSource.match(detail.id))
        }
      }
      ZStack {
        RoundedRectangle(cornerRadius: 6).fill(.quaternary)
        if let url = model.previewURL {
          ThumbnailView(url: url, maxPixel: 900)
            .onTapGesture(count: 2) { model.openQuickLook() }
        } else if model.previewFailed {
          Label(TemplatesStrings.previewFailed, systemImage: "exclamationmark.triangle")
            .font(.callout).foregroundStyle(.secondary)
        }
        if model.isGeneratingPreview {
          ProgressView().controlSize(.small)
        }
      }
      .aspectRatio(CGFloat(template.manifest.width) / CGFloat(template.manifest.height), contentMode: .fit)
      .frame(maxWidth: .infinity)
      .accessibilityLabel(TemplatesStrings.previewSection)
      Button(TemplatesStrings.openQuickLook) { model.openQuickLook() }
        .disabled(model.previewURL == nil)
    }
  }
}
