import SSCore
import SwiftUI

/// The start panel of "Importa da Tuttocampo" (T4.11): what to read, which teams, the estimate for a season run.
/// Nothing is requested until "Avvia".
struct TuttocampoScopeSheet: View {
  let model: ImportModel

  var body: some View {
    @Bindable var model = model
    VStack(spacing: 0) {
      Text(ImportStrings.title)
        .font(.headline)
        .padding(12)
      Divider()
      Form {
        Section(ImportStrings.scopeTitle) {
          Picker(ImportStrings.scopeTitle, selection: $model.scope) {
            ForEach(ImportScope.allCases) { scope in
              VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(scope))
                Text(Self.help(scope)).font(.callout).foregroundStyle(.secondary)
              }
              .tag(scope)
              .accessibilityElement(children: .combine)
            }
          }
          .pickerStyle(.radioGroup)
          .labelsHidden()
        }
        Section(ImportStrings.teamsTitle) {
          ForEach(model.startableTeams) { team in
            Toggle(
              team.name,
              isOn: Binding(
                get: { model.chosenTeamIDs.contains(team.id) }, set: { model.setTeamChosen(team, $0) }))
          }
          if model.chosenTeamIDs.isEmpty {
            Text(ImportStrings.teamsNoneChosen).font(.callout).foregroundStyle(.secondary)
          }
        }
        if let estimate = model.estimate {
          Section {
            Text(estimate.message)
              .foregroundStyle(.secondary)
              .accessibilityLabel("\(ImportStrings.estimateAccessibility): \(estimate.message)")
          }
        }
      }
      .formStyle(.grouped)
      Divider()
      HStack {
        Spacer()
        Button(ImportStrings.cancel) { model.dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(ImportStrings.start) { model.startRun() }
          .keyboardShortcut(.defaultAction)
          .disabled(!model.canStartRun)
      }
      .padding(12)
    }
    .frame(width: 460)
    .frame(minHeight: 460)
  }

  static func title(_ scope: ImportScope) -> String {
    switch scope {
    case .weekend: ImportStrings.scopeWeekend
    case .fromCurrentMatchday: ImportStrings.scopeFromCurrent
    case .wholeSeason: ImportStrings.scopeWhole
    }
  }

  static func help(_ scope: ImportScope) -> String {
    switch scope {
    case .weekend: ImportStrings.scopeWeekendHelp
    case .fromCurrentMatchday: ImportStrings.scopeFromCurrentHelp
    case .wholeSeason: ImportStrings.scopeWholeHelp
    }
  }
}
