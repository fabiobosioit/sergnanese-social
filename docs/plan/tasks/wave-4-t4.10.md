# T4.10 — Opponent matching: task sheet (Step 2)

The full sheet for the work after the T4.10 contract step. The rules (matching levels, expected results, review
sheet, picker) are in `wave-4-later.md` § T4.10 and decision D12 in `docs/plan/README.md`. Read both before
starting; this sheet does not repeat them.

**Blocked on:** T4.10a (Step 1) merged. No live network in any test.

**Contract (Step 1, merged first).** Code against these; do not edit `Sources/SSCore/` or `Sources/SSCoreFakes/`.
If one is wrong, stop and report. The comment at the top of `Sources/SSCore/OpponentMatching.swift` is the recipe.

| Contract | Where | Used by |
|---|---|---|
| `opponentMatchKey(_:) -> String` (level 1: legal prefixes and suffixes out, punctuation as spaces); `opponentsMatching(name:in:)` now uses it | `OpponentMatching.swift`, `Import.swift` | b |
| `OpponentProposal` (`opponent`, `score` 0…1, `kind` `.exact` / `.containment` / `.similar`), `rankOpponents(name:aliases:in:) -> [OpponentProposal]` (only opponents that qualify; exact first, then score, then name) | `OpponentMatching.swift` | b |
| Containment on a single significant word counts only when the word has 7+ letters (user, 2026-11-24): "ALCIONE" → "Alcione Milano" is proposed, "MEDA" → "Real Meda" is not. Two or more words on the shorter side are contained at any length | `OpponentMatching.swift` | b |
| `OpponentMatch` (`.exact`, `.proposed`, `.linked`, `.notFound`, `.ambiguous`) | `OpponentMatching.swift` | b |
| `ImportCandidate.opponentMatch`, `ImportCandidate.proposals` (at most `ImportCandidate.maxProposals` = 5, may include the matched opponent itself); `make(…)` pre-fills `opponent` and the draft for a single proposal, with **no** review reason. Several proposals → `.ambiguous` + `ReviewReason.opponentAmbiguous` (the existing reason and message) | `Import.swift` | b |
| `Opponent.draftAddingImportNames(of:)` (unchanged API; now compares with `opponentMatchKey`) | `Import.swift` | b |
| Fakes: `FakePDFCalendarParser.matchingScenario(referenceSaturday:)` / `matchingScenarioCalendar(referenceSaturday:)`: four fixtures giving `.exact`, `.proposed`, `.ambiguous`, `.notFound` against `Resources/Fixtures/matches.json` (table in its doc comment). In the default `AppServices.fake()` the CSI scenario row "Valdorso 2016" is now `.proposed` (F.C. Valdorso) | `SSCoreFakes` | b |

**Package.swift:** no change. No new service, no wiring step.

**Already changed in Step 1 (minimal, so `Scripts/check.sh` stays green; review them):**

- `Tests/SSAppTests/Import/ImportModelCSITests.swift` `statesFollowTheScenarioTable`: "Valdorso 2016" expected
  `.changed` instead of `.needsReview` (it is now proposed and pre-filled; the time differs).
- `Tests/IntegrationTests/PDFImportTests.swift`, helper `stage`: keeps only `.exact` / `.linked` rows and creates
  the opponent for every other row (was: only for `[.opponentNotFound]`). All synthetic names share "ESEMPIO", so
  "WOMEN ESEMPIO" became `.ambiguous` and "S. ESEMPIO CALCIO" was then proposed for the created "WOMEN ESEMPIO"
  ("esempio" has 7 letters, so the single-word rule still applies to it).

| Task | Agent | Model | Owns |
|---|---|---|---|
| T4.10b Review UI | `ui-dev` | sonnet · effort medium | `Sources/SSApp/Features/Import/ImportModel.swift`, `ImportSheet.swift`, `ImportStrings.swift`, `Tests/SSAppTests/Import/` (not `CSIBrowser/`), `Tests/IntegrationTests/PDFImportTests.swift` |

**Gate:** `Scripts/check.sh` green; `qa-reviewer` (sonnet, medium): acceptance criteria, Light/Dark, VoiceOver
labels; one live run with the user (the real PDF on the Dev data, after storing the girone's opponents with
different spellings).

---

## T4.10b — Review UI for exact, proposed and ambiguous opponents

| | |
|---|---|
| **Agent / model** | `ui-dev` · sonnet · effort medium |
| **Depends on** | T4.10a |
| **Size** | S |

**Features**

1. **Tag on proposed rows.** A row with `opponentMatch == .proposed` shows the stored opponent's name, a secondary
   tag "Proposto" (SF Symbol + semantic colour, not colour alone; VoiceOver "abbinamento proposto") and the line
   "Abbinato a «<opponent>» (proposta automatica)", with two buttons:
   - **Conferma**: rebuild the row with `linkedOpponentID` = the proposed opponent (the existing `rebuild`); it
     becomes `.linked` and the tag goes. No database write.
   - **Cambia…**: opens the picker.
   A proposed row is ticked by the usual rules; importing without Conferma accepts the proposal.
2. **"Cambia avversario…"** on every row that has an opponent (`.exact`, `.proposed`, `.linked`), as a row button
   and in the context menu. Today only "non trovato" rows can be linked.
3. **Picker** (`OpponentLinkPicker`): with an empty search, section "Proposti" = `candidate.proposals` in order
   (score order is already done), then "Tutti gli avversari" = every other stored opponent alphabetically; with a
   search, the existing filter. At the bottom: "Crea nuovo «<fixture name>»" (the existing create action).
   Ambiguous rows (`.ambiguous`) show their proposals on top the same way.
4. **Saving the import names.** On "Importa", every ticked row whose opponent came from `.exact`, `.proposed` or
   `.linked` gets `opponent.draftAddingImportNames(of: fixture)` saved through `OpponentRepository.update` when the
   draft differs from the opponent (skip otherwise), before the matches are written, so the next import of the same
   source is exact everywhere. Never rename an opponent.
5. **Header line:** "N abbinati, N proposti, N da collegare" (exact + linked; proposed; not found + ambiguous),
   counted over the rows that are not locked.
6. All new text in `ImportStrings` (Italian).

**Acceptance criteria**

- With `FakePDFCalendarParser.matchingScenario`, the review shows one linked row (Pol. Borgo Lucente), one
  proposed row (Virtus Campofelice, tag + Conferma/Cambia…), one ambiguous row ("ORATORIO CALCIO": three proposals on top of the picker,
  nothing pre-filled) and one "non trovato" row; the header reads "1 abbinati, 1 proposti, 2 da collegare".
- Conferma turns a proposed row into a linked one without changing its draft or tick.
- "Cambia avversario…" on an exact row can link it to another opponent; the row is rebuilt with the new opponent.
- After "Importa" of the proposed row, the opponent's aliases contain the fixture name; staging the same fixture
  again gives `.exact`.
- No opponent is renamed or deleted by the review; nothing is written before "Importa".
- Light and Dark Mode; the tag is readable by VoiceOver; keyboard reachable buttons.

**Tests (Swift Testing)**

- `ImportModel` with `matchingScenario`: counts, Conferma, Cambia, picker sections and order, alias saving on
  commit, re-stage all exact.
- `PDFImportTests`: one extra case, stored opponents spelled differently (e.g. "U.S. Esempio Tre 1970 S.r.l." for
  "ESEMPIO TRE 1970", "Esempio Sei" for a name proposed by containment, none for the rest) → exact + proposed + not
  found; import; re-import is all exact. Review the Step 1 helper change above and keep it or replace it.
