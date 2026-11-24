import SSCore
import SwiftUI

/// "Risultato": half-time, final and scorers of one match, with one-click generation of the two stories.
/// Fields are in fixture order, so an away match is typed as read on the scoreboard. Return saves, Esc cancels
/// (and stops a render that is going on).
struct ResultSheet: View {
  @Bindable var model: ResultModel
  let close: () -> Void
  @FocusState private var focus: ResultField?

  var body: some View {
    VStack(spacing: 0) {
      header
      Form {
        Section {
          scoreGrid
          scorersField
        }
        if !model.warnings.isEmpty {
          Section(MatchesStrings.ResultEntry.warningsTitle) {
            ForEach(Array(model.warnings.enumerated()), id: \.offset) { WarningLabel($0.element) }
          }
        }
      }
      .formStyle(.grouped)
      footer
    }
    .frame(width: 460)
    .interactiveDismissDisabled(model.isWorking)
    .onAppear { focus = model.form.initialFocus }
    .onChange(of: model.isFinished) { if model.isFinished { close() } }
    .alert(
      MatchesStrings.ResultEntry.failedTitle,
      isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    ) {
      Button(MatchesStrings.ResultEntry.ok) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  // MARK: Parts

  private var header: some View {
    VStack(spacing: 2) {
      Text(model.detail.team.name).font(.headline)
      Text("\(model.homeName) – \(model.awayName)")
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .multilineTextAlignment(.center)
      Text(model.longDate).font(.callout).foregroundStyle(.secondary)
    }
    .padding(.top, 16)
    .padding(.horizontal, 20)
  }

  private var scoreGrid: some View {
    Grid(alignment: .center, horizontalSpacing: 8, verticalSpacing: 8) {
      GridRow {
        Color.clear.frame(width: 1, height: 1)
        Text(model.homeName).lineLimit(1).truncationMode(.tail)
        Color.clear.frame(width: 1, height: 1)
        Text(model.awayName).lineLimit(1).truncationMode(.tail)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      scoreRow(
        MatchesStrings.ResultEntry.halfTime, home: $model.form.halfTimeHome, away: $model.form.halfTimeAway,
        homeField: .halfTimeHome, awayField: .halfTimeAway, problem: model.problem(for: .halfTime))
      scoreRow(
        MatchesStrings.ResultEntry.final, home: $model.form.finalHome, away: $model.form.finalAway,
        homeField: .finalHome, awayField: .finalAway, problem: model.problem(for: .score))
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func scoreRow(
    _ title: String, home: Binding<String>, away: Binding<String>, homeField: ResultField,
    awayField: ResultField, problem: String?
  ) -> some View {
    GridRow {
      Text(title).gridColumnAlignment(.trailing)
      scoreField(home, field: homeField, side: model.homeName, phase: title)
      Text(MatchesStrings.ResultEntry.separator).foregroundStyle(.secondary).accessibilityHidden(true)
      scoreField(away, field: awayField, side: model.awayName, phase: title)
    }
    if let problem {
      GridRow {
        Color.clear.frame(width: 1, height: 1)
        ProblemText(problem).gridCellColumns(3).gridColumnAlignment(.leading)
      }
    }
  }

  private func scoreField(_ text: Binding<String>, field: ResultField, side: String, phase: String) -> some View {
    TextField(phase, text: text)
      .labelsHidden()
      .multilineTextAlignment(.center)
      .frame(width: 64)
      .focused($focus, equals: field)
      .accessibilityLabel(MatchesStrings.ResultEntry.goalsLabel(side, phase.lowercased()))
  }

  private var scorersField: some View {
    ValidatedField(MatchesStrings.ResultEntry.scorers, problems: model.problems, field: .notes) {
      TextField(
        MatchesStrings.ResultEntry.scorers, text: $model.form.scorers,
        prompt: Text(MatchesStrings.ResultEntry.scorersPlaceholder), axis: .vertical
      )
      .labelsHidden()
      .lineLimit(2...4)
      .focused($focus, equals: .scorers)
    }
  }

  private var footer: some View {
    VStack(spacing: 8) {
      if model.isWorking {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(MatchesStrings.ResultEntry.rendering).foregroundStyle(.secondary)
          Spacer()
        }
      }
      HStack {
        Button(MatchesStrings.ResultEntry.cancel) { cancel() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        generateButton(.halfTime, title: MatchesStrings.ResultEntry.generateHalfTime)
        generateButton(.fullTime, title: MatchesStrings.ResultEntry.generateFullTime)
        Button(MatchesStrings.ResultEntry.save) { if model.save() { close() } }
          .keyboardShortcut(.defaultAction)
          .disabled(model.isWorking)
      }
    }
    .padding(16)
  }

  /// One button, or a pull-down when several templates fit (its main action is the one used last).
  @ViewBuilder
  private func generateButton(_ kind: ResultKind, title: String) -> some View {
    let candidates = model.candidates(for: kind)
    if candidates.isEmpty {
      Button(title) {}
        .disabled(true)
        .help(
          kind == .halfTime
            ? MatchesStrings.ResultEntry.noTemplateHalfTime : MatchesStrings.ResultEntry.noTemplateFullTime)
    } else if candidates.count == 1 {
      Button(title) { model.startGenerate(kind) }
        .disabled(model.isWorking)
        .help(MatchesStrings.ResultEntry.generateHelp)
    } else {
      Menu(title) {
        ForEach(candidates) { template in
          Button {
            model.startGenerate(kind, templateID: template.id)
          } label: {
            if template.id == model.choice[kind] {
              Label(template.manifest.name, systemImage: "checkmark")
            } else {
              Text(template.manifest.name)
            }
          }
        }
      } primaryAction: {
        model.startGenerate(kind)
      }
      .disabled(model.isWorking)
      .fixedSize()
      .help(MatchesStrings.ResultEntry.generateHelp)
    }
  }

  private func cancel() {
    if model.isWorking { model.cancelRender() } else { close() }
  }
}
