# T3.2 Part B: Mac review of the app

- Tested: `main` at `6a27429` (after T3.1 and T3.3), 2026-11-18.
- Reviewer: `qa-reviewer`. This file is a report. It does not fix anything; fixes go to the owner shown in each row.
- Verdict: **no blocking UI row found from source and screenshots.** Two rows depend on checks the user has to do by hand (M1, M5). The release gate also needs the by-hand list at the end, and the blocking image defect V1 in `visual-report.md` (empty venue) applies to the app's output.

## Method and limits

- `Scripts/check.sh` passes on this commit: build with warnings as errors, format lint, 315 tests.
- `swift run ss-tool screenshots` (fake data, Light and Dark) → `out/screens/<screen>-<light|dark>.png`. I opened all 18 images. The tool does not capture the toolbar, the menu bar, inspectors, sheets or popovers. Those were checked in the source only.
- Source review of `Sources/SSApp/**` and `Sources/SergnaneseSocial/**` against `03-mac-design.md` and the `macos-design-guidelines` checklist.
- Running app: I built the debug bundle and launched it with `--mock` and a temp `SS_DATA_DIR`. I could not read its menu bar, because `osascript` is not allowed assistive access on this Mac. So every "menu item exists / is disabled" result below is **from source**, and the user should confirm it (item U1 at the end).
- Nothing touched `~/Library/Application Support/Sergnanese Social/` or `… Dev/`. Neither folder exists after the run. Every command ran with a temp `SS_DATA_DIR`.

## Problems

| ID | Where | What is wrong | Screenshot | Suggested fix | Owner | Blocking |
|---|---|---|---|---|---|---|
| M1 | `Features/Generate/GenerateView.swift:291`, `Components/ImageGallery.swift:233` | In Genera, Return is used twice. The toolbar button "Genera immagini" is the window's default action (`.keyboardShortcut(.defaultAction)`), and the gallery opens Quick Look on Return. Key equivalents are handled before the focused view's key handler. So selecting an image after a run and pressing Return probably starts the whole weekend render again instead of opening Quick Look. Not verified, because I could not drive the app. | n/a | User check U3. If confirmed: remove Return from the gallery's Quick Look keys (keep Space, ⌘Y, double-click) and update the gallery's doc comment, or drop `.defaultAction` while results are shown. | `ui-dev` | No, but **blocking if U3 confirms it** |
| M2 | `Features/Generate/GenerateViewModel.swift:157`, `Shell/AppModel.swift:79`, `Features/Matches/MatchesViewModel.swift:70` | Per-match warnings use the smallest `teamName` limit of **all** installed templates (16), not the limit of the templates the match will actually be rendered with. Youth matches that only go into the programme (limit 22) get a false "Il nome «U.S. Castelverde Calcio» verrà accorciato in «Castelverde…»". In Genera the list shows 8 or more warnings while the footer says "3 immagini da generare · 4 avvisi". The Partite badge and the Avvisi column count the same false positives (the badge shows 7). Users will set short names they do not need. | `out/screens/generate-light.png`, `out/screens/matches-light.png` | In Genera, build the row warnings from `plan.warnings` for that match plus the warnings that do not depend on a limit. For the badge and the Matches column, use the limits of the templates the default plan would use for that match (programme for all matches, pre-match post for the first team). | `ui-dev` | No |
| M3 | `Features/Teams/TeamsView.swift:125` | The "Attiva" switch keeps its visible label on every row. Inactive teams read "Attiva" next to a switch that is off (see Veterani). | `out/screens/teams-light.png`, `-dark.png` | Add `.labelsHidden()` (the accessibility label stays), and add a column header or the help text. | `ui-dev` | No |
| M4 | `Features/Teams/TeamsView.swift:68` | `Button(team.isActive ? "Disattiva" : …)` puts Italian text inline in a view. This breaks the `Strings` rule in `CLAUDE.md`. | n/a | Move it to `TeamsStrings`. | `ui-dev` | No |
| M5 | `Shell/AppCommands.swift:67`, `:72` | The Modifica menu probably shows two "Elimina" items (the system pasteboard "Elimina" and ours with ⌘⌫) and two Find entries (the system "Trova ▸ Trova… ⌘F" and our "Trova ⌘F"). Not verified live. | n/a | User check U1. If duplicated: use `CommandGroup(replacing: .pasteboard)` and keep the standard items plus Duplica/Elimina. Replace the system Find group (`CommandGroup(replacing: .textEditing)`) or drop our item and publish through the standard one. | `ui-dev` | No |
| M6 | `Features/Archive/ArchiveView.swift:147-170`, `Features/Templates/TemplatesView.swift:186-205` | Missing from the toolbars in §3: Archivio has no search field and no Condividi button (sharing works from the menu and the context menu). Template has no search field. | `out/screens/archive-light.png`, `templates-light.png` | Add `.searchable` and a `ShareLink` for the selection, or record the deviation in `03-mac-design.md`. With four templates and a few archive weeks this is low value. | `ui-dev` | No |
| M7 | `Features/Archive/ArchiveView.swift:29` | The empty Archivio uses `ContentUnavailableView` without an action. §8 asks for one clear action. | n/a | Add "Vai a Genera" (`app.open(.generate)`). | `ui-dev` | No |
| M8 | Partite table, column `Casa/Trasferta` | At the default width the header is cut to `Casa/…`. | `out/screens/matches-light.png` | Use a shorter header (for example "C/T", with the full words as help), or a larger ideal width. | `ui-dev` | No |
| M9 | `Features/Opponents/OpponentsView.swift` logo column | Opponents without a logo show bare initials. Partite shows the same initials in a grey circle. The two screens are inconsistent. | `out/screens/opponents-light.png` vs `matches-light.png` | Reuse the circle from `OpponentCell`. | `ui-dev` | No |
| M10 | `Features/Generate/GenerateView.swift:156` | A match with no time gets the subtitle "Sab 21 nov, —, in trasferta". | `out/screens/generate-light.png` | Write "orario da definire" (a `GenerateStrings` entry) instead of the dash. | `ui-dev` | No |
| M11 | `Components/ImageGallery.swift:160` | `.draggable(image.url)` drags only the clicked thumbnail. §6 says a selection of one or more images can be dragged out. | n/a | User check U2. If several images are wanted: drag the selection, for example through an `NSItemProvider` per file. | `ui-dev` | No |
| M12 | Settings › Immagini, accent colour | No readability check on the accent colour. See V2 in `visual-report.md`. | `out/qa/single/story-halftime/s27-accent-light.png` | Inline warning below 3:1 contrast with white. | `ui-dev` | No |
| M13 | `Features/Settings/SettingsStrings.swift:20` | Straight quotes in the Italian text: `passa a "in casa"`. | `out/screens/settings-light.png` | Use «in casa». | `ui-dev` | No |

## `03-mac-design.md`, section by section

"Pass (source)" means the code does what the spec asks, but the item cannot be seen in the screenshots. "User" means only someone using the app can confirm it. The by-hand list says how.

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
| Badge on Partite = matches with warnings | Pass, inflated by M2 | `matches-light.png` shows 7 |
| Settings not in the sidebar | Pass | screenshots |
| Selected section remembered | Pass (source) | `AppModel.persistSection` |
| Icon alignment | User | In the off-screen screenshots the wide `person.3` icon touches the "Squadre" label. Check in the real window (U1) |

### §3 Toolbar

| Section | Status | Evidence |
|---|---|---|
| Partite: switcher, Aggiungi, filter menu, search, Genera (prominent) | Pass (source) | `MatchesView.swift` toolbar, `.searchable(placement: .toolbar)` |
| Genera: switcher, Genera immagini (prominent, default) | Pass (source), see M1 | plus "Condividi tutto" |
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
| Quick Look (Space, ⌘Y, double-click) | Pass (source), see M1 | `quickLookPreview` |
| Condividi → AirDrop, Messages, Mail, Foto | User | U2 |
| Drag to Finder, Photos, Messages, browser | User, see M11 | U2 |
| ⌘C copies the image | Pass (source) | `onCopyCommand` + `ImageActions.copy` writes the image and the file URL |
| Mostra nel Finder | Pass (source) | |
| Drop a logo, paste with ⌘V, drop a template folder or zip | Pass (source) | `LogoWell.onDrop/onPasteCommand`, `TemplatesView.dropDestination`. Behaviour: U2 |

### §7 Appearance

| Item | Status | Evidence |
|---|---|---|
| Light and Dark both work | Pass | All 9 screens in both modes; no unreadable or fixed-colour surface |
| No fixed colours on surfaces or text | Pass | Only semantic system colours (`.yellow` warning, `.red`/`.orange`/`.green` status, `.secondary`, `controlBackgroundColor`, `systemGray`). The selected caption is white on accent, as in Finder |
| System font, semantic styles | Pass, one exception | `MatchesView.swift:288` uses `.system(size: 9)` for initials in a 22-pt circle (acceptable) |
| System accent for selection and default buttons | Pass | Club red appears only in images and the icon |
| Neutral mid-grey mat behind thumbnails | Pass | `ImageGallery.swift:127`, `archive-*.png`, `gallery-light.png` |
| Reduce Motion / Transparency / Increase Contrast | Pass (source) | No custom animation, standard materials |

### §8 Feedback

| Item | Status | Evidence |
|---|---|---|
| Determinate progress in the window and on the Dock, one bounce in the background, no success alert | Pass (source) | `GenerateView.runProgress`, `DockProgress` (`requestUserAttention(.informationalRequest)` only when inactive), the result is inline status text |
| Inline warnings with a yellow triangle and a one-click fix | Pass, see M2 | `WarningLabel`, Modifica link in Genera |
| Errors in a standard alert | Pass (source) | Startup failure alert with "Mostra cartella dati" (`main.swift`); screen errors in `.alert` |
| Empty states with `ContentUnavailableView` and one action | Pass, except M7 | Matches (Aggiungi partita / Carica dati demo), Opponents, Teams, Templates, Genera, gallery |
| Error states for lists | Pass (source) | Load-failed views with "Riprova" in Matches, Genera, Archivio, Opponents, Teams, Templates |

### §9 Accessibility

| Item | Status | Evidence |
|---|---|---|
| Icon-only buttons have Italian labels | Pass (source) | Weekend arrows, star (first team), alias +/-, lock/source icons, status badge, home/away marker, logo well. No icon-only button without a label was found |
| Matches row read as one sentence | Pass (source) / user | `MatchesViewModel.rowSentence` on the first column, other cells hidden. U4 |
| Keyboard: Tab, arrows, Return, Esc | User | U5 |
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
| Keyboard: Tab, arrows, Esc, Return, Delete, Space for Quick Look | Pass (source); M1, U5. Cmd-Z undo: skipped (§11, deletes confirm instead) |
| Pointer: hover, context menus, drag and drop, multi-select | Pass (source); M11, U2 |
| Notifications: none, no success alerts | Pass |
| System integration: Dock icon, Share | Pass / U2. Spotlight, App Intents: skipped (§11) |
| Visual: system font, Dark Mode, accent, materials | Pass |
| Accessibility: labels, Full Keyboard Access, Reduce Motion/Transparency, focus order | Pass (source) / U4, U5 |

## By-hand list for the user

An agent cannot do these. Run the release `.dmg`, or `Scripts/run.sh` (Dev data folder), load demo data, and press Genera once. Write what you see in the table at the end.

| # | Check | How | Expected |
|---|---|---|---|
| U1 | Menus and window | Open every menu. Look at Modifica and Vista in particular. Resize the window, quit and relaunch. Collapse the sidebar with ⌃⌘S. Set the toolbar to "Icon and Text". Enter full screen. | Every item of §4 is there with its shortcut and is greyed where it does not apply. **Only one** "Elimina" and one "Trova" (M5). The window reopens at the same size and place. Sidebar icons are aligned. |
| U2 | AirDrop and drag out | In Genera, select one image → Immagini › Condividi… → AirDrop → your phone. Then drag one thumbnail into Finder, into Photos, and into a browser upload field (for example a new Instagram/Facebook post on the web). Try dragging with two images selected. Drop a logo image from Finder and from a browser onto an opponent. ⌘V an image onto an opponent. Drop a template zip onto Template. | The PNG arrives on the phone at full size. Finder gets a copy of the PNG (not a link). The browser accepts the file. Note whether a multi-selection drags one image or all (M11). Logos and the zip are accepted. |
| U3 | Return in Genera | After generating, click one thumbnail, then press Return. Press Space. | Space opens Quick Look. **If Return starts a new render instead of Quick Look, M1 becomes blocking.** |
| U4 | VoiceOver over the matches table | ⌘F5, go to Partite, move through the rows with VO-arrows. | Each row is read as one sentence: "Domenica 15:30, Prima Squadra contro …, in casa, 1 avviso". Icon buttons (weekend arrows, star, +/-) have Italian names. |
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
