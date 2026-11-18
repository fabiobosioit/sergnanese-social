import SSCore
import SwiftUI

/// Squadre: our teams, reorderable by drag, with the first-team marker and the "attiva" toggle.
public struct TeamsView: View {
  let app: AppModel
  @ViewState private var model: TeamsViewModel

  public init(app: AppModel) {
    self.app = app
    _model = ViewState(initialValue: TeamsViewModel(services: app.services))
  }

  public var body: some View {
    @Bindable var vm = model
    content(vm)
      .navigationTitle(TeamsStrings.title)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(TeamsStrings.add, systemImage: "plus") { vm.beginCreate() }
            .help(TeamsStrings.add)
        }
      }
      .sheet(isPresented: $vm.isCreating) { NewTeamSheet(model: vm) }
      .confirmDelete(
        vm.pendingDelete.map { TeamsStrings.deleteTitle($0.name) } ?? "",
        isPresented: Binding(get: { vm.pendingDelete != nil }, set: { if !$0 { vm.pendingDelete = nil } }),
        message: TeamsStrings.deleteMessage, onConfirm: { vm.confirmDelete() }
      )
      .alert(
        AppStrings.Errors.title,
        isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } }),
        actions: { Button(AppStrings.Common.ok) { vm.errorMessage = nil } },
        message: { Text(vm.errorMessage ?? "") }
      )
      .publishCommand(.delete, enabled: vm.selection != nil) { vm.requestDeleteSelection() }
      .task { vm.reload() }
      .onChange(of: app.dataRevision) { vm.reload() }
  }

  @ViewBuilder
  private func content(_ vm: TeamsViewModel) -> some View {
    @Bindable var vm = vm
    if let error = vm.loadError {
      ContentUnavailableView {
        Label(TeamsStrings.errorTitle, systemImage: "exclamationmark.triangle")
      } description: {
        Text(error)
      } actions: {
        Button(TeamsStrings.retry) { vm.reload() }
      }
    } else if vm.teams.isEmpty {
      ContentUnavailableView {
        Label(TeamsStrings.emptyTitle, systemImage: TeamsStrings.placeholderSymbol)
      } description: {
        Text(TeamsStrings.emptyDescription)
      } actions: {
        Button(TeamsStrings.add) { vm.beginCreate() }
      }
    } else {
      List(selection: $vm.selection) {
        ForEach(vm.teams) { team in
          TeamRow(team: team, model: vm)
            .tag(team.id)
            .contextMenu {
              Button(TeamsStrings.makeFirstTeam) { vm.makeFirst(team) }
                .disabled(team.isFirstTeam)
              Button(team.isActive ? TeamsStrings.deactivate : TeamsStrings.active) {
                vm.setActive(team, !team.isActive)
              }
              Divider()
              Button(TeamsStrings.moveUp) {
                vm.selection = team.id
                vm.moveSelection(by: -1)
              }
              .disabled(team.id == vm.teams.first?.id)
              Button(TeamsStrings.moveDown) {
                vm.selection = team.id
                vm.moveSelection(by: 1)
              }
              .disabled(team.id == vm.teams.last?.id)
              Divider()
              Button(TeamsStrings.deleteMenu, role: .destructive) { vm.requestDelete(team) }
            }
        }
        .onMove { vm.move(fromOffsets: $0, toOffset: $1) }
      }
      .onDeleteCommand { vm.requestDeleteSelection() }
    }
  }
}

/// One team: first-team marker, inline name and short label, and the "attiva" toggle.
private struct TeamRow: View {
  let team: Team
  let model: TeamsViewModel

  @ViewState private var name = ""
  @ViewState private var shortLabel = ""
  @FocusState private var focus: Field?

  private enum Field: Hashable { case name, shortLabel }

  var body: some View {
    HStack(spacing: 12) {
      Button {
        model.makeFirst(team)
      } label: {
        Image(systemName: team.isFirstTeam ? "star.fill" : "star")
          .foregroundStyle(team.isFirstTeam ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
      }
      .buttonStyle(.borderless)
      .help(team.isFirstTeam ? TeamsStrings.firstTeamHelp : TeamsStrings.makeFirstTeam)
      .accessibilityLabel(team.isFirstTeam ? TeamsStrings.firstTeam : TeamsStrings.makeFirstTeam)
      .accessibilityAddTraits(team.isFirstTeam ? .isSelected : [])

      TextField(TeamsStrings.nameField, text: $name)
        .textFieldStyle(.plain)
        .focused($focus, equals: .name)
        .onSubmit(commit)
      TextField(TeamsStrings.shortLabelField, text: $shortLabel)
        .textFieldStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 140)
        .focused($focus, equals: .shortLabel)
        .onSubmit(commit)
      Toggle(TeamsStrings.active, isOn: Binding(get: { team.isActive }, set: { model.setActive(team, $0) }))
        .toggleStyle(.switch)
        .labelsHidden()
        .controlSize(.small)
        .help(TeamsStrings.activeHelp)
        .accessibilityLabel(TeamsStrings.active)
    }
    .padding(.vertical, 2)
    .onAppear(perform: resetFields)
    .onChange(of: team) { resetFields() }
    .onChange(of: focus) { old, new in
      if old != nil && new == nil { commit() }
    }
  }

  private func resetFields() {
    name = team.name
    shortLabel = team.shortLabel
  }

  private func commit() {
    if !model.rename(team, name: name, shortLabel: shortLabel) { resetFields() }
  }
}

/// "Nuova squadra": name and short label, Crea (Return) and Annulla (Esc).
private struct NewTeamSheet: View {
  let model: TeamsViewModel

  var body: some View {
    @Bindable var vm = model
    VStack(spacing: 0) {
      Text(TeamsStrings.newTitle)
        .font(.headline)
        .padding(.top, 16)
      Form {
        ValidatedField(TeamsStrings.nameField, problems: vm.newProblems, field: .name) {
          TextField(
            TeamsStrings.nameField, text: $vm.newDraft.name, prompt: Text(TeamsStrings.namePrompt)
          )
          .labelsHidden()
          .onSubmit { vm.create() }
        }
        ValidatedField(TeamsStrings.shortLabelField, problems: vm.newProblems, field: .shortLabel) {
          TextField(
            TeamsStrings.shortLabelField, text: $vm.newDraft.shortLabel,
            prompt: Text(TeamsStrings.shortLabelPrompt)
          )
          .labelsHidden()
          .onSubmit { vm.create() }
        }
      }
      .formStyle(.grouped)
      HStack {
        Spacer()
        Button(AppStrings.Common.cancel) { vm.isCreating = false }
          .keyboardShortcut(.cancelAction)
        Button(TeamsStrings.create) { vm.create() }
          .keyboardShortcut(.defaultAction)
      }
      .padding([.horizontal, .bottom], 16)
    }
    .frame(width: 400)
  }
}
