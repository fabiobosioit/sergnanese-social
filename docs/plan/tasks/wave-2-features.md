# Wave 2 — Features (5 tasks in parallel)

Five screens. Each one develops against the in-memory fakes (`Scripts/run.sh --mock`), so none waits for the database or the render engine. Real wiring happens in T3.1.

**Gate to Wave 3:** all five merged into `main`, `Scripts/check.sh` green, and with `Scripts/run.sh --mock` the whole weekly job can be done end to end: review matches → generate → share an image.

| Task | Agent | Model | Owns (under `Sources/SSApp/Features/` and `Tests/SSAppTests/`) |
|---|---|---|---|
| T2.1 Matches | `ui-dev` | sonnet | `Matches/**` |
| T2.2 Opponents and teams | `ui-dev` | sonnet | `Opponents/**`, `Teams/**` |
| T2.3 Settings | `ui-dev` | sonnet | `Settings/**` |
| T2.4 Templates | `ui-dev` | sonnet | `Templates/**` |
| T2.5 Generate and archive | `ui-dev` | sonnet | `Generate/**`, `Archive/**` |

Rules common to all five (details in `03-mac-design.md`):

- One `@MainActor @Observable` view model per screen, taking `AppServices`; views stay thin. Tests exercise the view model with `AppServices.fake()`.
- Publish the screen's actions to the menu bar through the focused-value keys from T1.6. Do not edit the shell.
- Every row and image has a context menu. Every list has an empty state and an error state.
- Strings in the feature's own `Strings` file.
- Before finishing, run `swift run ss-tool screenshots`, look at your screen in Light and Dark, and say what you saw.

---

## T2.1 — Matches (the review-and-edit screen)

| | |
|---|---|
| **Depends on** | T1.6 |
| **Size** | M–L |

This screen is decision D7: check and fix the weekend before generating.

**Features**

1. Toolbar: `WeekendSwitcher`, Aggiungi, filter menu (team, status), search, prominent **Genera**. The weekend is the shared one in `AppModel`.
2. A `Table` of the weekend's matches, sectioned by day, ordered by time. Columns: time, team, home/away marker, opponent with logo thumbnail, venue, round, status badge, warnings. Lock and source show as small icons with labels.
3. Selecting a row opens the **inspector** with the full form: team, opponent (searchable picker with "Nuovo avversario…" inline), date, time, home/away (switching to home pre-fills the venue with the club's home venue), competition, round, status, score and half-time score, notes, lock. Changes save when a field commits; validation problems show next to the field.
4. ⌘N adds a match for the shown weekend in a sheet with the same form.
5. Context menu and menu bar: Modifica, Duplica (to next week), Blocca/Sblocca, Rinvia (sets status postponed), Elimina (with confirmation). Multi-selection works for Blocca and Elimina.
6. Warnings per match, computed in the view model: no time, no venue, opponent without logo, opponent name that will be cut (using `displayName` and the smallest `teamName` limit among installed templates). A summary line: "N partite, M con avvisi". The sidebar badge shows M.
7. **Genera** (toolbar, ⌘R) switches to the Genera section for the shown weekend.
8. Empty state: "Nessuna partita in questo weekend" with "Aggiungi partita" and, when the database has no matches at all, "Carica dati demo".
9. Tests: form validation, warning logic, duplicate date maths, filter + search.

**Acceptance**

- [ ] With fakes: add, edit, duplicate, delete, lock all work and the table refreshes.
- [ ] Warnings appear for the fixture match with the 45-character opponent and the one without a logo.
- [ ] Keyboard only: arrows move the selection, Tab walks the inspector, ⌘N / ⌘D / ⌘⌫ work, Esc closes the sheet.
- [ ] VoiceOver reads a row as one sentence.
- [ ] `Scripts/check.sh` passes.

---

## T2.2 — Opponents and teams

| | |
|---|---|
| **Depends on** | T1.6 |
| **Size** | M |

**Features**

1. **Avversari**: searchable `Table` (logo, name, short name, number of matches). Inspector to edit name, short name, aliases (token field), and the logo through `LogoWell` (drop, paste, choose, remove). A live "Come apparirà" line shows `displayName` cut to the smallest template limit, so the user sees at once whether a short name is needed.
2. ⇧⌘N and the toolbar + create an opponent in a sheet.
3. Delete asks for confirmation; when the opponent has matches, the repository's conflict message is shown in an alert and nothing is deleted.
4. **Squadre**: a `List` reordered by drag (`onMove`), each row with name, short label, an "attiva" toggle and a first-team marker (exactly one; choosing another moves it). Add, rename inline, delete with the same guard.
5. Tests: one per screen for create, for a validation error, for the delete guard; team reordering persists the new `sortOrder`.

**Acceptance**

- [ ] With fakes: full create/edit/delete cycle on opponents and teams; reorder persists.
- [ ] A PNG dragged from Finder and an image dragged from Safari both set the logo; ⌘V with an image on the clipboard does too.
- [ ] Only shared components and standard controls are used.
- [ ] `Scripts/check.sh` passes.

---

## T2.3 — Settings

| | |
|---|---|
| **Depends on** | T1.6 |
| **Size** | S |

The Settings window (⌘,), a `TabView` with `Form`s in the standard macOS settings style.

**Features**

1. **Società**: club name, short name, season, social handle, home venue.
2. **Immagini**: template accent colour (`ColorPicker` + hex field, with "Ripristina rosso Sergnanese"); output folder shown as a path control with "Scegli…" (system folder picker, `fileImporter`) and "Mostra nel Finder".
3. **Dati**: the data folder path with "Mostra nel Finder", the date of the last automatic backup, "Carica dati demo" / "Rimuovi dati demo", the app version.
4. Changes apply immediately (no Save button), as in system settings; invalid values show a problem under the field and are not saved.
5. Tests: load/save round trip, hex colour validation, output folder change.

**Acceptance**

- [ ] With fakes: every setting saves and is there after closing and reopening the window.
- [ ] The window has the standard settings look, no custom chrome, and works in Dark Mode.
- [ ] `Scripts/check.sh` passes.

---

## T2.4 — Templates

| | |
|---|---|
| **Depends on** | T1.6 |
| **Size** | M |

**Features**

1. A grid of template cards: thumbnail at the right aspect ratio, name, format badge (Post 1080×1350 / Story 1080×1920), kind (singola / elenco), version, "integrato" badge for built-ins.
2. Import with ⌘O / the toolbar (a `.zip` or a folder) and by dropping one on the grid. Validation problems are listed in a sheet; on an id clash ask "Sostituire?".
3. Inspector for the selected template: large preview, manifest fields, the `limits`, the required fields.
4. "Anteprima con una partita": pick a match (or a weekend, for list templates) and show the real render through `RenderService.preview`; Space opens it in Quick Look.
5. Context menu: Anteprima, Mostra nel Finder, Elimina (user templates), Ripristina (built-ins).
6. A help link to the template-writing guide.
7. Tests: list, import success, import with problems, clash handling, delete vs restore rules.

**Acceptance**

- [ ] With fakes: list, import success, import with problems, preview, delete, restore.
- [ ] Dropping a folder and dropping a zip both start the import.
- [ ] `Scripts/check.sh` passes.

---

## T2.5 — Generate and archive

| | |
|---|---|
| **Depends on** | T1.6 |
| **Size** | L |

**Features — Genera**

One screen, not a wizard: choices on the left, the result on the right.

1. Left column, top: `WeekendSwitcher` (shared weekend; default next weekend).
2. Left column, **Partite**: the weekend's matches as a checklist, pre-selected by the plan's default rules; warnings per match with a "Modifica" button that jumps to the match in Partite; skipped (postponed/cancelled) matches greyed.
3. Left column, **Template**: a checklist of templates, each with a line saying what it will produce ("Story programma: 2 immagini (12 partite)", "Post pre-partita: Prima Squadra vs …").
4. A live summary from `RenderService.plan`: total images and all warnings, updated as choices change, before anything is generated.
5. **Genera immagini** (prominent toolbar button, ⌘R, default action): runs `RenderService.render`, shows a determinate progress bar in the window and on the Dock icon, with **Annulla**. Disabled, with the reason shown, when no match or no template is selected. Warnings never block.
6. Right side: `ImageGallery` of the results as they arrive. Selection, Quick Look, share (AirDrop), drag-out, copy, Mostra nel Finder, Rigenera — all from the shared component, the context menu and the Immagini menu. A "Condividi tutte" toolbar button shares the whole set.

**Features — Archivio**

7. Past renders grouped by weekend in the same `ImageGallery`, with a date-range menu and a template filter. Same actions, plus "Elimina dall'archivio" (asks whether to move the file to the Trash as well).
8. Records whose file no longer exists on disk are shown with a "file mancante" badge and can be removed or regenerated.

**Tests**

9. View-model tests for the plan summary and the selection logic with zero matches, one match, twelve matches; progress and cancellation with the fake renderer; archive grouping and filters.

**Acceptance**

- [ ] With fakes: the full flow from weekend to gallery works, including the two-page programme case.
- [ ] Sharing a selection offers AirDrop; dragging two thumbnails to Finder copies two PNG files.
- [ ] Cancelling mid-run keeps the images already made and stops cleanly.
- [ ] `Scripts/check.sh` passes.
