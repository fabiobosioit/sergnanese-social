# T4.5 — Results workflow: task sheet

The full sheet for T4.5. The plan entry (`wave-4-later.md` § T4.5) is three lines; this sheet fixes the decisions,
the contract step and the work after it. Read `01-architecture.md` §4–§7 and `03-mac-design.md` §4–§6 first.

**Blocked on:** nothing external. The user's answers to the open questions at the end (defaults are written in, so
the contract step can start with them). No network in any part of this task.

## What already exists (no change needed)

Checked in the code on 2026-11-24:

- **Model and database.** `Match.score`, `Match.halfTime` (both `Score?`, our point of view) and `Match.notes`
  ("Scorers or free text") exist in SSCore, in `MatchDraft`, and as columns `score_us`, `score_them`, `half_time_us`,
  `half_time_them`, `notes` in `matches` (SSData). Validation: goals 0…99, notes ≤ 500 characters. **No migration.**
- **Render context.** `SideContext.score` / `halfTimeScore`, `MatchContext.halfTime`, `hasScore`, `hasHalfTime`,
  `notes`, `isPostponed`, `isCancelled`. The built-ins `story-halftime` and `story-fulltime` already print
  `{{match.notes}}` as the scorers block (4 lines, `pre-line`), and the fixtures put scorers there ("Rossi 23',
  Bianchi 78'"). **Scorers are `notes`** (decision 1).
- **Rendering one image.** `RenderService.render` with an explicit `TemplateSelection` renders any template for any
  match and stores a `RenderRecord` (Archivio). `regenerateRecord` (Genera) shows the pattern.
- **Share picker.** `ImageActions.share(_:)` (`SSApp/Components/ImageGallery.swift`) opens
  `NSSharingServicePicker` on the key window.
- **Inspector form.** `MatchForm` already edits score, half-time score and notes; the quick form is a shortcut to
  three of its fields plus generation, not a new data path.

## Decisions

1. **Scorers = `Match.notes`.** The quick form labels the field "Marcatori"; the inspector label "Note" becomes
   "Marcatori e note". No new field, no migration, no template change for the two stories.
2. **Recap template = `kind: list` + `purpose: fulltime`.** No new `TemplatePurpose` case: a new case would break
   the exhaustive switch in `TemplatesStrings.purpose`, and older app versions would reject a shared template that
   uses it. `TemplateManifest.isResultsRecap` names the combination once. The recap is never in the default plan.
3. **A recap is one set of pages for the whole selection**, not one set per day as for the programme: the weekend's
   results on one image (several pages only above `pageSize`). `PlannedImage.date` = the first match date.
4. **Recap title and date label** (computed by SSRender, Italian, in `RenderStrings`): one day → "Risultati" and
   the long date; the Saturday and Sunday of one weekend → "Risultati del weekend" and the range ("Dal 14 al 15
   novembre"); anything else → "Risultati" and the range.
5. **What the recap contains.** The one-click recap takes **every match** of the selected weekend (user decision 2026-11-24: the user
   edits the image on the phone), every team, in schedule order, including postponed and cancelled ones. The template
   shows "Rinviata" / "Annullata" for those and "–" for a match without a score; no warning is raised for postponed
   or cancelled rows. Rows show category, both sides
   in home/away order, the score and an outcome marker; **no scorers in the recap rows** (no room; they are on the
   full-time story).
6. **Outcome for templates.** Mustache cannot compare numbers, so the context gets `outcome` (`win` / `draw` /
   `loss`, absent without a score) for a CSS class and a letter (V / N / P) in the recap row.
7. **An import never removes a result typed by the user.** Today `ImportCandidate.make` copies `fixture.score` onto an
   existing match, so an import run on Sunday evening, before the source has the score, would erase the score and
   half-time score just typed. New rule in the contract step (C3).
8. **Duplicate does not copy scorers.** `MatchRepository.duplicate` keeps `notes` today; once notes are the scorers,
   duplicating a played match would carry last week's scorers onto next week's story. New rule: notes are cleared
   when the original has a final or half-time score (C4). Open question 1.
9. **Quick form = a small sheet "Risultato"** opened from the row (context menu), the inspector and the Immagini
   menu. It is a deliberate exception to `03-mac-design.md` §5 ("sheets only for new items and import reports"),
   like the import sheets: a short modal form with Return / Esc. The orchestrator adds the line to §5 and two menu
   rows to §4 (see "Plan edits").
10. **Status.** Saving a complete final score on a `.scheduled` match sets `.played`. A half-time score alone changes
    no status. "Risultato…" is disabled for postponed and cancelled matches. Locked matches can be edited (locks
    are about imports; `update` works on locked matches).
11. **Final ≥ half-time** for each side is checked in the quick form only (a field problem), never in SSCore
    validation: an import that brings only the final score must not fail the whole transaction on an old typo.
12. **Template choice.** Single templates with purpose `.halftime` (resp. `.fulltime`), recap templates with
    `isResultsRecap`. None → the button is disabled with a help text; one → used; several → a pull-down
    (`Menu(primaryAction:)`) whose primary action is the last one used (remembered per purpose in `UserDefaults`),
    else the first built-in, else the first by name.
13. **Sharing.** After a one-click render the system share picker opens with the new file(s). From the sheet, the
    picker opens **after** the sheet has closed (`.sheet(onDismiss:)`), anchored to the main window. The share
    action is injected (`@MainActor ([URL]) -> Void`, default `ImageActions.share`) so tests can capture it.

---

## Step 1 — contract (`foundation-architect`), merged first

Owns `Sources/SSCore/`, `Sources/SSCoreFakes/`, `Resources/Fixtures/`, `Tests/SSCoreTests/`, plus the minimal test
edits listed below. Everyone after codes against these; do not edit `Sources/SSCore/` or `Sources/SSCoreFakes/`. If
one is wrong, stop and report.

| # | Contract | Where | Used by |
|---|---|---|---|
| C1 | `public enum MatchOutcome: String, Sendable, Codable, CaseIterable { case win, draw, loss }` with `init?(us: Int?, them: Int?)` (`nil` unless both present). `MatchContext.outcome: MatchOutcome?`, **derived** in the existing `init` from `us.score` / `opponent.score` (no new init parameter, so every caller compiles unchanged); `nil` is absent from the JSON, so `{{#outcome}}` works and older fixture JSON still decodes | `RenderContext.swift` | b, a (rows carry it) |
| C2 | `TemplateManifest.isResultsRecap: Bool` (`kind == .list && purpose == .fulltime`). Doc comments: `TemplatePurpose.fulltime` (with `list` = results recap), `TemplateSelection.matchIDs` (a recap takes all its matches in one set of pages; other list templates one set per day), `RenderRequest.selections` (the default plan never includes a recap) | `TemplateManifest.swift`, `Services.swift` | a, c |
| C3 | `ImportCandidate.make`, existing match: when `fixture.score == nil`, the fixture's status is `.scheduled` or `.played`, and the existing match has a `score`, the draft **keeps** the existing `score`, `halfTime` and `status` (the row is then `.unchanged` if nothing else differs). A fixture with a score still wins (as today; the row shows `.changed`); postponed and cancelled fixtures behave as today. Doc comment updated | `Import.swift` | every import path (T4.2, T4.3, T4.8, T4.11): behaviour only, no API change |
| C4 | `MatchRepository.duplicate` doc: `notes` are cleared when the original has a `score` or a `halfTime`, kept otherwise. The in-memory fake follows it | `Repositories.swift`, `SSCoreFakes/FakeRepositories.swift` | d, c |
| C5 | Fixture `list-results.context.json`: a `ListContext` with title "Risultati del weekend", dateLabel "Dal 14 al 15 novembre", page 1/1, **10 rows** over Saturday and Sunday: home and away wins, a loss, 0–0, 3–3, a two-digit score (10–0), the 45-character opponent (cut to `teamName` 22), an opponent without a logo, one postponed row (no score), each with `outcome`. `outcome` added to every existing fixture context with a score. Generator (`generator/gen_fixtures.py`) and `Fixtures/README.md` updated | `Resources/Fixtures/` | a, b |
| C6 | Fakes: a 5th entry in `FakeTemplateStore.builtinManifests`, exactly the manifest b ships: `id "story-results"`, name "Story · Risultati del weekend", version 1.0.0, story 1080×1920, `kind .list`, `purpose .fulltime`, `pageSize 10`, `requires [.score]`, limits `teamName 22`, `category 16`. `FakeRenderService.plan`: a recap template makes one set of pages over the whole selection (date = first match date); its doc comment updated | `SSCoreFakes` | c |

Tests in `Tests/SSCoreTests/`: `MatchOutcome.init` (all cases, a missing side → `nil`, 0–0 → draw); `MatchContext`
derives `outcome`; old JSON without `outcome` decodes; `isResultsRecap` for the four combinations; C3 as four
`ImportCandidate.make` cases (no fixture score + stored score → kept and `.unchanged`; fixture score differs →
fixture wins, `.changed`, half-time kept; postponed fixture → as today; no stored score → as today); fake
`duplicate` with and without a score; `FixtureTests` decode `list-results.context.json`, check its 10 rows and that
every `outcome` agrees with the scores; fake plan for `story-results` over Saturday + Sunday → one image.

**Package.swift:** no change. No new target, service or dependency; no wiring step.

**Minimal edits outside the owned folders** (so `Scripts/check.sh` stays green; list them in the report):

- `Tests/SSCoreTests/FakesTests.swift`: templates count 4 → 5.
- `Tests/SSAppTests/Templates/TemplatesViewModelTests.swift`: counts 4 → 5 and 5 → 6 (the fake now has five
  built-ins); rename `listsTheFourBuiltins`.
- Any other test whose expectation changes because of C3 or C4, with the reason.

Until T4.5a merges, the real engine renders a recap per day with the programme title, and until T4.5d merges SSData
still copies notes on duplicate: expected.

---

| Task | Agent | Model | Owns |
|---|---|---|---|
| T4.5a Recap engine | `render-engineer` | sonnet · effort low | `Sources/SSRender/RenderPlanner.swift`, `ContextBuilder.swift`, `RenderStrings.swift`, `FixtureContexts.swift`, `TemplateRenderService.swift` (fixture choice only), `Sources/ss-tool/DemoRender.swift` (fixture names only), `Tests/SSRenderTests/` |
| T4.5b Recap template | `template-converter` | sonnet · effort medium | `Resources/Templates/story-results/` (new), `Tests/IntegrationTests/GoldenImageTests.swift` (`templateIDs` only), `Tests/IntegrationTests/.golden/story-results.png`, `docs/TEMPLATES.md` |
| T4.5c Results UI | `ui-dev` | sonnet · effort medium | `Sources/SSApp/Features/Matches/` (new `ResultSheet.swift`, `ResultFormState.swift`, `ResultModel.swift`; `MatchesView.swift`, `MatchEditors.swift`, `MatchForm.swift` (label only), `MatchesStrings.swift`), `Sources/SSApp/Features/Generate/GenerateViewModel.swift` (`isEligible` only), `Sources/SSApp/Shell/AppCommands.swift`, `CommandActions.swift`, `Sources/SSApp/Strings/AppStrings.swift`, `Tests/SSAppTests/Matches/`, `Tests/SSAppTests/Generate/`, `Tests/SSAppTests/Shell/` |
| T4.5d Duplicate without scorers | `core-dev` | sonnet · effort low | `Sources/SSData/Matches.swift` (`duplicate` only), `Tests/SSDataTests/MatchRepositoryTests.swift` |

T4.5a, T4.5c and T4.5d run in parallel after Step 1 and share nothing but the contract. T4.5b can start in parallel
(HTML against `ss-tool preview` with the new fixture) but adds its golden image only after T4.5a is merged, because
`RenderService.preview` picks the recap fixture only from T4.5a on; it merges after T4.5a.

**Gate:** `Scripts/check.sh` green on each branch; `qa-reviewer` (sonnet, medium) per task; visual QA of
`story-results` (rows, long names, 0–0, 10–0, postponed row, page label with 13 rows). Before T4.5b merges, the CI
golden comes from the "Update goldens" workflow run on its branch (the orchestrator commits the artifact into
`Tests/IntegrationTests/.golden/ci/`); without it CI fails by design. After all merges: one run with the user on the
Dev data (`Scripts/run.sh`): enter a half-time score, share the story to the phone with AirDrop, then the final
score and the recap.

---

## T4.5a — Recap engine

| | |
|---|---|
| **Agent / model** | `render-engineer` · sonnet · effort low |
| **Depends on** | Step 1 |
| **Size** | S |

**Features**

1. **Planner.** In `RenderPlanner.items(for:details:)`, a template with `manifest.isResultsRecap` gets one set of
   pages over all its matches (sorted by `MatchDetail.scheduleOrder`, sliced by `pageSize`), `PlannedImage.date` =
   the first match date, file names `renderFileName(date: first, templateID:, page:)`. Other list templates keep one
   set per day; single templates are unchanged. The default plan is unchanged (no recap in it).
2. **Title and date label** (decision 4) in `ContextBuilder.pages(_:)` when the manifest is a recap; the two titles
   in `RenderStrings`. The programme keeps "Oggi in campo" / "Weekend in campo".
3. **Warnings in a recap.** A postponed or cancelled row gives neither `.matchNotScheduled` nor the missing-score
   warning; a scheduled or played row without a score gives the missing-score warning (`requires: [score]`), as
   today (a scheduled match without a score in the recap shows "–"). Other warnings (cut names, missing logo file) as today.
4. **Fixture choice.** `FixtureContexts.standardFile` chooses by manifest: recap → `list-results.context.json`, other
   lists → `list.context.json`, singles → `single.context.json` (replace the `kind` overload or keep it and add one;
   update both callers, `TemplateRenderService.preview` and `ss-tool demo-render`). `demo-render --all` renders a
   recap with `list-results` and `list-23`.
5. Rows carry `outcome` through `MatchContext.init` (C1); nothing to compute here. Check it in a test.

**Acceptance criteria**

- A recap selection with 3 matches on Saturday and 5 on Sunday (pageSize 10) plans **one** image dated Saturday,
  `<saturday>_story-results_1of1.png`, title "Risultati del weekend", date label "Dal 14 al 15 novembre"; with 13
  matches two pages 1/2 and 2/2, both dated Saturday.
- The same matches with the programme template still give one set per day, titles unchanged.
- One-day recap: "Risultati" and the long date. A selection spanning two weekends: "Risultati" and the range.
- A postponed row in a recap: no warning; a scheduled row without score: exactly one missing-score warning.
- `preview(templateID: "story-results", matchIDs: [])` builds its context from `list-results.context.json`.
- Regenerating a recap record (`regenerateRecord`) plans one set again, not one per day.

**Tests (Swift Testing)**

- `RenderPlanTests`: the cases above with an in-memory template store holding a recap manifest, plus "default plan
  never includes a recap".
- `ContextBuilderTests`: titles and labels, recap warnings, `outcome` on rows (win, 0–0 draw, loss, none).
- Fixture choice for the three manifest shapes. Existing tests stay green.

---

## T4.5b — Recap template "Story · Risultati del weekend"

| | |
|---|---|
| **Agent / model** | `template-converter` · sonnet · effort medium |
| **Depends on** | Step 1 (fixture and manifest); T4.5a merged before the golden image |
| **Size** | S |

**Features**

1. `Resources/Templates/story-results/` with `manifest.json` **identical** to C6, `template.html`, and `assets/`
   (the Barlow fonts with `OFL.txt` and `club-logo.png`, copied from `story-programme`). Same visual family as
   `story-programme`: header with crest, `{{title}}` and `{{dateLabel}}`, up to 10 rows, footer with
   `{{club.handle}}`, `{{pageLabel}}` inside `{{#hasPages}}`.
2. **Row:** `{{category}}`; home side then away side (`home` / `away`, logo or initials circle, `displayName`), our
   side emphasised with `{{club.accent}}` through `{{#isUs}}`; between them the score `{{home.score}} – {{away.score}}`
   inside `{{#hasScore}}`; else "Rinviata" in `{{#isPostponed}}`, "Annullata" in `{{#isCancelled}}`, "–" otherwise.
   Outcome marker: `class="outcome outcome-{{outcome}}"` inside `{{#outcome}}`, with the letter V / N / P (win in
   the accent colour, draw neutral, loss dark), so it is not colour alone.
3. Zeros show (`0 – 0`): score blocks are wrapped in `{{#hasScore}}`, never in a section on a score.
4. Rules of `docs/TEMPLATES.md`: one root element of exactly 1080×1920, relative paths only, **no external URL**,
   text upper-cased in CSS, no logic beyond sections.
5. `docs/TEMPLATES.md`: the recap combination (`kind: list` + `purpose: fulltime`, one set per selection, the two
   titles), the `outcome` field, and the "Rinviata / Annullata" pattern.
6. Golden image: `story-results` added to `GoldenImageTests.templateIDs` and the local golden written with
   `UPDATE_GOLDEN=1` after rebasing on T4.5a.

**Acceptance criteria**

- `swift run ss-tool preview Resources/Templates/story-results Resources/Fixtures/list-results.context.json` renders
  1080×1920 with all 10 rows inside the layout: the 45-character name cut by the limit, 10–0 fits, 0–0 shows zeros,
  the postponed row reads "Rinviata", the no-logo opponent shows initials, V / N / P markers right.
- With `list-23.context.json` (sliced to 10 rows by the tool) nothing overflows; with a 2-page context the page
  label shows.
- `ss-tool demo-render` renders it with no `FAIL`; the template installs through `TemplateStore.install` with no
  problem; no request leaves the page (renderer content rules).

**Tests:** the golden image (local set; CI set via the workflow, see Gate). No other code.

---

## T4.5c — Results UI

| | |
|---|---|
| **Agent / model** | `ui-dev` · sonnet · effort medium |
| **Depends on** | Step 1 |
| **Size** | M |

**Features**

1. **Entry points** for one selected match that is scheduled or played: row context menu "Risultato…", a
   "Risultato…" button at the top of the inspector, and Immagini › "Risultato…" (⌥⌘R) published by Partite
   (`ShellCommand.enterResult`). Disabled, with a help text, for postponed and cancelled matches.
2. **Sheet "Risultato"** (`ResultSheet`): headline = team name and the two sides in fixture order, the long date.
   Fields in **fixture order** (home on the left, labelled with the side names, so an away match is typed as read on
   the scoreboard): "Primo tempo" [ ] – [ ], "Finale" [ ] – [ ], "Marcatori" (multi-line, stored in `notes`,
   placeholder "Rossi 23', Bianchi 78'"). Mapping to `Score(us:them:)` by `isHome` in `ResultFormState` (pure).
   Focus starts in the half-time home field when there is no half-time score yet, else in the final home field.
   Buttons: **Annulla** (Esc), **Salva** (Return), **Genera intervallo** (enabled with a complete half-time score),
   **Genera finale** (enabled with a complete final score). Each "Genera" saves first.
3. **Saving:** the existing match's draft with the three values changed, `normalized()` and `validate()` (problems
   next to the field), plus decision 11 (message "Il finale non può avere meno gol del primo tempo") and decision 10.
   Nothing else changes (time, venue, source, lock). Through `MatchRepository.update`; then the Partite list and the
   inspector show the new values and `app.didChangeData()` is called.
4. **Template choice** per decision 12; the remembered ids under keys of your own in `UserDefaults`. Under the
   buttons, the plan warnings of the chosen template for this match (`RenderService.plan` with the explicit
   selection), informational only.
5. **Generating:** `RenderRequest(from: date, to: date, selections: [TemplateSelection(templateID:, matchIDs: [id])])`,
   consuming `render`. A progress indicator in the sheet, the buttons disabled, Esc cancels the render (the saved
   result stays). `.imageFailed` or a thrown error → an alert in the sheet with the message; the sheet stays open.
   Success → the sheet closes and the share picker opens with the file (decision 13).
6. **Recap ("Riepilogo risultati"):** a button at the trailing edge of the Partite summary bar, shown when the
   selected weekend (`app.weekend`, Saturday–Sunday, every team, ignoring Partite's filters, search and scope) has at
   least one match with a final score; and Immagini › "Riepilogo risultati del weekend" (`ShellCommand.resultsRecap`,
   published by Partite, same condition). Matches per decision 5, template per decision 12, request
   `RenderRequest(weekend: app.weekend, selections: [ … ])`. Progress in the summary bar with **Annulla**; on success
   the share picker opens with every page; failures through `app.present`.
7. **Genera:** `GenerateViewModel.isEligible` gives a recap template every match (the pre-match rule unchanged). Nothing else changes in Genera.
8. Inspector label "Note" → "Marcatori e note". All new text in `MatchesStrings` / `AppStrings` (Italian).
   VoiceOver labels on the score fields ("Gol Sergnanese, primo tempo", …) and on the outcome of the work ("Storia
   dell'intervallo creata").

**Acceptance criteria** (against `AppServices.fake()`, a test share closure, render `delay` 0)

- Reference weekend, Prima Squadra at home (scheduled): Risultato…, half-time 1 – 0, Genera intervallo → stored
  `halfTime` us 1 them 0, status still scheduled, one new `story-halftime` record for that match, share called once
  with its file URL, sheet closed.
- Same match: final 2 – 1, Marcatori "Rossi 23', Bianchi 78'", Genera finale → status played, score us 2 them 1,
  notes stored, one `story-fulltime` record, share called once.
- Juniores away: typing home 0, away 3 stores us 3, them 0.
- Half-time 1 – 0 with final 0 – 1 → field problem, nothing stored, nothing rendered.
- Femminile (postponed): Risultato… disabled in the menu, the context menu and the inspector.
- Previous weekend (4 played matches): Riepilogo risultati → one `story-results` image with those 4 match ids, dated
  the Saturday, share called with 1 URL. Reference weekend before any score: the button is hidden and the menu item
  disabled.
- Genera with every match checked and `story-results` checked: its selection holds only matches with a score.
- Cancelling during a render: no share, the sheet stays open, the result stays saved. A render failure
  (`failingTemplateIDs`): alert, no share, result saved.
- Light and Dark Mode; keyboard: Tab through the fields in order, Return = Salva, Esc = Annulla / stop; VoiceOver
  reads the fields and buttons.

**Tests (Swift Testing)**

- `ResultFormState`: fixture-order mapping home/away, parsing (empty, half-filled, non-numeric, 100), final ≥
  half-time, played rule, initial focus.
- `ResultModel` with the fake: the acceptance cases above, template choice with 0 / 1 / several templates (install a
  second half-time template in the fake store) and the remembered choice, recap selection and its hidden/disabled
  state.
- `GenerateViewModel.isEligible` for the recap. `CommandAvailabilityTests` still pass with the two new commands.

---

## T4.5d — Duplicate without scorers

| | |
|---|---|
| **Agent / model** | `core-dev` · sonnet · effort low |
| **Depends on** | Step 1 |
| **Size** | XS |

`GRDBMatchRepository.duplicate` (`Sources/SSData/Matches.swift`) follows C4: `notes` cleared when the original has a
`score` or `halfTime`, kept otherwise. Tests: both cases; adjust the existing duplicate test only if its original has
a score, with the reason in the report.

---

## Step 3 — docs and release

`chore-runner` (haiku): USER-GUIDE subsection "Risultati: intervallo, finale e riepilogo" (the sheet, the two
buttons, AirDrop from the share picker, the recap, and that an import never erases a typed score).
`release-engineer`: next release.

**Plan edits for the orchestrator** (outside this sheet's owner): `03-mac-design.md` §4, Immagini menu: "Risultato…"
⌥⌘R and "Riepilogo risultati del weekend"; §5: the "Risultato" sheet as an accepted exception; `01-architecture.md`
§4: the recap combination; §5: `MatchContext.outcome`.

## Model and effort per step

| Step | Agent | Agent default | Dispatch with | Why |
|---|---|---|---|---|
| 1 contract | `foundation-architect` | opus, high | **opus, medium** | Small shapes, but C3 changes what every import writes; the rules and cases are fixed here. |
| T4.5a engine | `render-engineer` | opus, high | **sonnet, low** | One planner branch, two strings, a fixture choice; unit-testable, no WebKit change. |
| T4.5b template | `template-converter` | sonnet | **sonnet, medium** | Layout and overflow checked by eye on the previews. |
| T4.5c UI | `ui-dev` | sonnet, medium | **sonnet, medium** | A sheet, a render stream, the share picker, two commands, against fakes. |
| T4.5d duplicate | `core-dev` | sonnet, medium | **sonnet, low** | One condition and a test. |
| gate (each task) | `qa-reviewer` | opus, high | **sonnet, medium** | Fixed acceptance; visual QA of one template. |
| 3 USER-GUIDE | `chore-runner` | haiku | **haiku** | Prose only. |

Escalation is unchanged: retry once on the same model with the reviewer's findings, then one model up.

## Order with the other tasks

T4.5c edits `Shell/AppCommands.swift` and `CommandActions.swift`, which T4.4 (Shortcuts) will also touch, and
`MatchesView.swift`, used by the import tasks: do not run T4.5c in parallel with T4.4; merge one, rebase the other.
T4.6 (Captions) touches the gallery and Settings, not these files. Order: Step 1 → T4.5a ∥ T4.5c ∥ T4.5d ∥ T4.5b
(HTML) → T4.5b golden after T4.5a → gates → Step 3.

## Rules

- No database migration and no new stored field in this task. Scorers live in `notes`.
- A typed result is never erased by an import (C3) or carried to another match by duplicate (C4).
- One-click generation renders only what the user asked for (one match, or the weekend's scored matches) and writes
  nothing but the match being edited and the `RenderRecord`s.
- Templates render with the network blocked; the new template has no external URL. Fixtures and test names are
  invented.
- Dev data folder only (`Scripts/run.sh`); tests use `AppServices.fake()` or a temp `SS_DATA_DIR`.

## Open questions for the user

**Answered 2026-11-24:** 1 yes, 2 yes (story 1080×1920), 3 every match, 4 yes (import wins), 5 yes.


1. **Duplicate and notes (C4):** clear the notes of a duplicated match when the original has a score? Default yes.
   Alternative: keep today's behaviour and accept that scorers may be copied.
2. **Recap format:** a story 1080×1920 like the programme (default), or a feed post 1080×1350 (fewer rows per
   page, `pageSize` about 8)?
3. **Recap content:** every match of the weekend, including postponed and cancelled ("Rinviata" / "Annullata") and matches without a score ("–"). **Answered 2026-11-24: every match.**
4. **Import vs typed score (C3):** when the source has a different score from the one typed, the source wins and the
   row shows as changed (default). Should the typed score win instead?
