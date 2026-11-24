# 03 — Mac design

How Sergnanese Social looks and behaves as a Mac app. Every UI task follows this file; `qa-reviewer` checks against it in T3.2. The rules come from Apple's Human Interface Guidelines, through the `macos-design-guidelines` skill.

The principle: use what the system gives. Standard SwiftUI controls, system font, system colours, system materials. Do not draw custom versions of things macOS already has.

## 1. Window

- One main window (`Window` scene, not `WindowGroup`): this is a single-purpose utility, so there are no multiple windows or tabs. Closing the window quits the app.
- Freely resizable. Minimum 900×600, default 1200×760. Size and position are remembered between launches (SwiftUI does this for a `Window` with an id).
- Standard title bar and traffic lights, unified toolbar. No custom chrome. Full screen works.
- A second window: **Settings** (`Settings` scene), opened with ⌘,.
- The window title is the current section ("Partite", "Genera", …).

## 2. Sidebar

`NavigationSplitView` with a source-list sidebar (`.listStyle(.sidebar)`), collapsible, two sections ordered by how the weekly job goes:

| Section | Items (SF Symbol) |
|---|---|
| **Weekend** | Partite (`sportscourt`), Genera (`wand.and.stars`), Archivio (`photo.stack`) |
| **Libreria** | Avversari (`shield`), Squadre (`person.3`), Template (`rectangle.on.rectangle`) |

- Partite shows a badge with the number of matches that have warnings this weekend.
- Settings is **not** in the sidebar. It lives in the app menu, as on every Mac app.
- The selected section is remembered between launches.

## 3. Toolbar

Per section, in the unified toolbar, each item with an icon **and** a label (`Label`), so labels show when the user chooses "Icon and Text":

| Section | Toolbar items |
|---|---|
| Partite | weekend switcher (‹ · "Questo weekend" · ›), Aggiungi (+), filter menu, search field, **Genera** (prominent) |
| Genera | weekend switcher, **Genera immagini** (prominent, default action) |
| Archivio | date-range menu, template filter, Condividi, search |
| Avversari | Aggiungi (+), Scarica tutti gli avversari… (T4.9), search |
| Squadre | Aggiungi (+) |
| Template | Importa, search |

The search field uses `.searchable` and sits at the trailing edge.

## 4. Menu bar

Built with SwiftUI `Commands` in `SSApp/Shell`. All titles in Italian. Items are disabled when they do not apply (no selection, wrong section). System items (Servizi, Nascondi, Esci, the standard Modifica and Finestra items) come from macOS and appear in Italian because the app bundle declares Italian as its language.

| Menu | Item | Shortcut |
|---|---|---|
| **Sergnanese Social** | Informazioni su Sergnanese Social | |
| | Impostazioni… | ⌘, |
| **File** | Nuova partita | ⌘N |
| | Nuovo avversario | ⇧⌘N |
| | Scarica tutti gli avversari… (T4.9) | |
| | Importa template… | ⌘O |
| | Carica dati demo | |
| | Apri cartella immagini | ⇧⌘O |
| | Chiudi | ⌘W |
| **Modifica** | Annulla / Ripristina / Taglia / Copia / Incolla / Seleziona tutto | standard |
| | Duplica | ⌘D |
| | Elimina | ⌘⌫ |
| | Trova | ⌘F |
| **Vista** | Partite / Genera / Archivio / Avversari / Squadre / Template | ⌘1 … ⌘6 |
| | Weekend precedente | ⌘[ |
| | Weekend successivo | ⌘] |
| | Questo weekend | ⌘T |
| | Mostra/Nascondi barra laterale | ⌃⌘S |
| | Attiva modalità a tutto schermo | ⌃⌘F |
| **Immagini** | Genera immagini del weekend | ⌘R |
| | Risultato… (T4.5, on the selected match) | ⌥⌘R |
| | Riepilogo risultati del weekend (T4.5) | |
| | Anteprima rapida | Spazio, ⌘Y |
| | Condividi… | |
| | Copia immagine | ⌘C (when an image is selected) |
| | Mostra nel Finder | ⇧⌘R |
| **Finestra** | standard | |
| **Aiuto** | Guida di Sergnanese Social (opens the user guide) | ⌘? |
| | Scarica aggiornamenti… (opens the Releases page) | |
| | Apri cartella dati | |

Menu items act on the current section through SwiftUI focused values (`@FocusedValue`): each feature publishes the actions it supports, the shell's `Commands` call them. A feature never edits the menu definition.

## 5. Lists, selection, editing

- Matches, opponents and the archive use `Table` or `List` with **selection**: click, ⌘-click, ⇧-click, arrow keys.
- Editing happens in an **inspector** on the trailing side (`.inspector`) for matches and opponents, so the list stays visible. Sheets are used only for creating a new item, for the template import report, and for the quick "Risultato" form (T4.5, accepted exception 2026-11-24: scores are entered in a few seconds, then Genera intervallo / Genera finale).
- Double-click a row opens it for editing. Return edits the selected row's primary field where that makes sense.
- **Every row and every image has a context menu** (right-click) with the same actions as the Modifica and Immagini menus for that item.
- ⌫ on a selection asks for confirmation (`confirmationDialog`), with the destructive button marked `.destructive` and Cancel as the Esc action. Routine saves never show an alert.
- Teams reorder by drag (`onMove`).

## 6. Getting images out

This is the last step of the weekly job, so it gets the most care. In the Generate result and in Archivio, a selection of one or more images can be:

| Action | How |
|---|---|
| Looked at | Space or ⌘Y → Quick Look (`quickLookPreview`) |
| Shared | Condividi… → system share picker: **AirDrop to the phone**, Messages, Mail, "Aggiungi a Foto" |
| Dragged out | Drag thumbnails to Finder, Photos, Messages, a browser upload field (file URLs) |
| Copied | ⌘C puts the image on the clipboard |
| Found | Mostra nel Finder |

There is no "download zip": the files are already on disk.

Getting things in works the same way: drop a logo image (from Finder or straight from a browser) on an opponent, paste an image with ⌘V, drop a template folder or zip on the Template section.

## 7. Appearance

- **Light and Dark Mode both work.** Use semantic colours (`.primary`, `.secondary`, `Color(nsColor: .controlBackgroundColor)`), never fixed black/white surfaces.
- **System font** everywhere, with semantic styles (`.headline`, `.body`, `.caption`). Barlow appears only inside rendered images.
- **System accent colour** for selection and default buttons. The club red is brand, not chrome: it appears in the app icon, the crest and the template previews. Red in the UI means "destructive".
- Image thumbnails always show on a neutral mid-grey mat, so a white post is visible in Light Mode and not blinding in Dark Mode.
- Standard control sizes and spacing. No oversized touch-style buttons.
- Respect **Reduce Motion** (no decorative animation) and **Increase Contrast**; keep system materials so **Reduce Transparency** works without extra code.
- No fake glass effects. Built with a current SDK, standard toolbars and sidebars pick up the system's look on their own.

## 8. Feedback

- Generating shows a determinate progress bar in the window and on the Dock icon. When it finishes and the app is in the background, the Dock icon bounces once. No notification, no success alert.
- Warnings (missing logo, cut name, missing time) are inline, with a yellow `exclamationmark.triangle` and a one-click fix where possible.
- Errors the user must act on use a standard alert with a plain-Italian message and what to do next.
- Empty states use `ContentUnavailableView` with one clear action ("Aggiungi partita", "Carica dati demo").

## 9. Accessibility

- Every icon-only button has an `accessibilityLabel` in Italian. Status badges, the home/away marker and the lock icon have labels too.
- Everything reachable with the mouse is reachable with the keyboard: Tab between controls, arrows in lists, Return for the default action, Esc to cancel.
- VoiceOver reads a match row as one sentence ("Domenica 15:30, Prima Squadra contro …, in casa, 1 avviso").
- Text uses semantic styles so it follows the system text size.

## 10. App icon

The club crest centred on a white rounded-square plate that fills the standard macOS icon shape, exported as `.icns` at all sizes up to 1024×1024. A bare crest with a transparent background is not acceptable: recent macOS versions put such icons on a grey plate.

## 11. What we deliberately skip in v0.1.0

Spotlight indexing, Shortcuts/App Intents, widgets, a menu bar extra, notifications, undo for database edits (deletes ask for confirmation instead), toolbar customisation. None is needed for the weekly job; App Intents is a candidate for Wave 4.
