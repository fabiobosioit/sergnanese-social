import SSCore
import SwiftUI

/// A small sheet to choose the team whose CSI page is opened. Shown when several teams have one.
struct CSITeamPickerSheet: View {
  let launcher: CSIImportLauncher
  let onOpen: (EntityID) -> Void

  var body: some View {
    @Bindable var launcher = launcher
    VStack(spacing: 0) {
      Text(ImportStrings.pickTeamTitle)
        .font(.headline)
        .padding(.top, 16)
      Form {
        Picker(ImportStrings.pickTeamField, selection: $launcher.pickedTeamID) {
          ForEach(launcher.teams) { Text($0.name).tag(EntityID?.some($0.id)) }
        }
      }
      .formStyle(.grouped)
      HStack {
        Spacer()
        Button(AppStrings.Common.cancel) { launcher.isPickerPresented = false }
          .keyboardShortcut(.cancelAction)
        Button(ImportStrings.pickTeamOpen) { launcher.confirmPick(open: onOpen) }
          .keyboardShortcut(.defaultAction)
          .disabled(launcher.pickedTeamID == nil)
      }
      .padding([.horizontal, .bottom], 16)
    }
    .frame(width: 400)
  }
}
