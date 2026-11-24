import SSCore
import SwiftUI

/// The inspector: the full form of the selected match. Changes save when a field commits (Return,
/// leaving the field, or any picker or toggle change); problems show next to the field and nothing
/// is saved until they are fixed.
struct MatchInspector: View {
  let detail: MatchDetail
  let model: MatchesViewModel
  @ViewState private var form: MatchFormState
  @ViewState private var problems: [FieldProblem] = []
  /// The match as last loaded or saved; a different one coming in (lock from the menu, say) refreshes the form.
  @ViewState private var baseline: Match
  @FocusState private var focus: MatchField?

  init(detail: MatchDetail, model: MatchesViewModel) {
    self.detail = detail
    self.model = model
    _form = ViewState(initialValue: MatchFormState(match: detail.match))
    _baseline = ViewState(initialValue: detail.match)
  }

  var body: some View {
    VStack(spacing: 0) {
      resultBar
      warningsBar
      MatchForm(form: $form, problems: problems, model: model, focus: $focus, commit: commit)
    }
    .onChange(of: focus) { old, new in
      if old != nil, old != new { commit() }
    }
    .onChange(of: form.teamID) { commit() }
    .onChange(of: form.opponentID) { commit() }
    .onChange(of: form.date) { commit() }
    .onChange(of: form.isHome) { commit() }
    .onChange(of: form.status) { commit() }
    .onChange(of: form.isLocked) { commit() }
    .onChange(of: detail.match) { _, incoming in
      guard incoming != baseline else { return }
      baseline = incoming
      form = MatchFormState(match: incoming)
      problems = []
    }
    .onDisappear { commit() }
  }

  private func commit() {
    guard form != MatchFormState(match: baseline) else { return }
    let result = model.save(id: detail.id, form: form)
    problems = result
    if result.isEmpty, let saved = model.detail(id: detail.id)?.match {
      baseline = saved
      form = MatchFormState(match: saved)
    }
  }

  /// "Risultato…" at the top of the inspector; disabled for a postponed or cancelled match.
  private var resultBar: some View {
    let canEnter = model.canEnterResult([detail.id])
    return HStack {
      Button {
        model.beginResult([detail.id])
      } label: {
        Label(MatchesStrings.ResultEntry.enter, systemImage: "sportscourt")
      }
      .disabled(!canEnter)
      .help(canEnter ? MatchesStrings.ResultEntry.enterHelp : MatchesStrings.ResultEntry.enterDisabledHelp)
      Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
  }

  @ViewBuilder
  private var warningsBar: some View {
    let warnings = model.warnings(for: detail)
    if !warnings.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(Array(warnings.enumerated()), id: \.offset) { WarningLabel($0.element.message) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.vertical, 8)
    }
  }
}

/// "Nuova partita": the same form in a sheet. Return adds, Esc cancels.
struct NewMatchSheet: View {
  let model: MatchesViewModel
  @ViewState private var form: MatchFormState
  @ViewState private var problems: [FieldProblem] = []
  @FocusState private var focus: MatchField?
  @Environment(\.dismiss) private var dismiss

  init(initial: MatchFormState, model: MatchesViewModel) {
    self.model = model
    _form = ViewState(initialValue: initial)
  }

  var body: some View {
    VStack(spacing: 0) {
      Text(MatchesStrings.newMatchTitle)
        .font(.headline)
        .padding(.top, 16)
      MatchForm(form: $form, problems: problems, model: model, focus: $focus, commit: {})
      HStack {
        Spacer()
        Button(MatchesStrings.cancel) { cancel() }
          .keyboardShortcut(.cancelAction)
        Button(MatchesStrings.create) { add() }
          .keyboardShortcut(.defaultAction)
      }
      .padding(16)
    }
    .frame(width: 460, height: 620)
  }

  private func add() {
    problems = model.create(form: form)
    if problems.isEmpty { dismiss() }
  }

  private func cancel() {
    model.newMatchForm = nil
    dismiss()
  }
}
