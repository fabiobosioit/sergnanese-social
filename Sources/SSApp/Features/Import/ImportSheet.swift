import SSCore
import SwiftUI

/// "Importa da Tuttocampo": progress while reading, then the report and the staging list, then the
/// summary. Presented by Partite.
struct ImportSheet: View {
  let model: ImportModel

  var body: some View {
    @Bindable var model = model
    Group {
      if model.phase == .choosing {
        TuttocampoScopeSheet(model: model)
      } else {
        VStack(spacing: 0) {
          Text(model.title)
            .font(.headline)
            .padding(12)
          Divider()
          content
          Divider()
          footer
            .padding(12)
        }
        .frame(minWidth: 720, idealWidth: 840, minHeight: 520, idealHeight: 640)
      }
    }
    .interactiveDismissDisabled(model.phase == .fetching || model.phase == .committing)
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
    case .idle, .choosing:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .fetching:
      fetching
    case .committing:
      VStack(spacing: 12) {
        ProgressView()
        Text(ImportStrings.importing).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let message):
      ContentUnavailableView {
        Label(ImportStrings.loadErrorTitle, systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button(ImportStrings.retry) { model.start() }
      }
    case .review:
      review
    case .done:
      done
    }
  }

  private var fetching: some View {
    VStack(spacing: 12) {
      if let progress = model.progress, model.isSeasonRun {
        seasonProgress(progress)
      } else if let progress = model.progress {
        ProgressView(value: Double(progress.current - 1), total: Double(progress.total))
          .frame(maxWidth: 320)
        Text(ImportStrings.reading(progress.team, current: progress.current, total: progress.total))
          .foregroundStyle(.secondary)
      } else {
        ProgressView()
        if model.isCSI { Text(ImportStrings.readingPage).foregroundStyle(.secondary) }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
  }

  /// "Squadra 2 di 8 · Giornata 14 di 30", the team's name, a bar from the pages read.
  private func seasonProgress(_ progress: ImportModel.Progress) -> some View {
    VStack(spacing: 8) {
      Text(progress.team).font(.headline)
      if let page = model.seasonProgress, let total = page.pagesTotal {
        ProgressView(value: Double(min(page.pagesRead, total)), total: Double(total))
          .frame(maxWidth: 320)
      } else {
        ProgressView().progressViewStyle(.linear).frame(maxWidth: 320)
      }
      Text(
        ImportStrings.seasonReading(
          team: progress.current, of: progress.total, matchday: model.seasonProgress?.matchday ?? 1,
          last: model.seasonProgress?.lastMatchday)
      )
      .foregroundStyle(.secondary)
      Text(ImportStrings.seasonPages(model.runPagesRead)).font(.callout).foregroundStyle(.tertiary)
    }
    .accessibilityElement(children: .combine)
  }

  private var review: some View {
    VStack(spacing: 0) {
      if model.isSeasonRun { seasonBar }
      if let counts = model.matchCountsText {
        Text(counts)
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
        Divider()
      }
      reviewList
    }
  }

  /// The header line of a season review, the team filter and "Seleziona tutte / nessuna".
  private var seasonBar: some View {
    VStack(spacing: 6) {
      if let text = model.seasonSummaryText {
        Text(text)
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack {
        Picker(ImportStrings.filterLabel, selection: Bindable(model).teamFilter) {
          Text(ImportStrings.filterAll).tag(String?.none)
          ForEach(model.filterTeams) { Text($0.name).tag(String?.some($0.id)) }
        }
        .fixedSize()
        Spacer()
        Button(ImportStrings.selectAll) { model.setAllVisibleTicked(true) }
        Button(ImportStrings.selectNone) { model.setAllVisibleTicked(false) }
      }
      .controlSize(.small)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .overlay(alignment: .bottom) { Divider() }
  }

  private var reviewList: some View {
    List {
      if model.wasCancelled {
        Label(
          model.isSeasonRun ? ImportStrings.cancelledSeasonNote : ImportStrings.cancelledNote,
          systemImage: ImportStrings.infoSymbol
        )
        .foregroundStyle(.secondary)
      }
      reportSection
      if model.candidates.isEmpty && model.showsEmptyState {
        ContentUnavailableView {
          Label(ImportStrings.emptyTitle, systemImage: "calendar.badge.exclamationmark")
        } description: {
          Text(model.emptyDescription)
        }
        .frame(maxWidth: .infinity)
      }
      ForEach(model.sections) { section in
        Section {
          if !model.isCollapsed(section) {
            ForEach(section.candidates) { candidate in
              ImportRow(candidate: candidate, model: model)
            }
          }
        } header: {
          sectionHeader(section)
        }
      }
    }
  }

  @ViewBuilder
  private func sectionHeader(_ section: ImportSection) -> some View {
    if model.isCollapsible(section) {
      let collapsed = model.isCollapsed(section)
      Button {
        model.toggleCollapsed(section)
      } label: {
        HStack(spacing: 6) {
          Image(systemName: collapsed ? "chevron.right" : "chevron.down")
            .imageScale(.small)
            .frame(width: 10)
          Text(section.title)
          if collapsed {
            Text(ImportStrings.weekendRows(section.candidates.count)).foregroundStyle(.secondary)
          }
          Spacer()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(section.title)
      .accessibilityHint(collapsed ? ImportStrings.expandWeekend : ImportStrings.collapseWeekend)
    } else {
      Text(section.title)
    }
  }

  private var done: some View {
    List {
      Section {
        Label(model.summaryText ?? "", systemImage: "checkmark.circle")
          .font(.headline)
      } header: {
        Text(ImportStrings.doneTitle)
      }
      reportSection
    }
  }

  @ViewBuilder
  private var reportSection: some View {
    if !model.issues.isEmpty || !model.notes.isEmpty {
      Section(ImportStrings.reportTitle) {
        ForEach(model.notes, id: \.self) { note in
          Label {
            Text(note).fixedSize(horizontal: false, vertical: true)
          } icon: {
            Image(systemName: ImportStrings.errorSymbol).foregroundStyle(.yellow)
          }
        }
        ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in
          Label {
            Text(issue.message).fixedSize(horizontal: false, vertical: true)
          } icon: {
            Image(systemName: issue.isError ? ImportStrings.errorSymbol : ImportStrings.infoSymbol)
              .foregroundStyle(issue.isError ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
          }
          .accessibilityLabel(
            "\(issue.isError ? ImportStrings.errorAccessibility : ImportStrings.infoAccessibility): \(issue.message)")
        }
      }
    }
  }

  // MARK: Footer

  @ViewBuilder
  private var footer: some View {
    switch model.phase {
    case .idle, .committing, .choosing:
      HStack { Spacer() }
    case .fetching:
      HStack {
        Spacer()
        Button(ImportStrings.cancel) { model.cancelFetch() }
          .keyboardShortcut(.cancelAction)
      }
    case .failed:
      HStack {
        Spacer()
        Button(ImportStrings.close) { model.dismiss() }
          .keyboardShortcut(.cancelAction)
      }
    case .review:
      HStack {
        Text(model.selectionText)
          .font(.callout)
          .foregroundStyle(.secondary)
        Spacer()
        Button(AppStrings.Common.cancel) { model.dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(ImportStrings.importAction) { Task { await model.commit() } }
          .keyboardShortcut(.defaultAction)
          .disabled(!model.canImport)
      }
    case .done:
      HStack {
        Spacer()
        Button(ImportStrings.done) { model.dismiss() }
          .keyboardShortcut(.defaultAction)
      }
    }
  }
}

// MARK: - Row

/// One staged match: tick, team, date, home/away, opponent, state; below it what changes, what needs
/// review, the venue to complete and the logo option.
private struct ImportRow: View {
  let candidate: ImportCandidate
  let model: ImportModel

  @ViewState private var isLinking = false

  private var isTickable: Bool { ImportModel.isTickable(candidate) }
  private var opponentName: String { candidate.opponent?.name ?? candidate.fixture.opponentName }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Toggle(
        ImportStrings.tickAccessibility,
        isOn: Binding(get: { model.isTicked(candidate) }, set: { model.setTicked(candidate, $0) })
      )
      .toggleStyle(.checkbox)
      .labelsHidden()
      .disabled(!isTickable)
      .help(tickHelp)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 10) {
          Text(candidate.team.name).fontWeight(.medium)
          Text("\(formatDateShort(candidate.fixture.date)) \(candidate.fixture.time?.value ?? "")")
            .monospacedDigit()
            .foregroundStyle(.secondary)
          HomeAwayMarker(isHome: candidate.fixture.isHome, showsText: true)
          Text(opponentName).lineLimit(1).truncationMode(.tail)
          Spacer()
          StateBadge(state: candidate.state)
        }
        ForEach(model.changes(for: candidate), id: \.self) { change in
          Text(change).font(.callout).foregroundStyle(.secondary)
        }
        if candidate.opponentMatch == .proposed, let opponent = candidate.opponent {
          proposalLine(opponent)
        } else if model.canChangeOpponent(candidate) {
          Button(ImportStrings.changeOpponentAction) { isLinking = true }
            .buttonStyle(.link)
            .controlSize(.small)
            .accessibilityLabel(ImportStrings.changeOpponentAccessibility(opponentName))
        }
        if candidate.state == .needsReview { reviewSection }
        if candidate.isVenueMissing && isTickable { venueField }
        if isTickable, let opponent = candidate.opponent, opponent.logoFile != nil { logoToggle(opponent) }
      }
    }
    .padding(.vertical, 2)
    .popover(isPresented: $isLinking, arrowEdge: .bottom) {
      OpponentLinkPicker(candidate: candidate, model: model) { isLinking = false }
    }
    .contextMenu { contextMenu }
    .accessibilityElement(children: .contain)
  }

  /// "Proposto" tag (symbol and colour, read as "Abbinamento proposto"), the sentence and the two buttons.
  private func proposalLine(_ opponent: Opponent) -> some View {
    HStack(spacing: 8) {
      Label(ImportStrings.proposedTag, systemImage: ImportStrings.proposedSymbol)
        .font(.caption.weight(.medium))
        .foregroundStyle(.indigo)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.indigo.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ImportStrings.proposedAccessibility)
      Text(ImportStrings.proposedLine(opponent.name))
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
      Button(ImportStrings.confirm) { model.confirm(candidate) }
        .help(ImportStrings.confirmHelp)
      Button(ImportStrings.change) { isLinking = true }
    }
    .controlSize(.small)
  }

  private var tickHelp: String {
    switch candidate.state {
    case .unchanged: ImportStrings.unchangedHelp
    case .locked: ImportStrings.lockedHelp
    default: ""
    }
  }

  @ViewBuilder
  private var reviewSection: some View {
    ForEach(candidate.reviewMessages, id: \.self) { message in
      Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    if candidate.reviewReasons.contains(.unknownStatus) {
      Text(ImportStrings.unknownStatusNote).font(.callout).foregroundStyle(.secondary)
    }
    if candidate.reviewReasons.contains(where: { $0 == .opponentNotFound || $0 == .opponentAmbiguous }) {
      HStack {
        if candidate.reviewReasons.contains(.opponentNotFound) {
          Button(ImportStrings.createOpponent) { model.createOpponent(for: candidate) }
        }
        Button(ImportStrings.linkOpponent) { isLinking = true }
      }
      .controlSize(.small)
    }
  }

  private var venueField: some View {
    TextField(
      ImportStrings.venueField,
      text: Binding(get: { model.venue(for: candidate) }, set: { model.setVenue($0, for: candidate) }),
      prompt: Text(ImportStrings.venuePrompt)
    )
    .controlSize(.small)
    .frame(maxWidth: 360)
  }

  private func logoToggle(_ opponent: Opponent) -> some View {
    Toggle(
      ImportStrings.replaceLogo,
      isOn: Binding(
        get: { model.replaceLogo.contains(opponent.id) }, set: { model.setReplaceLogo(opponent, $0) })
    )
    .controlSize(.small)
    .help(ImportStrings.replaceLogoHelp)
  }

  @ViewBuilder
  private var contextMenu: some View {
    if isTickable {
      Button(model.isTicked(candidate) ? ImportStrings.untick : ImportStrings.tick) {
        model.setTicked(candidate, !model.isTicked(candidate))
      }
    }
    if candidate.state == .needsReview, candidate.reviewReasons.contains(.opponentNotFound) {
      Button(ImportStrings.createOpponent) { model.createOpponent(for: candidate) }
    }
    if candidate.state == .needsReview,
      candidate.reviewReasons.contains(where: { $0 == .opponentNotFound || $0 == .opponentAmbiguous })
    {
      Button(ImportStrings.linkOpponent) { isLinking = true }
    }
    if candidate.opponentMatch == .proposed {
      Button(ImportStrings.confirm) { model.confirm(candidate) }
    }
    if model.canChangeOpponent(candidate) {
      Button(ImportStrings.changeOpponentAction) { isLinking = true }
    }
  }
}

/// "Nuova", "Modificata", …: a small capsule, like `StatusBadge`.
private struct StateBadge: View {
  let state: ImportCandidate.State

  private var title: String {
    switch state {
    case .new: ImportStrings.stateNew
    case .changed: ImportStrings.stateChanged
    case .unchanged: ImportStrings.stateUnchanged
    case .locked: ImportStrings.stateLocked
    case .needsReview: ImportStrings.stateNeedsReview
    }
  }

  private var tint: Color {
    switch state {
    case .new: .green
    case .changed: .blue
    case .unchanged, .locked: .secondary
    case .needsReview: .orange
    }
  }

  var body: some View {
    HStack(spacing: 3) {
      if state == .locked { Image(systemName: "lock.fill").imageScale(.small) }
      Text(title)
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(tint)
    .padding(.horizontal, 7)
    .padding(.vertical, 2)
    .background(tint.opacity(0.15), in: Capsule())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
  }
}

/// "Collega a esistente…" and "Cambia avversario…": a searchable list of opponents in a popover. Without a search
/// the proposals come first, then every other opponent; "Crea nuovo" is always at the bottom.
private struct OpponentLinkPicker: View {
  let candidate: ImportCandidate
  let model: ImportModel
  let onDone: () -> Void

  @ViewState private var query = ""

  var body: some View {
    let content = model.pickerContent(for: candidate, matching: query)
    VStack(alignment: .leading, spacing: 8) {
      Text(ImportStrings.linkTitle(candidate.fixture.opponentName)).font(.headline)
      Text(candidate.opponent == nil ? model.linkMessage : ImportStrings.changeMessage)
        .font(.callout).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      TextField(ImportStrings.linkSearch, text: $query, prompt: Text(ImportStrings.linkSearch))
        .textFieldStyle(.roundedBorder)
      List {
        if content.proposed.isEmpty {
          ForEach(content.others) { choice($0) }
        } else {
          Section(ImportStrings.pickerProposed) { ForEach(content.proposed) { choice($0) } }
          Section(ImportStrings.pickerAll) { ForEach(content.others) { choice($0) } }
        }
      }
      .frame(height: 220)
      .overlay {
        if content.isEmpty { Text(ImportStrings.linkNoResults).foregroundStyle(.secondary) }
      }
      if model.canCreateOpponent(candidate) {
        Button(ImportStrings.pickerCreate(candidate.fixture.opponentName)) {
          model.createOpponent(for: candidate)
          onDone()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .padding(14)
    .frame(width: 360)
  }

  private func choice(_ opponent: Opponent) -> some View {
    Button {
      model.choose(opponent, for: candidate)
      onDone()
    } label: {
      HStack {
        Text(opponent.name)
        Spacer()
        if opponent.id == candidate.opponent?.id {
          Image(systemName: "checkmark").foregroundStyle(.secondary).accessibilityHidden(true)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(ImportStrings.linkChoose) \(opponent.name)")
  }
}
