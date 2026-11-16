# Wave 1 — Core (6 tasks in parallel)

All six tasks depend only on Wave 0 and own separate folders, so they start together.

**Gate to Wave 2:** all six merged into `main`, `Scripts/check.sh` green, and:

- `swift run ss-tool demo-render` writes four correct PNGs from the fixtures (tool from T1.3, templates from T1.2 — the orchestrator runs it after merging both);
- the user has downloaded the trial `.dmg` from GitHub with a browser, installed it and opened it (T1.5);
- the user has clicked through the shell with `Scripts/run.sh --mock` in Light and Dark Mode (T1.6).

| Task | Agent | Model | Owns |
|---|---|---|---|
| T1.1 Database layer | `core-dev` | sonnet | `Sources/SSData/**`, `Tests/SSDataTests/**` |
| T1.2 Template conversion | `template-converter` | sonnet | `Resources/Templates/**`, `Sources/ss-tool/Preview.swift` |
| T1.3 Render engine | `render-engineer` | opus | `Sources/SSTemplates/**`, `Sources/SSRender/**`, their test folders, `Sources/ss-tool/DemoRender.swift` |
| T1.4 Fake data | `chore-runner` | haiku | `Sources/SSSeed/**`, `Resources/Seed/**`, `Tests/SSSeedTests/**` |
| T1.5 Packaging + CI | `release-engineer` | sonnet | `Scripts/package_app.sh`, `Packaging/**`, `.github/**`, `Sources/SergnaneseSocial/Smoke.swift`, `docs/INSTALL.md` |
| T1.6 App shell | `ui-dev` | sonnet (effort high) | `Sources/SSApp/**`, `Tests/SSAppTests/Shell/**`, `Tests/SSAppTests/Components/**`, `Sources/SergnaneseSocial/main.swift`, `Sources/ss-tool/Screenshots.swift` |

---

## T1.1 — Database layer

| | |
|---|---|
| **Agent / model** | `core-dev` · sonnet · effort medium |
| **Depends on** | T0.2 |
| **Size** | M |

**Features**

1. `Database.open(at:)` on a GRDB `DatabaseQueue` with foreign keys on; an in-memory variant for tests.
2. Versioned migrations with GRDB's `DatabaseMigrator`. Migration 1: tables `teams`, `opponents`, `matches`, `settings`, `renders` matching `01-architecture.md` §3; indexes on `matches(date)`, `matches(team_id, date)`, `renders(created_at)`.
3. Implementations of every repository protocol in `SSCore/Repositories.swift`. Database records are private to `SSData`; the public surface is the `SSCore` model types.
4. `matches.list(from:to:teamID:)` returns `MatchDetail` values (match + team + opponent), ordered by date, time, team `sortOrder`.
5. Delete guards: deleting a team/opponent with matches throws `AppError.conflict` with an Italian message.
6. `settings`: defaults (`ASD Sergnanese`, `Sergnanese`, `2026/27`, `#CF3326`) returned when nothing is stored.
7. `isLocked` matches: `update` works, but `upsertFromImport` skips them (used in Wave 4; implemented and tested now).
8. `LogoStore` on the logos folder: import from a file URL or image data (PNG, JPEG, WebP, HEIC, SVG; max 5 MB), always stored as a PNG no larger than 1024 px under a generated name; replacing removes the old file.
9. Automatic backup: on open, if the newest file in `backups/` is older than 7 days, write a new one with **GRDB's backup API** (not a file copy); keep the last 5.

**Acceptance**

- [ ] Tests on an in-memory database for every repository method, including guards and date-range edges (Saturday to Sunday inclusive).
- [ ] Opening an empty file creates the schema; opening it again changes nothing.
- [ ] No SQL and no GRDB import outside `Sources/SSData/`.
- [ ] Logo import test: an SVG and a 3000 px JPEG both come out as PNG ≤ 1024 px.
- [ ] `Scripts/check.sh` passes.

---

## T1.2 — Convert the four demo templates

| | |
|---|---|
| **Agent / model** | `template-converter` · sonnet · effort medium |
| **Depends on** | T0.2 (manifest type, fixtures) |
| **Size** | M |

Input: the four zips in `template-demo/`. Output: four template folders that the render engine can use unchanged.

| Source zip | Template id | kind | Size |
|---|---|---|---|
| `Post · Pre-partita-html.zip` | `post-prematch` | single | 1080×1350 |
| `Story · Programma pre-partita-html.zip` | `story-programme` | list, pageSize 10 | 1080×1920 |
| `Story · Intervallo-html.zip` | `story-halftime` | single | 1080×1920 |
| `Story · Risultato finale-html.zip` | `story-fulltime` | single | 1080×1920 |

**Features**

1. Apply the conversion rules of `01-architecture.md` §4 to each template. Keep every inline style value; the look must not change.
2. Placeholder mapping (Mustache; no helpers exist):

   | In the export | Becomes |
   |---|---|
   | `{{accent}}` | `{{club.accent}}` |
   | `ASD Sergnanese`, `Stagione 2026/27`, `[@account]` | `{{club.name}}`, `Stagione {{club.season}}`, `{{club.handle}}` |
   | `[Categoria]`, `[Categoria n]` | `{{match.category}}` / `{{category}}` inside `{{#rows}}` |
   | `[Avversario]` | `{{match.opponent.displayName}}` (already cut to the manifest limit) |
   | `Giornata [N]` | wrapped in `{{#match.round}}…{{/match.round}}` so it shows only when set |
   | `[Dom 00 mese]`, `[Domenica 00 mese]`, `[Data]` | `dateShort` / `dateLong` |
   | `[00:00]`, `[Ora]` | `{{#time}}{{time}}{{/time}}{{^time}}—{{/time}}` |
   | `[Campo]` | `{{match.venue}}` |
   | score `0` / `0` | `match.home.score`, `match.away.score` (half-time template uses `halfTime`) |
   | `[Marcatori / note]` | `{{#match.notes}}…{{/match.notes}}`, block hidden when empty |
   | dashed `LOGO` circle | `{{#logo}}<img …>{{/logo}}{{^logo}}initials circle of the same size{{/logo}}` |

3. Home/away: in `post-prematch`, the left block is `match.home`, the right is `match.away`. In the two result stories the first row is `match.home`, the second `match.away`. The Sergnanese crest comes from `club.logo`, not a hard-coded file.
4. `story-programme`: one row block inside `{{#rows}}`; each row shows time, category, `vs <opponent>` and venue; a small `(C)`/`(T)` marker for home/away in the venue cell. With fewer than 10 rows the list stays top-aligned. The header shows `{{pageLabel}}` only inside `{{#hasPages}}`. The export's "Giornata [N]" in the header is dropped: rows belong to different teams and rounds.
5. Keep Instagram safe zones: nothing important in the top and bottom 250 px of stories.
6. Fonts: download Barlow (500/600/700) and Barlow Condensed (600/700/800 + 800 italic) from the Google Fonts repository, put the files and the `OFL.txt` licence in each template's `assets/fonts/`, and declare them with relative `@font-face` rules. No external URL anywhere.
7. One `manifest.json` per template with `limits` for `teamName`, `venue`, `category`, each tuned by looking at the rendered result.
8. `ss-tool preview <template-folder> <fixture.json>`: renders the template with Mustache and screenshots it with a bare off-screen `WKWebView` to `out/preview/`. It is a deliberately crude checker so this task does not wait for T1.3; it may apply the limits with `SSCore`'s `truncateAtWord`.
9. `Resources/Templates/README.md`: how to write a new template, with the field list and the Mustache patterns above.

**Acceptance**

- [ ] `grep -r "googleapis\|x-dc\|support.js\|vendor/" Resources/Templates` finds nothing.
- [ ] Each manifest decodes with `SSCore`'s `TemplateManifest` (test in the agent's report: the preview tool refuses an invalid one).
- [ ] Previews exist for all four templates with: the standard fixture, the 45-character name, the missing logo, an away match. The agent has **looked at each PNG** and reports what it saw.
- [ ] Standard-fixture previews match the look of the original exports (same positions, colours, fonts). "Match day" fits on one line, which proves Barlow Condensed loaded.
- [ ] `Scripts/check.sh` passes.

---

## T1.3 — Render engine and template store

| | |
|---|---|
| **Agent / model** | `render-engineer` · opus · effort high |
| **Depends on** | T0.2 |
| **Size** | L |

Opus is used because this is the part with real technical risk: exact pixel output across displays, font timing, isolation of template code, and WebKit APIs that are easy to get subtly wrong. A throwaway experiment already produced a correct 1080×1350 sRGB PNG from the pre-match demo on this Mac (`takeSnapshot` gave 2160×2700 on a Retina display, redrawn to exact size); this task makes it robust.

**Features — template store (`Sources/SSTemplates/`)**

1. `installBuiltins()`: copy `Resources/Templates/*` into the data folder's `templates/` on first run and when a built-in's version is newer.
2. `list()`, `get(id)`, `remove(id)`, `restoreBuiltin(id)`.
3. `install(from:replace:)` for a folder or a `.zip`: safe unzip with ZIPFoundation (reject `..`, absolute paths, symlinks; max 20 MB, max 200 files; allowed extensions only), locate `manifest.json` at the root or one folder deep, validate, refuse an id clash unless `replace` is true.
4. Validation result is a list of readable Italian problems (`manifest.width deve essere un numero`, `template.html non trovato`, …).

**Features — render service (`Sources/SSRender/`)**

5. `ContextBuilder`: builds a `SingleContext` per match, or sorted and paginated `ListContext`s; resolves logo URLs; applies the manifest `limits`; collects warnings (missing logo, missing time/venue, cut name, postponed/cancelled match included).
6. Mustache rendering with compiled templates cached by id + version.
7. `WebRenderer` (`@MainActor`) following the pipeline in `01-architecture.md` §6:
   - `WKWebView` in a borderless off-screen window; app activation is never requested;
   - a `WKURLSchemeHandler` serving only the template folder and the logos folder; a `WKContentRuleList` blocking every remote request; non-persistent data store; no script message handlers;
   - light appearance forced on the web view;
   - wait for `document.fonts.ready`, image decode, optional `window.__ready`, with a 10 s timeout that fails with a clear error;
   - `takeSnapshot`, redraw into an sRGB bitmap of exactly `width × height` pixels, encode as PNG;
   - verify the PNG's pixel size, else throw.
8. One web view reused through a serial queue, so generating 20 images does not create 20 web views.
9. `plan(request)`: dry run returning the images that would be produced and all warnings, without rendering. Default selection when the request lists no templates: `story-programme` takes all scheduled matches in the range, one set per day; `post-prematch` takes the first team's match. Postponed and cancelled matches are excluded by default and listed as "skipped".
10. `render(request)`: an `AsyncThrowingStream` of events (started, image done i/n, finished). Writes files with the naming scheme of §6 (never overwrites: adds `-2`, `-3`), stores `RenderRecord`s through `RenderRepository`. Cancelling the task stops after the current image.
11. `preview(templateID:matchIDs:)`: renders to a temp PNG; without match ids it uses the fixture.
12. `ss-tool demo-render`: renders all templates found in `Resources/Templates/` from the fixtures into `out/demo/`.
13. Tests use two tiny templates under `Tests/SSRenderTests/Fixtures/` (one single, one list), so this task does not wait for T1.2.

**Acceptance**

- [ ] Output is exactly `width × height` pixels on this Mac's display. The redraw step is also unit-tested with synthetic 1× and 2× snapshot images.
- [ ] A test template with a full-bleed `#CF3326` block: the centre pixel of the PNG reads exactly `#CF3326`.
- [ ] The same test template renders identically with the app forced to Dark Mode.
- [ ] A template that requests `https://…` renders with that request blocked and a warning recorded. A template that asks for a file outside its folder (`../`) does not get it.
- [ ] List pagination: 23 rows with pageSize 10 → 3 images with `1/3`, `2/3`, `3/3`.
- [ ] Import tests: valid folder, valid zip, missing manifest, path traversal, symlink, oversize.
- [ ] Rendering the same context twice on the same Mac gives identical pixels.
- [ ] While tests run, no window appears and the frontmost app does not change.
- [ ] `Scripts/check.sh` passes.

---

## T1.4 — Fake data (seed)

| | |
|---|---|
| **Agent / model** | `chore-runner` · haiku |
| **Depends on** | T0.2 |
| **Size** | S |

Haiku is enough: the shapes are fixed by `SSCore`, the content is invented, and the only code is one small pure function and a loader. If the build fails twice, rerun on sonnet.

**Features**

1. `Resources/Seed/teams.json`: 10 teams (Prima Squadra, Juniores, Allievi U17, Allievi U16, Giovanissimi U15, Giovanissimi U14, Esordienti, Pulcini, Primi Calci, Femminile), with `sortOrder` and `isFirstTeam` on the first.
2. `Resources/Seed/opponents.json`: 20 **invented** clubs (no real club names), including: three names over 35 characters, two with legal prefixes (`A.S.D.`, `Pol.`), one with an apostrophe and an accent, four without a logo.
3. `Resources/Seed/logos/`: 16 simple generated PNG crests, 512×512 (shape + initials, varied colours), made with a short script kept in the same folder. They are fake data and safe to commit.
4. `generateMatches(today:)`: a pure function producing matches for the **next four weekends** from `today`: 8–11 matches per weekend, mixed Saturday/Sunday, home and away, one postponed, one without a time, one weekend with 12 matches (to force two programme pages), plus last weekend's matches with scores and half-time scores.
5. `SeedLoader`, the implementation of `SSCore`'s `DemoDataLoader`: clears seed-sourced rows and inserts everything with `source: .seed`, using only the repository protocols and `LogoStore`.
6. Tests: all JSON decodes into the model types; the generator is deterministic for a given date; counts and edge cases above are present; loading twice into the in-memory fakes leaves the same number of rows.

**Acceptance**

- [ ] `Scripts/check.sh` passes.
- [ ] No real club name, logo or person appears in the seed.
- [ ] `SSSeed` imports only Foundation and `SSCore`.

---

## T1.5 — Packaging and CI (walking skeleton)

| | |
|---|---|
| **Agent / model** | `release-engineer` · sonnet · effort medium |
| **Depends on** | T0.1 |
| **Size** | M |

Done in Wave 1, not at the end, so that packaging problems (runner toolchain, signing, resources, Gatekeeper) appear while the app is still tiny. Background: `05-macos-packaging.md`.

**Features**

1. `Scripts/package_app.sh release`: release build for arm64, the bundle of T0.1 plus `AppIcon.icns`, ad-hoc signature, then `build/Sergnanese-Social-<version>.dmg` made with `hdiutil`, containing the app and an Applications shortcut. Verifies the result with `codesign --verify --deep --strict`.
2. App icon per `03-mac-design.md` §10: the crest on a white rounded-square plate, all sizes generated with `sips` + `iconutil` into `Packaging/AppIcon.icns`, from the best crest available (`Packaging/crest-source.*` if the user supplied one, else the 500 px PNG from the demo zips — say which in the report).
3. `Sources/SergnaneseSocial/Smoke.swift`, run by `--smoke`. In this wave the check is self-contained, because the real engine is being written in parallel: open a GRDB database in a temp folder, find `Resources/Templates` or `Resources/Fixtures` through `AppPaths`, snapshot a tiny inline HTML page in an off-screen `WKWebView` and check the PNG size, print `SMOKE OK`, exit 0. T3.1 later switches it to the real engine.
4. `.github/workflows/ci.yml`: on pull request and push to `main` → Apple silicon macOS runner, `Scripts/check.sh`.
5. `.github/workflows/release.yml`: on tag `v*`, on manual dispatch, and on push to branches named `release-trial/**` → `Scripts/check.sh`, `Scripts/package_app.sh release`, **copy the `.app` to a temp folder, delete `.build`, run it with `--smoke`**, then upload the `.dmg` to a GitHub Release (a draft for manual and trial runs). The trial-branch trigger exists because a manual run cannot be started for a workflow that is not yet on `main`.
6. `docs/INSTALL.md` (Italian + English): which Macs are supported (Apple silicon, macOS 15+), download, drag to Applications, first-launch approval in System Settings → Privacy & Security → "Open Anyway", the `xattr` alternative, how to update, where the data lives, how to uninstall.
7. Workflows use only the built-in `GITHUB_TOKEN` with `contents: write` on the release job. No other secrets. Third-party actions pinned to a commit.

**Acceptance**

- [ ] The task branch is pushed as `release-trial/t1.5`; the run is green, prints `SMOKE OK`, and leaves a draft release with one `.dmg`.
- [ ] `ci.yml` is green on a pull request from the task branch.
- [ ] `Scripts/package_app.sh release` works locally with only the Command Line Tools.
- [ ] The report says plainly what could not be checked by an agent: the Gatekeeper first-launch steps. **The user checks them at the wave gate** with the browser-downloaded `.dmg`, and `INSTALL.md` is corrected to match what they saw on macOS 27.

---

## T1.6 — App shell, shared components, mock mode

| | |
|---|---|
| **Agent / model** | `ui-dev` · sonnet · **effort high** |
| **Depends on** | T0.2 |
| **Size** | L |

Everything here follows `03-mac-design.md`. This task decides how Mac-like the app is; the Wave 2 screens only fill it in.

**Features**

1. `Shell/`: the `App` type with the main `Window` scene (min 900×600, default 1200×760) and the `Settings` scene; `NavigationSplitView` with the two-section sidebar of §2; the selected section remembered with `@SceneStorage`/`@AppStorage`.
2. The complete menu bar of `03-mac-design.md` §4 as SwiftUI `Commands`, wired through `@FocusedValue` action keys defined here (`newItem`, `duplicate`, `delete`, `find`, `generate`, `share`, `quickLook`, `revealInFinder`, `copyImage`, weekend navigation). Items are disabled when the current section does not publish the action. ⌘1–⌘6 switch sections.
3. `AppModel` (`@MainActor @Observable`): holds `AppServices`, the current section, the **selected weekend** (shared by Partite, Genera and Archivio) and a way for one section to open another with context ("Genera for this weekend").
4. One placeholder view per feature in `Features/<Name>/<Name>View.swift` (a `ContentUnavailableView`), so Wave 2 tasks replace the contents of their own folder and never edit the shell. The Settings scene shows `Features/Settings/SettingsView`.
5. `Sources/SergnaneseSocial/main.swift`: starts the shell. With `--mock` it uses `AppServices.fake()`; without it, it calls `Composition.makeServices()`, which is still a stub in this wave and falls back to the fakes with a visible "dati demo" badge in the toolbar.
6. `Components/`:
   - `WeekendSwitcher` (previous / label / next, "Questo weekend"),
   - `ImageGallery`: a selectable grid of rendered images on a neutral grey mat, correct aspect ratio for post and story, with Quick Look, drag-out as file URLs, system share picker, copy, "Mostra nel Finder" and the matching context menu — used by Genera, Archivio and Template,
   - `LogoWell`: shows a logo or initials; accepts a dropped image file, an image dragged from a browser, and ⌘V paste; has "Scegli…" and "Rimuovi",
   - `WarningLabel`, `StatusBadge`, `HomeAwayMarker`, each with an accessibility label,
   - `FormSection` helpers that show field-level validation problems from `SSCore`,
   - a small `confirmDelete` modifier wrapping `confirmationDialog`.
7. `Strings/`: shared Italian strings (sections, menus, common buttons and errors). Each feature keeps its own `Strings` file in its folder.
8. Dock progress helper (`NSDockTile` progress + one bounce when done in the background).
9. `ss-tool screenshots`: renders every feature's root view with `AppServices.fake()`, in Light and in Dark appearance, to `out/screens/<feature>-<light|dark>.png`, so agents and `qa-reviewer` can look at screens without driving the app. Best effort: toolbar and menu bar are not captured.
10. Tests: `AppModel` weekend navigation; the command-enabling logic; `ImageGallery`'s selection model.

**Acceptance**

- [ ] `Scripts/run.sh --mock` shows the shell; every sidebar item and ⌘1–⌘6 open the right placeholder; ⌘, opens Settings; closing the window quits.
- [ ] The menu bar matches `03-mac-design.md` §4, in Italian; items with no handler are greyed out.
- [ ] `ImageGallery` with the fake renders: Space opens Quick Look, a thumbnail drags to Finder as a PNG file, Condividi shows AirDrop.
- [ ] Quit and relaunch: window size, position and selected section are restored.
- [ ] Screenshots exist for every section in Light and Dark; the agent has looked at them and reports what it saw.
- [ ] No user-visible string outside a `Strings` file. No fixed colours for surfaces or text.
- [ ] `Scripts/check.sh` passes.
