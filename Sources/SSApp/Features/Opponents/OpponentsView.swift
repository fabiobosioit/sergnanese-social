import SSCore
import SwiftUI

/// Avversari: a searchable table of the clubs we play, with an inspector to edit the selected one.
public struct OpponentsView: View {
  let app: AppModel
  @ViewState private var model: OpponentsViewModel
  @ViewState private var showsInspector = true
  @ViewState private var isSearching = false

  public init(app: AppModel) {
    self.app = app
    _model = ViewState(initialValue: OpponentsViewModel(services: app.services))
  }

  public var body: some View {
    @Bindable var vm = model
    content(vm)
      .navigationTitle(OpponentsStrings.title)
      .searchable(
        text: $vm.searchText, isPresented: $isSearching, placement: .toolbar,
        prompt: Text(OpponentsStrings.searchPrompt)
      )
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(OpponentsStrings.add, systemImage: "plus") { vm.beginCreate() }
            .help(OpponentsStrings.add)
        }
        ToolbarItem(placement: .primaryAction) {
          Button(OpponentsStrings.inspectorTitle, systemImage: "sidebar.trailing") { showsInspector.toggle() }
            .help(OpponentsStrings.inspectorTitle)
        }
      }
      .inspector(isPresented: $showsInspector) {
        inspector(vm)
          .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
      }
      .sheet(isPresented: $vm.isCreating) { NewOpponentSheet(model: vm) }
      .confirmDelete(
        vm.deleteTitle,
        isPresented: Binding(get: { !vm.pendingDelete.isEmpty }, set: { if !$0 { vm.pendingDelete = [] } }),
        message: OpponentsStrings.deleteMessage, onConfirm: { vm.confirmDelete() }
      )
      .alert(
        AppStrings.Errors.title,
        isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } }),
        actions: { Button(AppStrings.Common.ok) { vm.errorMessage = nil } },
        message: { Text(vm.errorMessage ?? "") }
      )
      .publishCommand(.newOpponent) { vm.beginCreate() }
      .publishCommand(.delete, enabled: !vm.selection.isEmpty) { vm.requestDeleteSelection() }
      .publishCommand(.find) { isSearching = true }
      .task {
        vm.onDataChanged = { app.refreshWarningBadge() }
        vm.reload()
      }
      .onChange(of: vm.searchText) { vm.reload() }
      .onChange(of: vm.selection) { old, _ in vm.selectionChanged(from: old) }
      .onChange(of: app.dataRevision) { vm.reload() }
  }

  @ViewBuilder
  private func content(_ vm: OpponentsViewModel) -> some View {
    if let error = vm.loadError {
      ContentUnavailableView {
        Label(OpponentsStrings.errorTitle, systemImage: "exclamationmark.triangle")
      } description: {
        Text(error)
      } actions: {
        Button(OpponentsStrings.retry) { vm.reload() }
      }
    } else {
      table(vm)
        .overlay {
          if vm.opponents.isEmpty {
            if vm.searchText.isEmpty {
              ContentUnavailableView {
                Label(OpponentsStrings.emptyTitle, systemImage: OpponentsStrings.placeholderSymbol)
              } description: {
                Text(OpponentsStrings.emptyDescription)
              } actions: {
                Button(OpponentsStrings.add) { vm.beginCreate() }
              }
            } else {
              ContentUnavailableView.search(text: vm.searchText)
            }
          }
        }
    }
  }

  private func table(_ vm: OpponentsViewModel) -> some View {
    @Bindable var vm = vm
    return Table(vm.opponents, selection: $vm.selection) {
      TableColumn(OpponentsStrings.columnLogo) { opponent in
        LogoCell(url: vm.logoURL(fileName: opponent.logoFile), initials: initials(opponent.name))
      }
      .width(36)
      TableColumn(OpponentsStrings.columnName) { opponent in
        Text(opponent.name)
      }
      TableColumn(OpponentsStrings.columnShortName) { opponent in
        Text(opponent.shortName ?? "—").foregroundStyle(.secondary)
      }
      TableColumn(OpponentsStrings.columnMatches) { opponent in
        Text(vm.matches(of: opponent), format: .number).monospacedDigit()
      }
      .width(60)
    }
    .contextMenu(forSelectionType: EntityID.self) { ids in
      if !ids.isEmpty {
        Button(OpponentsStrings.edit) {
          vm.selection = ids
          showsInspector = true
        }
        Divider()
        Button(OpponentsStrings.deleteMenu, role: .destructive) { vm.requestDelete(ids) }
      }
    } primaryAction: { ids in
      vm.selection = ids
      showsInspector = true
    }
    .onDeleteCommand { vm.requestDeleteSelection() }
  }

  @ViewBuilder
  private func inspector(_ vm: OpponentsViewModel) -> some View {
    @Bindable var vm = vm
    if let selected = vm.selectedOpponent {
      OpponentFields(
        draft: $vm.draft, problems: vm.problems, appearance: vm.appearance(of: vm.draft),
        limit: vm.teamNameLimit, logoURL: vm.logoURL(fileName: selected.logoFile),
        onCommit: { vm.commit() },
        onLogo: { input in Task { await vm.setLogo(LogoInputValue(input)) } },
        onRemoveLogo: { vm.removeLogo() },
        onAddAlias: { vm.addAlias($0) }, onRemoveAlias: { vm.removeAlias($0) }
      )
      .id(selected.id)
    } else {
      ContentUnavailableView(
        OpponentsStrings.noSelectionTitle, systemImage: OpponentsStrings.placeholderSymbol)
    }
  }
}

/// The logo (or initials) in a table row.
private struct LogoCell: View {
  let url: URL?
  let initials: String

  var body: some View {
    Group {
      if let url {
        ThumbnailView(url: url, maxPixel: 64)
      } else {
        Text(initials)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 24, height: 24)
    .accessibilityHidden(true)
  }
}

/// "Nuovo avversario": the same fields as the inspector, with Crea (Return) and Annulla (Esc).
private struct NewOpponentSheet: View {
  let model: OpponentsViewModel

  var body: some View {
    @Bindable var vm = model
    VStack(spacing: 0) {
      Text(OpponentsStrings.newTitle)
        .font(.headline)
        .padding(.top, 16)
      OpponentFields(
        draft: $vm.newDraft, problems: vm.newProblems, appearance: vm.appearance(of: vm.newDraft),
        limit: vm.teamNameLimit, logoURL: vm.logoURL(fileName: vm.newDraft.logoFile),
        onCommit: {},
        onLogo: { input in Task { await vm.setNewLogo(LogoInputValue(input)) } },
        onRemoveLogo: { vm.removeNewLogo() },
        onAddAlias: { OpponentsViewModel.appendAlias($0, to: &vm.newDraft) },
        onRemoveAlias: { alias in vm.newDraft.aliases.removeAll { $0 == alias } }
      )
      HStack {
        Spacer()
        Button(AppStrings.Common.cancel) { vm.cancelCreate() }
          .keyboardShortcut(.cancelAction)
        Button(OpponentsStrings.create) { vm.create() }
          .keyboardShortcut(.defaultAction)
      }
      .padding([.horizontal, .bottom], 16)
    }
    .frame(width: 440, height: 560)
  }
}
