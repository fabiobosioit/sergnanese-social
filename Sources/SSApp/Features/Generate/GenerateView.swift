import SSCore
import SwiftUI

/// Genera: choices on the left, the result on the right. The shell only calls `GenerateView(app:)`.
public struct GenerateView: View {
  let app: AppModel
  @ViewState private var model: GenerateViewModel
  @ViewState private var selection = GallerySelection()

  public init(app: AppModel) {
    self.app = app
    self._model = ViewState(initialValue: GenerateViewModel(app: app))
  }

  public var body: some View {
    Group {
      switch model.load {
      case .loading:
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      case .failed(let message):
        ContentUnavailableView {
          Label(GenerateStrings.loadFailedTitle, systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button(GenerateStrings.retry) { model.reload() }
        }
      case .loaded:
        content
      }
    }
    .toolbar { toolbar }
    .task(id: reloadKey) { model.reload() }
    .alert(
      AppStrings.Errors.title,
      isPresented: Binding(
        get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
      actions: { Button(AppStrings.Common.ok) { model.errorMessage = nil } },
      message: { Text(model.errorMessage ?? "") }
    )
    .publishCommand(.generate, enabled: model.canGenerate) { model.startGenerating() }
  }

  private var reloadKey: String { "\(app.weekend.saturday.value)#\(app.dataRevision)" }

  // MARK: Layout

  private var content: some View {
    HStack(spacing: 0) {
      choices
        .frame(width: 340)
      Divider()
      result
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  // MARK: Choices

  private var choices: some View {
    VStack(spacing: 0) {
      List {
        Section {
          if model.details.isEmpty {
            noMatches
          } else {
            ForEach(model.matchRows) { matchRow($0) }
          }
        } header: {
          HStack {
            Text(GenerateStrings.matchesSection)
            Spacer()
            Button(GenerateStrings.selectAll) { model.setAllMatches(true) }
            Button(GenerateStrings.selectNone) { model.setAllMatches(false) }
          }
          .buttonStyle(.link)
        }
        Section(GenerateStrings.templatesSection) {
          if model.templates.isEmpty {
            noTemplates
          } else {
            ForEach(model.templateRows) { templateRow($0) }
          }
        }
      }
      .listStyle(.inset(alternatesRowBackgrounds: false))
      Divider()
      summary
    }
  }

  private var noMatches: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(GenerateStrings.noMatchesTitle).font(.headline)
      Text(GenerateStrings.noMatchesDescription).font(.callout).foregroundStyle(.secondary)
      Button(GenerateStrings.goToMatches) { app.open(.matches, weekend: app.weekend) }
    }
    .padding(.vertical, 4)
  }

  private var noTemplates: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(GenerateStrings.noTemplatesTitle).font(.headline)
      Text(GenerateStrings.noTemplatesDescription).font(.callout).foregroundStyle(.secondary)
      Button(GenerateStrings.goToTemplates) { app.open(.templates) }
    }
    .padding(.vertical, 4)
  }

  private func matchRow(_ row: MatchRow) -> some View {
    let match = row.detail.match
    return VStack(alignment: .leading, spacing: 4) {
      Toggle(
        isOn: Binding(get: { row.isChecked }, set: { _ in model.toggleMatch(row.id) })
      ) {
        VStack(alignment: .leading, spacing: 1) {
          Text(
            GenerateStrings.matchLabel(
              row.detail.team.shortLabel, displayName(for: row.detail.opponent, limit: nil).text)
          )
          .lineLimit(1)
          Text(rowSubtitle(row))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .toggleStyle(.checkbox)
      if row.isSkipped {
        HStack(spacing: 6) {
          StatusBadge(match.status)
          Text(GenerateStrings.skipped).font(.caption).foregroundStyle(.secondary)
        }
      }
      if !row.warnings.isEmpty {
        ForEach(Array(row.warnings.enumerated()), id: \.offset) { _, warning in
          WarningLabel(warning.message)
        }
        Button(GenerateStrings.edit) { model.edit() }
          .buttonStyle(.link)
          .font(.callout)
          .help(GenerateStrings.editHelp)
      }
    }
    .opacity(row.isSkipped && !row.isChecked ? 0.55 : 1)
    .padding(.vertical, 2)
    .contextMenu {
      Button(GenerateStrings.edit) { model.edit() }
    }
    .accessibilityElement(children: .contain)
  }

  private func rowSubtitle(_ row: MatchRow) -> String {
    let match = row.detail.match
    let day = formatDateShort(match.date)
    let time = match.time.map(\.description) ?? "—"
    let side = match.isHome ? GenerateStrings.homeMarker : GenerateStrings.awayMarker
    return "\(day), \(time), \(side)"
  }

  private func templateRow(_ row: TemplateRow) -> some View {
    let manifest = row.template.manifest
    let line =
      row.isChecked
      ? GenerateStrings.templateLine(
        name: manifest.name, images: row.imageCount, matches: row.matchCount, isSingle: row.isSingle)
      : GenerateStrings.templateIdle(
        format: manifest.format == .post ? GenerateStrings.formatPost : GenerateStrings.formatStory,
        size: "\(manifest.width) × \(manifest.height)", isSingle: row.isSingle)
    return Toggle(
      isOn: Binding(get: { row.isChecked }, set: { _ in model.toggleTemplate(row.id) })
    ) {
      VStack(alignment: .leading, spacing: 1) {
        Text(manifest.name).lineLimit(1)
        Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(2)
      }
    }
    .toggleStyle(.checkbox)
    .padding(.vertical, 2)
  }

  // MARK: Summary

  private var summary: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(model.totalImages == 0 ? GenerateStrings.noImages : GenerateStrings.totalImages(model.totalImages))
        .font(.headline)
      if model.planWarnings.isEmpty {
        if model.totalImages > 0 {
          Label(GenerateStrings.noWarnings, systemImage: "checkmark.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      } else {
        Label(GenerateStrings.warningsCount(model.planWarnings.count), systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(.secondary)
          .symbolRenderingMode(.multicolor)
      }
      if let reason = model.disabledReason {
        Text(reason).font(.callout).foregroundStyle(.secondary)
      }
      if let error = model.planError {
        Text(error).font(.callout).foregroundStyle(.red)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .accessibilityElement(children: .combine)
  }

  // MARK: Result

  private var result: some View {
    VStack(spacing: 0) {
      if case .running(let done, let total) = model.run {
        runProgress(done: done, total: total)
        Divider()
      } else if let status = statusText {
        HStack {
          Text(status).font(.callout).foregroundStyle(.secondary)
          Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        Divider()
      }
      if !model.failures.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text(GenerateStrings.failuresTitle).font(.headline)
          ForEach(model.failures, id: \.self) { WarningLabel($0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        Divider()
      }
      ImageGallery(images: model.galleryImages, selection: $selection) { targets in
        Button(GenerateStrings.regenerate, systemImage: "arrow.clockwise") {
          let ids = targets.map(\.id)
          Task { await model.regenerate(ids) }
        }
      }
    }
  }

  private var statusText: String? {
    switch model.run {
    case .finished(let produced, let failed): GenerateStrings.finished(produced: produced, failed: failed)
    case .cancelled(let produced): GenerateStrings.cancelled(produced: produced)
    default: nil
    }
  }

  private func runProgress(done: Int, total: Int) -> some View {
    HStack(spacing: 12) {
      ProgressView(value: Double(done), total: Double(max(total, 1)))
      Text(total == 0 ? GenerateStrings.preparing : GenerateStrings.progress(done: done, total: total))
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
      Button(GenerateStrings.cancel) { model.cancel() }
        .keyboardShortcut(.cancelAction)
    }
    .padding(12)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(GenerateStrings.progress(done: done, total: total))
  }

  // MARK: Toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      WeekendSwitcher(model: app)
    }
    ToolbarItem(placement: .primaryAction) {
      if model.run.isRunning {
        Button(GenerateStrings.cancel, systemImage: "xmark.circle") { model.cancel() }
          .help(GenerateStrings.cancel)
      } else {
        ShareLink(items: model.resultURLs) {
          Label(GenerateStrings.shareAll, systemImage: "square.and.arrow.up")
        }
        .disabled(model.results.isEmpty)
        .help(GenerateStrings.shareAll)
      }
    }
    ToolbarItem(placement: .primaryAction) {
      Button(GenerateStrings.generate, systemImage: "wand.and.stars") { model.startGenerating() }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!model.canGenerate)
        .help(model.disabledReason ?? GenerateStrings.generateHelp)
    }
  }
}
