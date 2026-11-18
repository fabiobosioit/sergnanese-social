import SSCore
import SwiftUI

/// The form shared by the inspector and the "Nuovo avversario" sheet: logo, name, short name, the
/// live "Come apparirà" line and the aliases.
struct OpponentFields: View {
  @Binding var draft: OpponentDraft
  let problems: [FieldProblem]
  let appearance: Truncation
  let limit: Int?
  let logoURL: URL?
  let onCommit: () -> Void
  let onLogo: @MainActor (LogoInput) -> Void
  let onRemoveLogo: @MainActor () -> Void
  let onAddAlias: (String) -> Void
  let onRemoveAlias: (String) -> Void

  @ViewState private var aliasText = ""
  @FocusState private var focus: Field?

  private enum Field: Hashable { case name, shortName, alias }

  var body: some View {
    Form {
      Section {
        LabeledContent(OpponentsStrings.logoField) {
          LogoWell(
            logoURL: logoURL, name: draft.name, initials: initials(draft.name), onInput: onLogo,
            onRemove: onRemoveLogo)
        }
        .fieldProblem(problems, for: .logo)
      }
      Section {
        ValidatedField(OpponentsStrings.nameField, problems: problems, field: .name) {
          TextField(OpponentsStrings.nameField, text: $draft.name)
            .labelsHidden()
            .focused($focus, equals: .name)
            .onSubmit(onCommit)
        }
        ValidatedField(OpponentsStrings.shortNameField, problems: problems, field: .shortName) {
          TextField(
            OpponentsStrings.shortNameField,
            text: Binding(get: { draft.shortName ?? "" }, set: { draft.shortName = $0 }),
            prompt: Text(OpponentsStrings.shortNamePrompt)
          )
          .labelsHidden()
          .focused($focus, equals: .shortName)
          .onSubmit(onCommit)
        }
        LabeledContent(OpponentsStrings.appearsAs) { appearsAs }
      }
      Section(OpponentsStrings.aliasesField) { aliases }
    }
    .formStyle(.grouped)
    .onChange(of: focus) { old, _ in
      if old != nil { onCommit() }
    }
  }

  private var appearsAs: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(appearance.text.isEmpty ? "—" : appearance.text)
        .font(.headline)
        .textSelection(.enabled)
      Label(
        appearance.wasCut ? OpponentsStrings.appearsCut : OpponentsStrings.appearsFits,
        systemImage: appearance.wasCut ? "scissors" : "checkmark.circle"
      )
      .font(.caption)
      .foregroundStyle(appearance.wasCut ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
      if let limit {
        Text(OpponentsStrings.appearsAsHint(limit: limit))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var aliases: some View {
    ForEach(draft.aliases, id: \.self) { alias in
      HStack {
        Text(alias)
        Spacer()
        Button {
          onRemoveAlias(alias)
        } label: {
          Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(OpponentsStrings.removeAlias(alias))
        .help(OpponentsStrings.removeAlias(alias))
      }
    }
    HStack {
      TextField(OpponentsStrings.addAlias, text: $aliasText, prompt: Text(OpponentsStrings.aliasPrompt))
        .focused($focus, equals: .alias)
        .onSubmit(addAlias)
      Button(action: addAlias) {
        Image(systemName: "plus.circle")
      }
      .buttonStyle(.borderless)
      .disabled(aliasText.trimmingCharacters(in: .whitespaces).isEmpty)
      .accessibilityLabel(OpponentsStrings.addAlias)
      .help(OpponentsStrings.addAlias)
    }
    if let message = problems.message(for: .aliases) { ProblemText(message) }
  }

  private func addAlias() {
    onAddAlias(aliasText)
    aliasText = ""
  }
}
