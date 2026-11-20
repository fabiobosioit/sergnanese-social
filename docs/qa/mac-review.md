# T3.2 Part B: Mac review of the app

- First run: `main` at `6a27429` (after T3.1 and T3.3), 2026-11-18.
- Re-check: `main` at `b0ce149` (after the T3.2 UI fixes for M1–M4, M7–M10, M12, M13), 2026-11-18. See [Re-check](#re-check-after-the-fixes).
- Reviewer: `qa-reviewer`. This file is a report. It does not fix anything; fixes go to the owner shown in each row.
- Verdict after the re-check: **no blocking UI row is open.** All the fixed rows check out in source and in the screenshots. M5, M6 and M11 were left for the user on purpose. M1 is fixed in source, but only U3 can prove it in the running app. The release gate still needs the by-hand list (U1–U5) at the end. On the image side, V1 (blocking) is fixed; see `visual-report.md`.

## Re-check after the fixes

- `Scripts/check.sh` passes on `b0ce149`: build with warnings as errors, format lint, 321 tests.
- `swift run ss-tool screenshots` with `SS_DATA_DIR` set to a temp folder → `out/screens/<screen>-<light|dark>.png`. I opened
  Light and Dark for Partite, Genera, Squadre, Avversari, Impostazioni, and Archivio in Light. Neither
  `~/Library/Application Support/Sergnanese Social` nor `… Dev` exists after the run.
- The screenshots still do not show the toolbar, menus, inspectors, the Immagini tab of Settings or the empty Archivio. Those
  rows were checked in the source only.

| ID | Status | Evidence |
|---|---|---|
| M1 | **Fixed in source**, U3 to confirm | `GenerateView.swift:292`: `.keyboardShortcut(model.results.isEmpty ? .defaultAction : nil)`. Once there are results, the toolbar button is no longer the default action, so Return goes to the gallery's key handler (`ImageGallery.swift:233`, Space/Return → Quick Look). With no results, Return still starts a run. No automated test can press Return in the window, so U3 stays on the by-hand list. |
| M2 | **Fixed** | New `defaultPlanWarnings` (`Features/Matches/RowWarnings.swift`) takes the name-cut warnings from the weekend's default plan, so each match is checked against the templates it will really go into. Used by the Partite rows, the Avvisi column and the sidebar badge (`MatchesViewModel.swift:56,71`, `AppModel.swift:79`). Genera uses `plan.warnings` for the current selection (`GenerateViewModel.swift:159`). Screenshots: the badge is now 4 (was 7). Partite says "10 partite, 4 con avvisi". Genera lists 4 warnings and its footer says "4 avvisi". `U.S. Castelverde Calcio` (Allievi U17, programme only) no longer gets a false warning (`matches-light.png`, `generate-light.png`, Dark the same). Gap: no test asserts that a programme-only match with a 17–22-character name has *no* name warning. The updated `AppModelTests` compares the badge with the same function, so it would pass even if the function were wrong. |
| M3 | **Fixed** | `TeamsView.swift:129` `.labelsHidden()`; the accessibility label (`:132`) and the help text stay. `teams-light.png` / `-dark.png`: only the switches show; Veterani's switch is off with no "Attiva" text next to it. |
| M4 | **Fixed** | `TeamsView.swift:68` uses `TeamsStrings.deactivate`. No other inline Italian found in `Sources/SSApp/Features/**` views (grep of `Text/Button/Label/Toggle/help("…")` outside `*Strings.swift`; only the dev-only `ScreenshotSupport.swift` component gallery has literals). |
| M7 | **Fixed** (source) | `ArchiveView.swift:29-35`: `ContentUnavailableView` with the action "Vai a Genera" (`ArchiveStrings.goToGenerate`) → `app.open(.generate)`. The empty state is not in the screenshot set (the demo archive has images). |
| M8 | **Fixed** | `MatchesView.swift:109` width 72–100 (ideal 84). The header reads `Casa/Fuori` in full in `matches-light.png` and `-dark.png`. |
| M9 | **Fixed** | `OpponentsView.swift:156-160`: initials in a 22-pt `.quaternary` circle. `opponents-light.png` / `-dark.png`: `AM` and `BL` now match the circles in Partite. |
| M10 | **Fixed** | `GenerateView.swift:156`, `GenerateStrings.timeToBeDefined`. `generate-light.png`: "Sab 21 nov, orario da definire, in trasferta" (Pulcini – Prato Fiorito). |
| M12 | **Fixed** (source + test) | Same fix as V2: `SettingsModel.swift:40-60`, `SettingsView.swift:83`, text in `SettingsStrings.accentTooLight`; triangle label in `.secondary` with a multicolour symbol, so it reads in both modes. Test `lightAccentWarnsAboutWhiteText`. The Immagini tab is not captured by `ss-tool screenshots`: look at it in U1. |
| M13 | **Fixed** | `SettingsStrings.swift:20`: `passa a «in casa»`. Visible in `settings-light.png` / `-dark.png`. |
| M5, M6, M11 | Not re-checked (skipped by design) | Still open. They depend on U1 (M5), on a decision about the toolbar (M6) and on U2 (M11). |

Also changed in the same fix, checked: the Partite venue column is now titled "Luogo" (`MatchesStrings.columnVenue`), and the
"Guida ai template" link points to `docs/TEMPLATES.md` (`TemplatesStrings.swift:21`).

## Method and limits (first run)

- `Scripts/check.sh` passes on this commit: build with warnings as errors, format lint, 315 tests.
- `swift run ss-tool screenshots` (fake data, Light and Dark) → `out/screens/<screen>-<light|dark>.png`. I opened all 18 images. The tool does not capture the toolbar, the menu bar, inspectors, sheets or popovers. Those were checked in the source only.
- Source review of `Sources/SSApp/**` and `Sources/SergnaneseSocial/**` against `03-mac-design.md` and the `macos-design-guidelines` checklist.
- Running app: I built the debug bundle and launched it with `--mock` and a temp `SS_DATA_DIR`. I could not read its menu bar, because `osascript` is not allowed assistive access on this Mac. So every "menu item exists / is disabled" result below is **from source**, and the user should confirm it (item U1 at the end).
- Nothing touched `~/Library/Application Support/Sergnanese Social/` or `… Dev/`. Neither folder exists after the run. Every command ran with a temp `SS_DATA_DIR`.

## Problems

| ID | Where | What is wrong | Screenshot | Suggested fix | Owner | Blocking | Status (re-check `b0ce149`) |
|---|---|---|---|---|---|---|---|
| M1 | `Features/Generate/GenerateView.swift:291`, `Components/ImageGallery.swift:233` | In Genera, Return is used twice. The toolbar button "Genera immagini" is the window's default action (`.keyboardShortcut(.defaultAction)`), and the gallery opens Quick Look on Return. Key equivalents are handled before the focused view's key handler. So selecting an image after a run and pressing Return probably starts the whole weekend render again instead of opening Quick Look. Not verified, because I could not drive the app. | n/a | User check U3. If confirmed: remove Return from the gallery's Quick Look keys (keep Space, ⌘Y, double-click) and update the gallery's doc comment, or drop `.defaultAction` while results are shown. | `ui-dev` | No, but **blocking if U3 confirms it** | **Fixed in source** (`.defaultAction` dropped while results are shown). U3 confirms |
| M2 | `Features/Generate/GenerateViewModel.swift:157`, `Shell/AppModel.swift:79`, `Features/Matches/MatchesViewModel.swift:70` | Per-match warnings use the smallest `teamName` limit of **all** installed templates (16), not the limit of the templates the match will actually be rendered with. Youth matches that only go into the programme (limit 22) get a false "Il nome «U.S. Castelverde Calcio» verrà accorciato in «Castelverde…»". In Genera the list shows 8 or more warnings while the footer says "3 immagini da generare · 4 avvisi". The Partite badge and the Avvisi column count the same false positives (the badge shows 7). Users will set short names they do not need. | `out/screens/generate-light.png`, `out/screens/matches-light.png` | In Genera, build the row warnings from `plan.warnings` for that match plus the warnings that do not depend on a limit. For the badge and the Matches column, use the limits of the templates the default plan would use for that match (programme for all matches, pre-match post for the first team). | `ui-dev` | No | **Fixed** (missing negative test, see above) |
| M3 | `Features/Teams/TeamsView.swift:125` | The "Attiva" switch keeps its visible label on every row. Inactive teams read "Attiva" next to a switch that is off (see Veterani). | `out/screens/teams-light.png`, `-dark.png` | Add `.labelsHidden()` (the accessibility label stays), and add a column header or the help text. | `ui-dev` | No | **Fixed** |
| M4 | `Features/Teams/TeamsView.swift:68` | `Button(team.isActive ? "Disattiva" : …)` puts Italian text inline in a view. This breaks the `Strings` rule in `CLAUDE.md`. | n/a | Move it to `TeamsStrings`. | `ui-dev` | No | **Fixed** |
| M5 | `Shell/AppCommands.swift:67`, `:72` | The Modifica menu probably shows two "Elimina" items (the system pasteboard "Elimina" and ours with ⌘⌫) and two Find entries (the system "Trova ▸ Trova… ⌘F" and our "Trova ⌘F"). Not verified live. | n/a | User check U1. If duplicated: use `CommandGroup(replacing: .pasteboard)` and keep the standard items plus Duplica/Elimina. Replace the system Find group (`CommandGroup(replacing: .textEditing)`) or drop our item and publish through the standard one. | `ui-dev` | No | Open, waiting for U1 |
| M6 | `Features/Archive/ArchiveView.swift:147-170`, `Features/Templates/TemplatesView.swift:186-205` | Missing from the toolbars in §3: Archivio has no search field and no Condividi button (sharing works from the menu and the context menu). Template has no search field. | `out/screens/archive-light.png`, `templates-light.png` | Add `.searchable` and a `ShareLink` for the selection, or record the deviation in `03-mac-design.md`. With four templates and a few archive weeks this is low value. | `ui-dev` | No | Open (skipped by design) |
| M7 | `Features/Archive/ArchiveView.swift:29` | The empty Archivio uses `ContentUnavailableView` without an action. §8 asks for one clear action. | n/a | Add "Vai a Genera" (`app.open(.generate)`). | `ui-dev` | No | **Fixed** (source) |
| M8 | Partite table, column `Casa/Fuori` | At the default width the header is cut to `Casa/…`. | `out/screens/matches-light.png` | Use a shorter header (for example "C/T", with the full words as help), or a larger ideal width. | `ui-dev` | No | **Fixed** |
| M9 | `Features/Opponents/OpponentsView.swift` logo column | Opponents without a logo show bare initials. Partite shows the same initials in a grey circle. The two screens are inconsistent. | `out/screens/opponents-light.png` vs `matches-light.png` | Reuse the circle from `OpponentCell`. | `ui-dev` | No | **Fixed** |
| M10 | `Features/Generate/GenerateView.swift:156` | A match with no time gets the subtitle "Sab 21 nov, —, in trasferta". | `out/screens/generate-light.png` | Write "orario da definire" (a `GenerateStrings` entry) instead of the dash. | `ui-dev` | No | **Fixed** |
| M11 | `Components/ImageGallery.swift:160` | `.draggable(image.url)` drags only the clicked thumbnail. §6 says a selection of one or more images can be dragged out. | n/a | User check U2. If several images are wanted: drag the selection, for example through an `NSItemProvider` per file. | `ui-dev` | No | Open, waiting for U2 |
| M12 | Settings › Immagini, accent colour | No readability check on the accent colour. See V2 in `visual-report.md`. | `out/qa/single/story-halftime/s27-accent-light.png` | Inline warning below 3:1 contrast with white. | `ui-dev` | No | **Fixed** (source + test) |
| M13 | `Features/Settings/SettingsStrings.swift:20` | Straight quotes in the Italian text: `passa a "in casa"`. | `out/screens/settings-light.png` | Use «in casa». | `ui-dev` | No | **Fixed** |

## `03-mac-design.md`, section by section

"Pass (source)" means the code does what the spec asks, but the item cannot be seen in the screenshots. "User" means only someone using the app can confirm it. The by-hand list says how. Status updated for the re-check where a fixed row applies.

### §1 Window

| Item | Status | Evidence |
|---|---|---|
| One `Window` scene, not `WindowGroup` | Pass (source) | `Shell/ShellScenes.swift:15` |
| Closing the window quits | Pass (source) | `ShellDelegate.applicationShouldTerminateAfterLastWindowClosed` |
| Minimum 900×600, default 1200×760 | Pass (source) | `RootView.swift` `.frame(minWidth: 900, minHeight: 600)`, `.defaultSize(width: 1200, height: 760)` |
| Size and position remembered | User | `Window(id: "main")`. U1 |
| Standard title bar, traffic lights, unified toolbar, full screen | Pass (source) / user | No custom chrome anywhere. U1 |
| Settings scene with ⌘, | Pass (source) | `Settings { SettingsView }` |
| Window title is the section | Pass (source) | `.navigationTitle(model.section.title)` |

### §2 Sidebar

| Item | Status | Evidence |
|---|---|---|
| `NavigationSplitView`, `.listStyle(.sidebar)`, sections Weekend / Libreria, the six SF Symbols | Pass | `RootView.swift`, `AppSection.swift`, all `out/screens/*` |
| Collapsible | User | U1 |
| Badge on Partite = matches with warnings | Pass (M2 fixed) | `matches-light.png` shows 4, the same as "4 con avvisi" |
| Settings not in the sidebar | Pass | screenshots |
| Selected section remembered | Pass (source) | `AppModel.persistSection` |
| Icon alignment | User | In the off-screen screenshots the wide `person.3` icon touches the "Squadre" label (still so on `b0ce149`). Check in the real window (U1) |

### §3 Toolbar

| Section | Status | Evidence |
|---|---|---|
| Partite: switcher, Aggiungi, filter menu, search, Genera (prominent) | Pass (source) | `MatchesView.swift` toolbar, `.searchable(placement: .toolbar)` |
| Genera: switcher, Genera immagini (prominent, default) | Pass (source) | plus "Condividi tutto". Default action only while there are no results (M1 fix) |
| Archivio: date range, template filter, Condividi, search | Partial | Condividi and search missing (M6) |
| Avversari: Aggiungi, search | Pass (source) | plus an inspector toggle |
| Squadre: Aggiungi | Pass (source) | |
| Template: Importa, search | Partial | search missing (M6); also "Guida" and an inspector toggle |
| Every item is a `Label` (icon + text) | Pass (source) | "Icon and Text" mode: U1 |

### §4 Menu bar (from source; confirm in U1)

| Menu | Item | Shortcut | Status |
|---|---|---|---|
| App | Informazioni su Sergnanese Social | | Pass (`CommandGroup(replacing: .appInfo)`) |
| App | Impostazioni… | ⌘, | Pass (Settings scene) |
| File | Nuova partita | ⌘N | Pass. Enabled only where published (Partite) |
| File | Nuovo avversario | ⇧⌘N | Pass (Avversari) |
| File | Importa template… | ⌘O | Pass (Template) |
| File | Carica dati demo | | Pass. Always enabled; loading twice is safe (`SeedLoader.load` replaces the seed matches) |
| File | Apri cartella immagini | ⇧⌘O | Pass (creates the folder, then opens it) |
| File | Chiudi | ⌘W | System |
| Modifica | Annulla … Seleziona tutto | standard | System |
| Modifica | Duplica | ⌘D | Pass (Partite, disabled without a selection) |
| Modifica | Elimina | ⌘⌫ | Pass (disabled without a selection). Possible duplicate (M5) |
| Modifica | Trova | ⌘F | Pass (Partite, Avversari). Possible duplicate (M5) |
| Vista | Partite … Template | ⌘1–⌘6 | Pass |
| Vista | Weekend precedente / successivo | ⌘[ / ⌘] | Pass. Disabled outside Partite, Genera, Archivio |
| Vista | Questo weekend | ⌘T | Pass. Also disabled when already on this weekend |
| Vista | Mostra/Nascondi barra laterale | ⌃⌘S | User (provided by the system for split views; `SidebarCommands` is not added) |
| Vista | Attiva modalità a tutto schermo | ⌃⌘F | System |
| Immagini | Genera immagini del weekend | ⌘R | Pass (Partite opens Genera; Genera runs, disabled while it cannot) |
| Immagini | Anteprima rapida | ⌘Y (Space in the grid) | Pass |
| Immagini | Condividi… | | Pass (`NSSharingServicePicker`) |
| Immagini | Copia immagine | (⌘C through Modifica › Copia) | Pass. The deviation is documented in `AppCommands.swift` |
| Immagini | Mostra nel Finder | ⇧⌘R | Pass |
| Aiuto | Guida di Sergnanese Social | ⌘? | Pass (opens `docs/USER-GUIDE.md` on GitHub) |
| Aiuto | Scarica aggiornamenti… | | Pass (Releases page) |
| Aiuto | Apri cartella dati | | Pass |

Menus act through `@FocusedValue` (`publishCommand`). No feature edits `AppCommands`. Pass.

### §5 Lists, selection, editing

| Item | Status | Evidence |
|---|---|---|
| Table/List with click, ⌘-click, ⇧-click, arrows | Pass (source) | Matches and Opponents use `Table(selection: Set)`. The gallery has its own selection (`GallerySelection`, tested). Teams is single selection |
| Editing in an inspector for matches and opponents | Pass (source) | `.inspector` in both |
| Sheets only for new items and the import report | Pass (source) | `NewMatchSheet`, opponent and team create sheets, `ImportProblemsSheet` |
| Double-click / Return opens for editing | Pass (source) | `contextMenu(forSelectionType:primaryAction:)` in Matches and Opponents |
| Context menu on every row and image | Pass (source) | Matches, Opponents, Teams, Templates, gallery, Genera rows |
| ⌫ asks for confirmation, destructive button, Esc cancels | Pass (source) | `confirmDelete` (`FormHelpers.swift`) and `confirmationDialog` in Archivio and Template |
| No alert on routine saves | Pass (source) | Alerts only appear for `errorMessage` |
| Teams reorder by drag | Pass (source) | `.onMove`, plus Sposta su/giù in the context menu |

### §6 Getting images out

| Item | Status | Evidence |
|---|---|---|
| Quick Look (Space, ⌘Y, double-click) | Pass (source); Return too after M1 fix | `quickLookPreview` (`ImageGallery.swift:113`). U3 |
| Condividi → AirDrop, Messages, Mail, Foto | User | U2 |
| Drag to Finder, Photos, Messages, browser | User, see M11 | U2 |
| ⌘C copies the image | Pass (source) | `onCopyCommand` + `ImageActions.copy` writes the image and the file URL |
| Mostra nel Finder | Pass (source) | |
| Drop a logo, paste with ⌘V, drop a template folder or zip | Pass (source) | `LogoWell.onDrop/onPasteCommand`, `TemplatesView.dropDestination`. Behaviour: U2 |

### §7 Appearance

| Item | Status | Evidence |
|---|---|---|
| Light and Dark both work | Pass | All screens in both modes on `b0ce149`; no unreadable or fixed-colour surface |
| No fixed colours on surfaces or text | Pass | Only semantic system colours (`.yellow` warning, `.red`/`.orange`/`.green` status, `.secondary`, `.quaternary`, `controlBackgroundColor`, `systemGray`). The selected caption is white on accent, as in Finder |
| System font, semantic styles | Pass, one exception | `MatchesView.swift:288` uses `.system(size: 9)` for initials in a 22-pt circle (acceptable) |
| System accent for selection and default buttons | Pass | Club red appears only in images and the icon |
| Neutral mid-grey mat behind thumbnails | Pass | `ImageGallery.swift:127`, `archive-*.png`, `gallery-light.png` |
| Reduce Motion / Transparency / Increase Contrast | Pass (source) | No custom animation, standard materials |

### §8 Feedback

| Item | Status | Evidence |
|---|---|---|
| Determinate progress in the window and on the Dock, one bounce in the background, no success alert | Pass (source) | `GenerateView.runProgress`, `DockProgress` (`requestUserAttention(.informationalRequest)` only when inactive), the result is inline status text |
| Inline warnings with a yellow triangle and a one-click fix | Pass (M2 fixed) | `WarningLabel`, Modifica link in Genera; list and footer agree (4 and 4) |
| Errors in a standard alert | Pass (source) | Startup failure alert with "Mostra cartella dati" (`main.swift`); screen errors in `.alert` |
| Empty states with `ContentUnavailableView` and one action | Pass (M7 fixed) | Matches (Aggiungi partita / Carica dati demo), Opponents, Teams, Templates, Genera, gallery, Archivio (Vai a Genera) |
| Error states for lists | Pass (source) | Load-failed views with "Riprova" in Matches, Genera, Archivio, Opponents, Teams, Templates |

### §9 Accessibility

| Item | Status | Evidence |
|---|---|---|
| Icon-only buttons have Italian labels | Pass (source) | Weekend arrows, star (first team), alias +/-, lock/source icons, status badge, home/away marker, logo well, the label-less "Attiva" switch. No icon-only button without a label was found |
| Matches row read as one sentence | Pass (source) / user | `MatchesViewModel.rowSentence` on the first column, other cells hidden. U4 |
| Keyboard: Tab, arrows, Return, Esc | User | U5, U3 |
| Semantic text styles | Pass | see §7 |

### §10 App icon

| Item | Status | Evidence |
|---|---|---|
| Crest on a white rounded plate, `.icns` up to 1024 | Pass | `Packaging/AppIcon.icns` (all 10 sizes, plate and margins correct at 256 and 32 px) |

### §11 Deliberately skipped in v0.1.0

Spotlight, App Intents, widgets, notifications, undo for database edits, toolbar customisation: not present, as decided. Not counted as failures.

## `macos-design-guidelines` checklist (summary)

| Area | Result |
|---|---|
| Menu bar: standard menus, shortcuts, dynamic enable, context menus, App menu | Pass (source); M5 to confirm |
| Windows: resizable with a minimum, full screen, state restored, traffic lights | Pass (source) / U1. Multiple windows: N/A (single-purpose, §1) |
| Toolbars: present, labels; search | Pass, M6. Customisation: skipped (§11) |
| Sidebar: source list, collapsible | Pass / U1 |
| Keyboard: Tab, arrows, Esc, Return, Delete, Space for Quick Look | Pass (source); M1 fixed in source, U3, U5. Cmd-Z undo: skipped (§11, deletes confirm instead) |
| Pointer: hover, context menus, drag and drop, multi-select | Pass (source); M11, U2 |
| Notifications: none, no success alerts | Pass |
| System integration: Dock icon, Share | Pass / U2. Spotlight, App Intents: skipped (§11) |
| Visual: system font, Dark Mode, accent, materials | Pass |
| Accessibility: labels, Full Keyboard Access, Reduce Motion/Transparency, focus order | Pass (source) / U4, U5 |

## By-hand list for the user

An agent cannot do these. Run the release `.dmg`, or `Scripts/run.sh` (Dev data folder), load demo data, and press Genera once. Write what you see in the table at the end.

| # | Check | How | Expected |
|---|---|---|---|
| U1 | Menus and window | Open every menu. Look at Modifica and Vista in particular. Resize the window, quit and relaunch. Collapse the sidebar with ⌃⌘S. Set the toolbar to "Icon and Text". Enter full screen. Open Impostazioni › Immagini, type `#FFE066` in the colour code, then press "Ripristina rosso Sergnanese". | Every item of §4 is there with its shortcut and is greyed where it does not apply. **Only one** "Elimina" and one "Trova" (M5). The window reopens at the same size and place. Sidebar icons are aligned. With `#FFE066` a yellow-triangle warning "Colore troppo chiaro…" appears under the colour and goes away after the reset (M12/V2). |
| U2 | AirDrop and drag out | In Genera, select one image → Immagini › Condividi… → AirDrop → your phone. Then drag one thumbnail into Finder, into Photos, and into a browser upload field (for example a new Instagram/Facebook post on the web). Try dragging with two images selected. Drop a logo image from Finder and from a browser onto an opponent. ⌘V an image onto an opponent. Drop a template zip onto Template. | The PNG arrives on the phone at full size. Finder gets a copy of the PNG (not a link). The browser accepts the file. Note whether a multi-selection drags one image or all (M11). Logos and the zip are accepted. |
| U3 | Return in Genera | Before generating, press Return: a run starts. After it ends, click one thumbnail, then press Return. Press Space. | Return before a run starts the run. After the run, Return and Space both open Quick Look; **a new render must not start** (M1 fix). If it does, M1 is blocking again. |
| U4 | VoiceOver over the matches table | ⌘F5, go to Partite, move through the rows with VO-arrows. Also go to Squadre and move onto a switch. | Each row is read as one sentence: "Domenica 15:30, Prima Squadra contro …, in casa, 1 avviso". Icon buttons (weekend arrows, star, +/-) have Italian names. The team switch is read as "Attiva" with its state (M3). |
| U5 | Full Keyboard Access through Genera | System Settings › Accessibilità › Tastiera › Accesso completo da tastiera on. In Genera, Tab through the weekend switcher, Tutte/Nessuna, every match and template checkbox, Modifica links, Genera immagini, the gallery, Condividi tutto. Use the arrows in the gallery, then Esc. | Every control is reachable and shows a focus ring. No trap. The arrows move the selection; Esc clears it. |

## User findings

To be filled in by the user (T3.2 acceptance requires this before the task closes).

| # | Date | Result (ok / problem) | Notes |
|---|---|---|---|
| U1 | | | |
| U2 | | | |
| U3 | | | |
| U4 | | | |
| U5 | | | |

## User test of v0.1.0 (2026-11-20)

Done by the user on their Mac (macOS 27) with the `.dmg` downloaded from the GitHub release in the browser:

| Step | Result |
|---|---|
| Install and first launch | Blocked by Gatekeeper as expected, then unblocked from System Settings. Worked. |
| Load demo data, generate the weekend images | Worked. |
| AirDrop one image to the phone | Worked. |
| U1–U5 (menus, drag-out, Return in Genera, VoiceOver, Full Keyboard Access) | **Not reported.** Still open; M1, M5, M6 and M11 stay open until checked. |
