import SSCore
import SwiftUI

/// The fields of the match form, for keyboard focus.
enum MatchField: Hashable {
  case time, venue, competition, round, scoreUs, scoreThem, halfTimeUs, halfTimeThem, notes
}

/// The match form, shared by the inspector and the "Nuova partita" sheet. It only edits `form`; the
/// caller decides when to save (`commit`) and shows `problems` next to the fields.
struct MatchForm: View {
  @Binding var form: MatchFormState
  let problems: [FieldProblem]
  let model: MatchesViewModel
  var focus: FocusState<MatchField?>.Binding
  let commit: () -> Void

  var body: some View {
    Form {
      Section {
        ValidatedField(MatchesStrings.formTeam, problems: problems, field: .team) {
          Picker(MatchesStrings.formTeam, selection: $form.teamID) {
            ForEach(teamChoices) { Text($0.name).tag($0.id) }
          }
          .labelsHidden()
        }
        ValidatedField(MatchesStrings.formOpponent, problems: problems, field: .opponent) {
          OpponentPicker(opponentID: $form.opponentID, model: model)
        }
      }

      Section {
        ValidatedField(MatchesStrings.formDate, problems: problems, field: .date) {
          DatePicker(MatchesStrings.formDate, selection: dateBinding, displayedComponents: .date)
            .labelsHidden()
        }
        ValidatedField(MatchesStrings.formTime, problems: problems, field: .time) {
          TextField(MatchesStrings.formTime, text: $form.timeText, prompt: Text(MatchesStrings.formTimePlaceholder))
            .labelsHidden()
            .focused(focus, equals: .time)
            .onSubmit(commit)
        }
        LabeledContent(MatchesStrings.formHomeAway) {
          Picker(MatchesStrings.formHomeAway, selection: homeBinding) {
            Text(MatchesStrings.formHome).tag(true)
            Text(MatchesStrings.formAway).tag(false)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
        }
        ValidatedField(MatchesStrings.formVenue, problems: problems, field: .venue) {
          TextField(MatchesStrings.formVenue, text: $form.venue)
            .labelsHidden()
            .focused(focus, equals: .venue)
            .onSubmit(commit)
        }
      }

      Section {
        ValidatedField(MatchesStrings.formCompetition, problems: problems, field: .competition) {
          TextField(MatchesStrings.formCompetition, text: $form.competition)
            .labelsHidden()
            .focused(focus, equals: .competition)
            .onSubmit(commit)
        }
        ValidatedField(MatchesStrings.formRound, problems: problems, field: .round) {
          TextField(MatchesStrings.formRound, text: $form.roundText)
            .labelsHidden()
            .frame(maxWidth: 80)
            .focused(focus, equals: .round)
            .onSubmit(commit)
        }
        LabeledContent(MatchesStrings.formStatus) {
          Picker(MatchesStrings.formStatus, selection: $form.status) {
            ForEach(MatchStatus.allCases, id: \.self) { Text(StatusBadge.title(for: $0)).tag($0) }
          }
          .labelsHidden()
        }
      }

      Section {
        ValidatedField(MatchesStrings.formScore, problems: problems, field: .score) {
          scoreFields(
            us: $form.scoreUs, them: $form.scoreThem, usField: .scoreUs, themField: .scoreThem)
        }
        ValidatedField(MatchesStrings.formHalfTime, problems: problems, field: .halfTime) {
          scoreFields(
            us: $form.halfTimeUs, them: $form.halfTimeThem, usField: .halfTimeUs, themField: .halfTimeThem)
        }
        ValidatedField(MatchesStrings.formNotes, problems: problems, field: .notes) {
          TextField(MatchesStrings.formNotes, text: $form.notes, axis: .vertical)
            .labelsHidden()
            .lineLimit(2...5)
            .focused(focus, equals: .notes)
        }
      }

      Section {
        Toggle(MatchesStrings.formLocked, isOn: $form.isLocked)
          .help(MatchesStrings.formLockedHelp)
      }
    }
    .formStyle(.grouped)
  }

  /// Active teams, plus the match's current team even when it has been deactivated.
  private var teamChoices: [Team] {
    model.teams.filter { $0.isActive || $0.id == form.teamID }
  }

  private var dateBinding: Binding<Date> {
    Binding(
      get: { form.date.startOfDay() },
      set: { form.date = DayDate($0) })
  }

  private var homeBinding: Binding<Bool> {
    Binding(
      get: { form.isHome },
      set: { form.setHome($0, homeVenue: model.homeVenue) })
  }

  private func scoreFields(
    us: Binding<String>, them: Binding<String>, usField: MatchField, themField: MatchField
  ) -> some View {
    HStack(spacing: 6) {
      TextField(MatchesStrings.formScoreUs, text: us, prompt: Text(MatchesStrings.formScoreUs))
        .multilineTextAlignment(.trailing)
        .frame(width: 56)
        .focused(focus, equals: usField)
        .onSubmit(commit)
        .accessibilityLabel(MatchesStrings.formScoreUs)
      Text(MatchesStrings.scoreSeparator).foregroundStyle(.secondary).accessibilityHidden(true)
      TextField(MatchesStrings.formScoreThem, text: them, prompt: Text(MatchesStrings.formScoreThem))
        .frame(width: 56)
        .focused(focus, equals: themField)
        .onSubmit(commit)
        .accessibilityLabel(MatchesStrings.formScoreThem)
    }
  }
}

/// A button that opens a popover with a search field and the opponents; "Nuovo avversario…" creates
/// one from the typed name without leaving the form.
struct OpponentPicker: View {
  @Binding var opponentID: EntityID
  let model: MatchesViewModel
  @ViewState private var isOpen = false
  @ViewState private var query = ""
  @FocusState private var searchFocused: Bool

  private var current: Opponent? { model.opponents.first { $0.id == opponentID } }

  private var results: [Opponent] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return model.opponents }
    return model.opponents.filter {
      textMatches(query: trimmed, in: [$0.name, $0.shortName ?? ""] + $0.aliases)
    }
  }

  private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

  var body: some View {
    Button {
      isOpen = true
    } label: {
      HStack {
        Text(current?.name ?? MatchesStrings.chooseOpponent)
          .foregroundStyle(current == nil ? .secondary : .primary)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 4)
        Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityLabel(MatchesStrings.formOpponent)
    .accessibilityValue(current?.name ?? MatchesStrings.chooseOpponent)
    .popover(isPresented: $isOpen, arrowEdge: .bottom) {
      VStack(spacing: 0) {
        TextField(MatchesStrings.searchOpponent, text: $query)
          .textFieldStyle(.roundedBorder)
          .focused($searchFocused)
          .padding(8)
          .onSubmit(submit)
        Divider()
        List {
          ForEach(results) { opponent in
            Button {
              choose(opponent)
            } label: {
              HStack {
                Text(opponent.name)
                Spacer()
                if opponent.id == opponentID { Image(systemName: "checkmark") }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
          if results.isEmpty {
            Text(MatchesStrings.noOpponentFound).foregroundStyle(.secondary)
          }
          Button {
            createFromQuery()
          } label: {
            Label(
              trimmedQuery.isEmpty ? MatchesStrings.newOpponent : MatchesStrings.newOpponentNamed(trimmedQuery),
              systemImage: "plus")
          }
          .buttonStyle(.plain)
          .foregroundStyle(.tint)
        }
        .listStyle(.plain)
      }
      .frame(width: 300, height: 320)
      .onAppear { searchFocused = true }
    }
  }

  private func choose(_ opponent: Opponent) {
    opponentID = opponent.id
    close()
  }

  private func submit() {
    if results.count == 1, let only = results.first {
      choose(only)
    } else if results.isEmpty, !trimmedQuery.isEmpty {
      createFromQuery()
    }
  }

  private func createFromQuery() {
    guard !trimmedQuery.isEmpty else {
      searchFocused = true
      return
    }
    if let created = model.createOpponent(named: trimmedQuery) {
      choose(created)
    }
  }

  private func close() {
    isOpen = false
    query = ""
  }
}
