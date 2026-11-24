import SSCore
import SwiftUI

/// A small sheet to choose the team a PDF calendar belongs to.
struct PDFTeamPickerSheet: View {
  let launcher: PDFImportLauncher

  var body: some View {
    @Bindable var launcher = launcher
    VStack(spacing: 0) {
      Text(ImportStrings.pickTeamPDFTitle(launcher.calendar?.competition ?? ""))
        .font(.headline)
        .multilineTextAlignment(.center)
        .padding([.top, .horizontal], 16)
      Form {
        Picker(ImportStrings.pickTeamField, selection: $launcher.pickedTeamID) {
          Text(ImportStrings.pickTeamNone).tag(EntityID?.none)
          ForEach(launcher.teams) { Text($0.name).tag(EntityID?.some($0.id)) }
        }
        Text(ImportStrings.pickTeamPDFMessage).font(.callout).foregroundStyle(.secondary)
      }
      .formStyle(.grouped)
      HStack {
        Spacer()
        Button(ImportStrings.cancel) { launcher.cancelPick() }
          .keyboardShortcut(.cancelAction)
        Button(ImportStrings.pickTeamContinue) { launcher.confirmPick() }
          .keyboardShortcut(.defaultAction)
          .disabled(launcher.pickedTeamID == nil)
      }
      .padding([.horizontal, .bottom], 16)
    }
    .frame(width: 440)
  }
}
