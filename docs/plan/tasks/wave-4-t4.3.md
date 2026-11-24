# T4.3 — PDF import (federation calendar): task sheets (Step 4 and Step 5)

Full sheets for the work after the T4.3 contract step. The layout, the rules (date and time from the home club,
venues, short name → full-name alias, our matches, byes, refusal of other layouts, the team picker) and the
short-to-full linking are in `wave-4-later.md` § T4.3. Read it before starting; this sheet does not repeat it.

**Blocked on:** Step 2 (synthetic fixtures in `Tests/Fixtures/pdf/` and `docs/plan/notes/t4.3-pdf-spike.md`) and
the Step 3 contract below, both merged. Also Step 1: the real sample must leave git (see "Ambiguity resolved").
No real PDF, club name or address in the repo or in a test; no network anywhere in this feature.

**Contract (Step 3, merged first).** Code against these; do not edit `Sources/SSCore/` or `Sources/SSCoreFakes/`.
If one is wrong, stop and report. The flow comment at the top of `Sources/SSCore/PDFCalendar.swift` is the
end-to-end recipe.

| Contract | Where | Used by |
|---|---|---|
| `PDFCalendar`: `category`, `phase`, `girone`, `matchdays` (`Matchday`: `number`, `leg` `.andata`/`.ritorno`, `date` = the printed Saturday), `clubs` (`Club`: `fullName`, `number`, `venue`, `address`, `time`, `homeDay` `.saturday`/`.sunday`/`nil`, `shortName` = the linked page-1 name), `fixtures` (ours), `byes` (our matchdays off), `problems` (`.unreadableRow`, `.clubNotLinked`, `.incomplete`). Pure helpers: `competition`, `HomeDay.matchDate(saturday:)`, `Club.matchVenue`. Caps: `PDFCalendar.maxFileSize` (10 MB), `maxPages` (20). The doc comment of `fixtures` says exactly how each fixture is filled | `PDFCalendar.swift` | a, b, 5 |
| `PDFCalendarParser.parse(pdf:settings:) throws -> PDFCalendar` (pure; its doc comment is the parser's contract, including the order of the errors) and `PDFCalendarError` (`.notAPDF`, `.tooLarge`, `.encrypted`, `.layoutNotRecognised`, `.unavailable`) | `PDFCalendar.swift` | a, b, 5 |
| `AppServices.pdfCalendarParser` (default: throws `.unavailable`) | `Services.swift` | b, 5 |
| `FetchedFixture.opponentAliases` (the page-2 full name), `.competition`, `.scheduleUnknown` (all defaulted; optional in JSON) | `Import.swift` | a, b, 5 |
| `FetchedFixture.newOpponentDraft` ("Crea avversario": name + aliases) and `Opponent.draftAddingImportNames(of:)` ("Collega a esistente…": adds the name and the aliases the opponent does not match yet) | `Import.swift` | b, 5 |
| `ImportCandidate.make(…, linkedOpponentID:, source:)`: `source` defaults to `.scrape` (pass `.pdf`); finds the opponent through `opponentAliases` when the name finds none; puts `competition` in new drafts and in existing matches without one; `ReviewReason.scheduleUnknown` (no draft, cannot be imported) | `Import.swift` | b, 5 |
| `ImportIssue.pdfReadFailed(file:reason:)` ("PDF: impossibile leggere «…». Formato PDF non riconosciuto: …" and the other reasons), `.pdfIncomplete(teams:clubs:)`, `.pdfClubNotLinked(name:)`, `.pdfUnreadableRow(matchday:text:)` (errors), `.pdfBye(matchday:)` ("Giornata 8: riposo.", information); `ImportIssue.pdfNotices(for:)` maps a calendar's problems and byes to report lines | `Import.swift`, `CoreStrings.swift` | b, 5 |
| Fake: `FakePDFCalendarParser` (`init(calendar:)`, `init(failing:)`, `scenario(referenceSaturday:)`, `scenarioCalendar(referenceSaturday:)`; the table in its doc comment gives each row's expected candidate for **Femminile**); `AppServices.fake()` uses the scenario | `SSCoreFakes` | b |

**Package.swift:** no change. PDFKit is a system framework and is linked automatically by `import PDFKit`. `SSApp`
still does not depend on `SSImport`: the UI reaches the parser through `AppServices`.

| Task | Agent | Model | Owns |
|---|---|---|---|
| T4.3a Parser | `render-engineer` | sonnet · effort high (opus if it fails twice) | `Sources/SSImport/PDF/**`, `Tests/SSImportTests/PDF/**`, new variants in `Tests/Fixtures/pdf/` made with the Step 2 generator only |
| T4.3b UI | `ui-dev` | sonnet · effort medium | `Sources/SSApp/Features/Import/**` (not `CSIBrowser/`), `Tests/SSAppTests/Import/` (not `CSIBrowser/`); for this task only: `Sources/SSApp/Features/Matches/MatchesView.swift` (toolbar button and drop target), `Sources/SSApp/Shell/AppCommands.swift`, `Sources/SSApp/Shell/CommandActions.swift`, `Sources/SSApp/Strings/AppStrings.swift` (the menu item) |
| Step 5 Wiring | `core-dev` | sonnet · effort low | `Sources/SergnaneseSocial/Composition.swift`, `Tests/IntegrationTests/PDFImportTests.swift` (new), `docs/plan/01-architecture.md` §7 and §8 |

T4.3a and T4.3b run in parallel; Step 5 starts when both are merged.

**Gate after Step 5:** `Scripts/check.sh` green; `qa-reviewer` (sonnet, medium) for T4.3a and T4.3b; `qa-reviewer`
(sonnet, high) for the final result: acceptance criteria, Mac design (open panel, drop target, team picker, Light and
Dark), and one run with the user on the real sample, which stays on the user's Mac. Expected with the sample:
8 Sergnanese matches with the right dates (Sunday for the clubs that play Domenica), times and venues, and
"Giornata 8: riposo".

---

## T4.3a — Federation PDF parser

| | |
|---|---|
| **Agent / model** | `render-engineer` · sonnet · effort high |
| **Depends on** | T4.3 Steps 2 and 3 |
| **Size** | M |

Read `docs/plan/notes/t4.3-pdf-spike.md` (measured column positions and line spacing) and the generator in
`Tests/Fixtures/pdf/` first.

**Features**

1. `public struct FederationPDFParser: PDFCalendarParser` in `Sources/SSImport/PDF/`, exactly as documented on
   `PDFCalendarParser` and `PDFCalendar.fixtures`. `import PDFKit` only: no SwiftUI, no WebKit, no AppKit types
   used directly. The `PDFDocument` and its pages are created and dropped inside `parse` (they are not `Sendable`);
   the parser itself holds no state.
2. **Guards, in this order:** `pdf.count > PDFCalendar.maxFileSize` → `.tooLarge` before PDFKit sees the bytes;
   `PDFDocument(data:)` is `nil` → `.notAPDF`; `isEncrypted` or `isLocked` → `.encrypted` (never try a password);
   `pageCount > PDFCalendar.maxPages` → `.tooLarge`; anything below that does not fit → `.layoutNotRecognised`.
   Annotations, links, forms and scripts are ignored: only text and positions are read.
3. **Lines with bounds:** for each page, `page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine()`,
   each line's `string` (trimmed, whitespace collapsed) and `bounds(for: page)`. Never rely on `page.string` order.
4. **Page 1 — grid:** title = the topmost centred line(s): `category`, then `phase` and `girone` split at the last
   `" - "` of the second title line. Every `GIORNATA n` line opens a block; the next line in the same column is the
   date `A. dd/mm/yyyy` (`.andata`) or `R. dd/mm/yyyy` (`.ritorno`), parsed into `DayDate`. A line belongs to the
   block whose column contains the line's centre x and whose band (from its `GIORNATA` line down to the next
   `GIORNATA` line of the same column, or the page bottom) contains its centre y. Use the spike's measured columns
   only as a sanity check; derive the columns from the `GIORNATA` lines' x positions.
   No title, no `GIORNATA` line, a block without a valid date, or a number outside `1...FieldLimits.maxRound` →
   `.layoutNotRecognised`.
5. **Match rows:** split at the separator `"- "` whose hyphen is preceded by a non-space character (`CREMONESE- RIOZZESE`;
   a name with `" - "` inside it is not split there). Exactly one separator, two non-empty sides → home, away. Else
   `.unreadableRow(matchday:text:)` and no fixture. A home side equal to `Riposo` (any case) is a bye of the away side.
6. **Page 2 — club table:** the header line(s) `Società | N. | Campo / Località | Indirizzo | Orario | Giorno` give each
   column's x range (from one header's left edge to the next one's); no header → `.layoutNotRecognised`. Text below
   the header is grouped into rows by y (the rows are about 16 pt apart; use half the spacing as the tolerance) and
   into cells by x. `Orario` → `ClockTime(_:)` (`9.30` → `09:30`; anything else → `nil`); `Giorno` `Sabato` /
   `Domenica` (any case, accents ignored) → `.saturday` / `.sunday`, else `nil`; empty `N.` → `nil`.
7. **Ours:** a side, or a page-2 `Società`, is our club when it equals `settings.clubShortName` under
   `searchKey(stripLegalPrefixes(_:))` after the legal suffixes of the linking rules are removed (`SERGNANESE A.S.D.`
   is ours). Rows without our club are ignored (but count for the health check and the linking).
8. **Short → full linking:** the five rules of `wave-4-later.md` § T4.3 ("Short name → page-2 club"), in order,
   with a private normaliser (upper case, spaces collapsed, dots removed, legal words and suffixes stripped, squad
   letter case-insensitive, `S.` expanded to `SAN`/`SANTO`/`SANTA` only to compare). Set `Club.shortName` for every
   linked row. Each page-1 name left unlinked → `.clubNotLinked(name:)`.
9. **Fixtures:** exactly as `PDFCalendar.fixtures` documents: date from the home club's `homeDay`
   (`HomeDay.matchDate(saturday:)`), the home club's time, away venue `Club.matchVenue`, home venue `nil`,
   `round` = matchday, `competition` = `PDFCalendar.competition`, `status: .scheduled`, `statusText: ""`,
   `opponentAliases` = `[club.fullName]` unless it equals the short name; home club unlinked or `homeDay == nil` →
   the Saturday, no time, no venue, `scheduleUnknown: true`. Sorted by matchday.
10. **Byes and health:** our byes in `byes`, ascending. Distinct page-1 teams (without `Riposo`) ≠ page-2 rows →
    `.incomplete(teams:clubs:)`, after the other problems. A calendar with no fixture of ours is returned as it is.

**Acceptance** (tests on the Step 2 synthetic files only; build the encrypted, oversized and many-page PDFs in the
test with PDFKit/CoreGraphics in a temporary folder)

- [ ] `calendar-sample.pdf`: category, phase and girone; every matchday with its number, leg and Saturday; every club
      row with every column; every short name linked (the `S.` name, the squad-letter name, the name that is a prefix
      of its full name); `problems` empty.
- [ ] Our fixtures, one by one: the Sunday date of a match at the Domenica club (the shape of rule 1's example:
      Saturday + 1, `09:30` from `9.30`); a home match with our club's time and `venue == nil`; an away match with
      `"<campo>, <indirizzo>"`; each opponent's page-1 name with its page-2 full name as the only alias; round and
      competition; no fixture on our bye and `byes == [n]`.
- [ ] Variant "page-2 club missing": that club's home match against us has `scheduleUnknown`, the Saturday, no time,
      no venue; `problems` holds `.clubNotLinked` for it and `.incomplete`, in that order.
- [ ] Variant "not federation": `.layoutNotRecognised`. A text file renamed `.pdf` → `.notAPDF`; a password-protected
      PDF → `.encrypted`; `maxFileSize + 1` bytes → `.tooLarge` (and PDFKit is never called: the bytes are not a PDF);
      a 21-page PDF → `.tooLarge`.
- [ ] Unit tests of the row split (`"A- B"`, `"A - B- C"` → `A - B` / `C`, `"A B"` and `"A- B- C"` unreadable,
      `"Riposo- A"` a bye) and of the name normaliser and linking rules on plain strings (fake names only).
- [ ] The settings' `clubShortName` is used: with another short name the same file gives that club's fixtures.
- [ ] Existing SSImport tests unchanged and green; `Scripts/check.sh` passes.

---

## T4.3b — UI: "Importa da PDF…", team picker, staging

| | |
|---|---|
| **Agent / model** | `ui-dev` · sonnet · effort medium |
| **Depends on** | T4.3 Step 3 |
| **Size** | M |

Built and tested against `AppServices.fake()` (`FakePDFCalendarParser.scenario`; stage it for **Femminile**).
Italian strings in `ImportStrings` (`AppStrings` only for the menu item); core messages (`ImportIssue.message`,
`ImportCandidate.reviewMessages`) are shown as they are. Standard controls, system font, semantic colours, Light and
Dark Mode. Reuse `ImportModel` and `ImportSheet` with a new source rather than copying them.

**Features**

1. **Command:** toolbar button "Importa da PDF…" in Partite and the same item in the File menu after "Importa da
   CSI…" (no shortcut), published by Partite as a focused action (`CommandAction.importPDF`). Disabled, with the
   reason as help text, while there is no active team.
2. **Choosing the file:** `.fileImporter` with `allowedContentTypes: [.pdf]`, one file. Dropping files on the Partite
   list: the first file URL that conforms to `UTType.pdf` is used, the rest ignored; a drop without a PDF does nothing.
   Security-scoped access is started and stopped around the read. The file size (resource value) is checked first:
   over `PDFCalendar.maxFileSize` → report line `.pdfReadFailed(file:reason: .tooLarge)` without reading the bytes.
3. **Reading:** `services.pdfCalendarParser.parse(pdf:settings:)` off the main actor (`Task.detached`), with an
   indeterminate progress. `PDFCalendarError` → the sheet shows only the report line
   `.pdfReadFailed(file: <file name>, reason:)`; nothing is staged.
4. **Team picker** (a sheet, like `CSITeamPickerSheet`): "Calendario: \(calendar.competition)", a picker of the active
   teams in `sortOrder`, preselected with the team chosen last in this run of the app (nothing stored), else none;
   "Continua" disabled until a team is chosen; "Annulla" closes everything.
5. **Staging:** `ImportModel` gains a source `.pdf(team:calendar:fileName:)`:
   - candidates: `ImportCandidate.make(fixture:team:opponents:existingMatches:homeVenue:linkedOpponentID:source: .pdf)`
     for every `calendar.fixtures`, existing matches read for the fixtures' date range of that team;
   - notices on top of the review: `ImportIssue.pdfNotices(for: calendar)`, errors first, then information;
   - when `calendar.fixtures` is empty: "Nessuna partita della \(clubShortName) in questo calendario." plus the notices;
   - default ticks: every `.new` or `.changed` row dated today or later (the whole season, not only the coming
     weekend); past rows start unticked;
   - "Crea avversario" uses `candidate.fixture.newOpponentDraft` and "Collega a esistente…" uses
     `opponent.draftAddingImportNames(of: candidate.fixture)` (skip the update when it equals `OpponentDraft(opponent)`).
     Use the helpers for the Tuttocampo and CSI sources too: for them they give today's result. The rebuild after
     create/link passes the same `source`;
   - a `.scheduleUnknown` row shows its review message and offers no action except create/link for the opponent;
   - `changes(for:)` also lists the competition ("Competizione: — → …").
6. **Commit and report:** `services.matches.upsertFromImport` of the ticked drafts (with venue edits, as today); no
   logo step for PDF (the PDF has no logos); the existing summary, then the notices. Closing reloads Partite.

**Acceptance**

- [ ] View-model tests on `AppServices.fake()` for Femminile: the four rows and states of the scenario table
      (`.changed`, `.new`, `.needsReview`, `.needsReview` with `scheduleUnknown`), the four notices in order (bye
      last, as information), the ticks (only rows from today on).
- [ ] "Crea avversario" on "AURORA PIANENGO" creates it with the alias "A.S.D. AURORA PIANENGO 1990" and the row
      becomes `.new`; "Collega a esistente…" on "NUOVA ESEMPIO" adds that alias, and the row stays `.needsReview` with
      only `scheduleUnknown`.
- [ ] Commit writes matches with `source == .pdf`: Sunday date and 10:30 for S. ILARIO (away, venue from the PDF),
      17:30 and the Settings home venue for BORGO LUCENTE, the competition on both; a locked match is untouched.
- [ ] `FakePDFCalendarParser(failing: .layoutNotRecognised)` → one report line containing "Formato PDF non
      riconosciuto", no candidates; a file over 10 MB (a sparse temporary file) → `.tooLarge` and the parser is not called.
- [ ] Dropping a PDF on Partite starts the same flow; dropping a PNG does nothing.
- [ ] Screens checked in Light and Dark Mode; standard controls only; the command is disabled without an active team.
- [ ] Existing Tuttocampo and CSI import tests unchanged and green; `Scripts/check.sh` passes.

---

## Step 5 — Wiring and integration test

| | |
|---|---|
| **Agent / model** | `core-dev` · sonnet · effort low |
| **Depends on** | T4.3a and T4.3b merged |
| **Size** | S |

**Features**

1. `Composition.makeServices` passes `pdfCalendarParser:` a `LoggingPDFCalendarParser(base: FederationPDFParser())`
   (in `Composition.swift`, like `LoggingPageFixtureParser`): under `Log.imports` log the number of fixtures, byes
   and problems, or the error case. Never log names, venues or addresses from the PDF.
2. `Tests/IntegrationTests/PDFImportTests.swift` in a temporary `SS_DATA_DIR` with the real database and
   `FederationPDFParser` on `Tests/Fixtures/pdf/calendar-sample.pdf`: settings with a known `homeVenue`, a team, one
   opponent existing under its full page-2 name; parse → `ImportCandidate.make(…, source: .pdf)` → create the
   missing opponents with `newOpponentDraft` → rebuild → `upsertFromImport`. Assert in the database: a Sunday date
   and its time, a home match with our time and the Settings venue, an away venue `"<campo>, <indirizzo>"`, an alias
   on a created opponent, the existing opponent reused through the alias (no duplicate), `source == .pdf`, round and
   competition. Importing the same file again gives only `.unchanged` rows.
3. `01-architecture.md`: §7 lists `PDFCalendarParser` and `AppServices.pdfCalendarParser`; §8 notes that the PDF
   import reads a local file only (no request, nothing run, 10 MB / 20 pages, encrypted files refused).

**Acceptance**

- [ ] The integration test passes without network; `Scripts/check.sh` passes.
- [ ] A Dev build (`Scripts/run.sh`) imports the real sample in the live run with the user (the file stays local).

---

## Ambiguity resolved in Step 3 (tell the user)

- **The real sample is in git.** `examples/Calendario_EsordientiMiste_Femm_Aut.pdf` was committed on `main`
  (commit `7455875`), and `examples/` is not in `.gitignore`. Step 1 asks to keep it out of the public repo: remove
  it from the index, ignore `examples/`, and, if it was pushed, consider rewriting history. Nothing in T4.3 reads it
  from the repo.
- **Home club missing from page 2, or a `Giorno` that is neither Sabato nor Domenica:** the row is "needs review"
  (`scheduleUnknown`) and **cannot be imported**; the user adds that match by hand. Importing it on the Saturday
  would create a duplicate when the real date is the Sunday (imports key matches by team and date).
- **Indirizzo:** appended to the away venue as `"<Campo / Località>, <Indirizzo>"`, cut at a word to the 60-character
  venue limit (the address goes first); notes are not used.
- **Opponent matching:** the short page-1 name first; when it finds no opponent, the full page-2 name (so an opponent
  created by Tuttocampo or CSI under its full name is reused). Only "Crea" and "Collega" save names as aliases.
- **Competition** fills new matches and existing matches without one; an existing competition is kept.
- **Team choice** is not remembered per calendar title (no stored setting); the picker remembers the last choice only
  while the app runs.
- **Default ticks** cover every new or changed row from today on, because a PDF is a whole-season calendar.
- **"Formato PDF non riconosciuto"** is a thrown error (nothing staged). Rows that cannot be split are reported
  (`unreadableRow`) and give no fixture.
