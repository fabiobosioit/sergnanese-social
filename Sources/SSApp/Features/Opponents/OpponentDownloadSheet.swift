import SSCore
import SwiftUI

/// "Scarica tutti gli avversari": progress while reading, then the review (report, possible duplicates,
/// rows), then the report of what was saved. Presented by Avversari.
struct OpponentDownloadSheet: View {
  let model: OpponentDownloadModel

  var body: some View {
    @Bindable var model = model
    VStack(spacing: 0) {
      Text(OpponentsStrings.downloadTitle)
        .font(.headline)
        .padding(12)
      Divider()
      content
      Divider()
      footer
        .padding(12)
    }
    .frame(minWidth: 760, idealWidth: 880, minHeight: 520, idealHeight: 660)
    .interactiveDismissDisabled(model.phase == .reading || model.phase == .saving)
    .alert(
      AppStrings.Errors.title,
      isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
      actions: { Button(AppStrings.Common.ok) { model.errorMessage = nil } },
      message: { Text(model.errorMessage ?? "") }
    )
  }

  // MARK: Content

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .idle:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .reading:
      reading
    case .saving:
      VStack(spacing: 12) {
        ProgressView()
        Text(OpponentsStrings.downloadSaving).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let message):
      ContentUnavailableView {
        Label(OpponentsStrings.errorTitle, systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button(OpponentsStrings.downloadRetry) { model.start() }
      }
    case .review:
      review
    case .done:
      done
    }
  }

  private var reading: some View {
    VStack(spacing: 12) {
      if let progress = model.progress {
        ProgressView(value: Double(progress.current - 1), total: Double(progress.total))
          .frame(maxWidth: 320)
        Text(OpponentsStrings.downloadReading(progress.team, current: progress.current, total: progress.total))
          .foregroundStyle(.secondary)
      } else {
        ProgressView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
  }

  private var review: some View {
    List {
      ReportSection(issues: model.readingIssues)
      if model.candidates.isEmpty {
        ContentUnavailableView {
          Label(OpponentsStrings.downloadEmptyTitle, systemImage: OpponentsStrings.placeholderSymbol)
        } description: {
          Text(OpponentsStrings.downloadEmptyDescription)
        }
        .frame(maxWidth: .infinity)
      }
      if !model.pairs.isEmpty {
        Section {
          ForEach(model.pairs) { pair in
            PairRow(pair: pair, model: model)
          }
        } header: {
          Text(OpponentsStrings.duplicatesTitle)
        } footer: {
          Text(OpponentsStrings.duplicatesHint)
        }
      }
      if !model.candidates.isEmpty {
        Section {
          ForEach(model.candidates) { candidate in
            CandidateRow(candidate: candidate, model: model)
          }
        } header: {
          ColumnHeader()
        }
      }
    }
  }

  private var done: some View {
    List {
      Section {
        if let summary = model.summary {
          Label(OpponentsStrings.created(summary.created), systemImage: "plus.circle")
          if summary.renamed > 0 { Label(OpponentsStrings.renamed(summary.renamed), systemImage: "pencil.circle") }
          if summary.aliases > 0 {
            Label(OpponentsStrings.aliases(summary.aliases), systemImage: "text.badge.plus")
          }
          Label(OpponentsStrings.logos(summary.logos), systemImage: "photo")
        }
      } header: {
        Text(OpponentsStrings.downloadDoneTitle)
      }
      ReportSection(issues: model.reportIssues)
    }
  }

  // MARK: Footer

  @ViewBuilder
  private var footer: some View {
    switch model.phase {
    case .idle, .saving:
      HStack { Spacer() }
    case .reading:
      HStack {
        Spacer()
        Button(OpponentsStrings.downloadCancel) { model.cancelReading() }
          .keyboardShortcut(.cancelAction)
      }
    case .failed:
      HStack {
        Spacer()
        Button(OpponentsStrings.downloadClose) { model.close() }
          .keyboardShortcut(.cancelAction)
      }
    case .review:
      VStack(alignment: .leading, spacing: 8) {
        if let message = model.planMessage {
          Label(message, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
          Text(OpponentsStrings.selectedCount(model.tickedCount))
            .font(.callout)
            .foregroundStyle(.secondary)
          Spacer()
          Button(OpponentsStrings.downloadCancel) { model.close() }
            .keyboardShortcut(.cancelAction)
          Button(OpponentsStrings.downloadSave) { Task { await model.save() } }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canSave)
        }
      }
    case .done:
      HStack {
        Spacer()
        Button(OpponentsStrings.downloadDone) { model.close() }
          .keyboardShortcut(.defaultAction)
      }
    }
  }
}

// MARK: - Report

/// The reading or logo issues, errors first, with the same symbols as the match import.
private struct ReportSection: View {
  let issues: [ImportIssue]

  var body: some View {
    if !issues.isEmpty {
      Section(OpponentsStrings.downloadReportTitle) {
        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
          Label {
            Text(issue.message).fixedSize(horizontal: false, vertical: true)
          } icon: {
            Image(systemName: issue.isError ? "exclamationmark.triangle.fill" : "info.circle")
              .foregroundStyle(issue.isError ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
          }
          .accessibilityLabel(
            "\(issue.isError ? OpponentsStrings.downloadReportErrors : OpponentsStrings.downloadReportInfo): \(issue.message)"
          )
        }
      }
    }
  }
}

// MARK: - Rows

private enum Column {
  static let tick: CGFloat = 22
  static let logo: CGFloat = 32
  static let state: CGFloat = 170
  static let seen: CGFloat = 250
}

private struct ColumnHeader: View {
  var body: some View {
    HStack(spacing: 10) {
      Color.clear.frame(width: Column.tick, height: 1)
      Text(OpponentsStrings.columnName).frame(maxWidth: .infinity, alignment: .leading)
      Text(OpponentsStrings.columnState).frame(width: Column.state, alignment: .leading)
      Text(OpponentsStrings.columnSeen).frame(width: Column.seen, alignment: .leading)
      Text(OpponentsStrings.columnFoundLogo).frame(width: Column.logo, alignment: .center)
    }
    .accessibilityHidden(true)
  }
}

/// One distinct name: tick, name, state, where it was seen, logo.
private struct CandidateRow: View {
  let candidate: OpponentCandidate
  let model: OpponentDownloadModel

  private var isTickable: Bool { model.isTickable(candidate) }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Toggle(
        OpponentsStrings.tickAccessibility,
        isOn: Binding(get: { model.isTicked(candidate) }, set: { model.setTicked(candidate, $0) })
      )
      .toggleStyle(.checkbox)
      .labelsHidden()
      .disabled(!isTickable)
      .help(isTickable ? "" : OpponentsStrings.presentHelp)
      .frame(width: Column.tick)

      Text(candidate.name)
        .fontWeight(.medium)
        .frame(maxWidth: .infinity, alignment: .leading)

      StateBadge(state: candidate.state)
        .frame(width: Column.state, alignment: .leading)

      VStack(alignment: .leading, spacing: 2) {
        ForEach(model.sightingLines(candidate), id: \.self) { line in
          Text(line).font(.callout).foregroundStyle(.secondary)
        }
      }
      .frame(width: Column.seen, alignment: .leading)

      LogoSymbol(logo: model.rowLogo(candidate), name: candidate.name)
        .frame(width: Column.logo)
    }
    .opacity(isTickable ? 1 : 0.55)
    .padding(.vertical, 2)
    .contextMenu {
      if isTickable {
        Button(model.isTicked(candidate) ? OpponentsStrings.untick : OpponentsStrings.tick) {
          model.setTicked(candidate, !model.isTicked(candidate))
        }
      }
    }
    .accessibilityElement(children: .contain)
  }
}

/// The existing opponent's logo, a symbol for a logo that can be downloaded, or a dash.
private struct LogoSymbol: View {
  let logo: OpponentDownloadModel.RowLogo
  let name: String

  var body: some View {
    switch logo {
    case .local(let url):
      ThumbnailView(url: url, maxPixel: 64)
        .frame(width: 24, height: 24)
        .accessibilityLabel("\(OpponentsStrings.columnFoundLogo): \(name)")
    case .available:
      Image(systemName: "photo.badge.arrow.down")
        .foregroundStyle(.secondary)
        .help(OpponentsStrings.logoAvailableHelp)
        .accessibilityLabel(OpponentsStrings.logoAvailable)
    case .none:
      Image(systemName: "minus")
        .foregroundStyle(.tertiary)
        .accessibilityLabel(OpponentsStrings.logoNone)
    }
  }
}

/// "Nuovo", "Già presente", …: a small capsule, like the match import.
private struct StateBadge: View {
  let state: OpponentCandidate.State

  private var tint: Color {
    switch state {
    case .new: .green
    case .missingLogo: .blue
    case .present: .secondary
    case .possibleDuplicate: .orange
    }
  }

  var body: some View {
    let title = OpponentDownloadModel.stateTitle(state)
    Text(title)
      .font(.caption.weight(.medium))
      .foregroundStyle(tint)
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(tint.opacity(0.15), in: Capsule())
      .accessibilityLabel(title)
  }
}

/// A possible duplicate: the two names and the three choices, with no default.
private struct PairRow: View {
  let pair: OpponentDuplicatePair
  let model: OpponentDownloadModel

  private var description: String {
    switch pair.second {
    case .candidate: OpponentsStrings.duplicateBetween(pair.firstName, pair.secondName)
    case .opponent: OpponentsStrings.duplicateWithExisting(pair.firstName, pair.secondName)
    }
  }

  var body: some View {
    let needed = model.needsChoice(pair)
    VStack(alignment: .leading, spacing: 6) {
      Text(description).fixedSize(horizontal: false, vertical: true)
      Picker(
        OpponentsStrings.choiceAccessibility,
        selection: Binding(get: { model.choice(for: pair) }, set: { model.setChoice($0, for: pair) })
      ) {
        Text(OpponentsStrings.use(pair.firstName)).tag(OpponentMergeChoice?.some(.useFirst))
        Text(OpponentsStrings.use(pair.secondName)).tag(OpponentMergeChoice?.some(.useSecond))
        Text(OpponentsStrings.keepSeparate).tag(OpponentMergeChoice?.some(.keepSeparate))
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .disabled(!needed)
      if !needed {
        Text(OpponentsStrings.duplicateNotNeeded).font(.callout).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .contain)
  }
}
