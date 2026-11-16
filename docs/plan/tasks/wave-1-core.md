# Wave 1 — Core (6 tasks in parallel)

All six tasks depend only on Wave 0 and own separate folders, so they start together.

**Gate to Wave 2:** all six merged into `main`, `npm run check` green, and this demo works from a terminal: `npm run demo:render` writes four correct PNGs from the fixtures (script delivered by T1.3, templates by T1.2 — the orchestrator runs it after merging both).

| Task | Agent | Model | Owns |
|---|---|---|---|
| T1.1 Database layer | `backend-dev` | sonnet | `src/server/db/**` |
| T1.2 Template conversion | `template-converter` | sonnet | `templates-builtin/**`, `scripts/template-preview.mjs` |
| T1.3 Render engine | `render-engineer` | opus | `src/server/services/**`, `tests/electron/render/**`, `scripts/demo-render.ts` |
| T1.4 Fake data | `chore-runner` | haiku | `seed/**` |
| T1.5 Packaging + CI | `release-engineer` | sonnet | `electron-builder.yml`, `build/**`, `.github/**`, `electron/smoke.ts`, `docs/INSTALL.md` |
| T1.6 UI shell | `ui-dev` | sonnet | `src/ui/app/**`, `src/ui/components/**`, `src/ui/api/**`, `src/ui/i18n/**`, placeholder `src/ui/pages/*/index.tsx` |

---

## T1.1 — Database layer

| | |
|---|---|
| **Agent / model** | `backend-dev` · sonnet · effort medium |
| **Depends on** | T0.2 |
| **Size** | M |

**Features**

1. `openDatabase(path)` with WAL mode and foreign keys on; `':memory:'` supported for tests.
2. Versioned migrations in `src/server/db/migrations/NNN_name.sql`, applied in order inside a transaction; a `schema_version` table.
3. Migration 001: tables `teams`, `opponents`, `matches`, `settings`, `renders` matching `01-architecture.md` §3; indexes on `matches(date)`, `matches(team_id, date)`, `renders(created_at)`.
4. Implementations of every interface in `src/shared/repositories.ts`. Rows are parsed through the zod schemas on the way out.
5. `matches.list({ from, to, teamId })` returns matches joined with team and opponent, ordered by date, time, team `sortOrder`.
6. Delete guards: deleting a team/opponent with matches throws a typed `ConflictError`.
7. `settings`: defaults (`ASD Sergnanese`, `Sergnanese`, `2026/27`, `#CF3326`) returned when nothing is stored.
8. `locked` matches: `update` works, but a `upsertFromImport` method skips them (used in Wave 4; implemented and tested now).
9. Automatic backup: on open, if the newest file in `userData/backups/` is older than 7 days, copy the database there; keep the last 5.

**Acceptance**

- [ ] Unit tests on an in-memory database for every repository method, including guards and date-range edges (Saturday 00:00 to Sunday 23:59).
- [ ] Opening an empty file creates the schema; opening it again changes nothing.
- [ ] No SQL outside `src/server/db/`.
- [ ] `npm run check` passes.

---

## T1.2 — Convert the four demo templates

| | |
|---|---|
| **Agent / model** | `template-converter` · sonnet · effort medium |
| **Depends on** | T0.2 (manifest schema, fixtures) |
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
2. Placeholder mapping:

   | In the export | Becomes |
   |---|---|
   | `{{accent}}` | `{{club.accent}}` |
   | `ASD Sergnanese`, `Stagione 2026/27`, `[@account]` | `{{club.name}}`, `Stagione {{club.season}}`, `{{club.handle}}` |
   | `[Categoria]`, `[Categoria n]` | `{{match.category}}` / `{{category}}` inside `{{#each rows}}` |
   | `[Avversario]` | `{{slot "teamName" match.opponent.displayName}}` |
   | `Giornata [N]` | shown only when `round` is set |
   | `[Dom 00 mese]`, `[Domenica 00 mese]`, `[Data]` | `dateShort` / `dateLong` |
   | `[00:00]`, `[Ora]` | `time`, or `—` when missing |
   | `[Campo]` | `{{slot "venue" match.venue}}` |
   | score `0` / `0` | `match.us.score`, `match.opponent.score` (half-time template uses `halfTime`) |
   | `[Marcatori / note]` | `match.notes`, block hidden when empty |
   | dashed `LOGO` circle | `<img>` of the opponent logo, or an initials circle in the same size |

3. Home/away: in `post-prematch`, the left block is `match.home`, the right is `match.away`. In the two result stories the first row is `match.home`, the second `match.away`. The Sergnanese crest comes from `club.logo`, not a hard-coded file.
4. `story-programme`: one row block inside `{{#each rows}}`; each row shows time, category, `vs <opponent>` and venue; a small `(C)`/`(T)` marker for home/away in the venue cell. With fewer than 10 rows the list stays top-aligned. The header shows `page.index/page.total` only when `total > 1`.
5. Keep Instagram safe zones: nothing important in the top and bottom 250 px of stories.
6. Fonts: `@font-face` rules pointing at `{{asset}}`-resolved bundled Barlow files (weights 500/600/700, Condensed 600/700/800 + 800 italic). No external URL anywhere.
7. One `manifest.json` per template with slots: `teamName`, `venue`, `category`, each with a `maxChars` tuned by looking at the rendered result.
8. `scripts/template-preview.mjs <template-id> <fixture.json>`: fills a template with a fixture and screenshots it with Playwright's Chromium to `out/preview/`. Used to check the work without waiting for T1.3.
9. `templates-builtin/README.md`: how to write a new template, with the field list and the helpers.

**Acceptance**

- [ ] `grep -r "googleapis\|x-dc\|support.js\|vendor/" templates-builtin` finds nothing.
- [ ] Each manifest validates against `src/shared/manifest.ts` (test).
- [ ] Previews exist for all four templates with: the standard fixture, the 45-character name, the missing logo, an away match. The agent has **looked at each PNG** and reports what it saw.
- [ ] Standard-fixture previews match the look of the original exports (same positions, colours, fonts).
- [ ] `npm run check` passes.

---

## T1.3 — Render engine and template service

| | |
|---|---|
| **Agent / model** | `render-engineer` · opus · effort high |
| **Depends on** | T0.2 |
| **Size** | L |

Opus is used because this is the part with real technical risk: exact pixel output across displays, font timing, sandboxing, and Electron APIs that are easy to get subtly wrong.

**Features — template service (`src/server/services/templates/`)**

1. `installBuiltins()`: copy `templates-builtin/*` into `userData/templates/` on first run and when a built-in's version is newer.
2. `list()`, `get(id)`, `remove(id)`, `restoreBuiltin(id)`.
3. `installFromZip(buffer)`: safe unzip (reject `..`, absolute paths, symlinks; max 20 MB, max 200 files; allowed extensions only), locate `manifest.json` at the root or one folder deep, validate, refuse an id clash unless `replace: true`.
4. Validation result is a list of readable problems (`manifest.width must be a number`, `template.html not found`, …).

**Features — render service (`src/server/services/render/`)**

5. `buildContexts(template, matches, settings)`: builds `SingleContext` per match, or sorted and paginated `ListContext`s; resolves logo paths; computes `displayName`; collects warnings (missing logo, missing time/venue, truncated name, postponed/cancelled match included).
6. Handlebars environment with the helpers of `01-architecture.md` §4 (`slot` reads the template's manifest), compiled templates cached by id + version.
7. `renderToPng(template, context)` following the pipeline in §6:
   - hidden `BrowserWindow`, `sandbox: true`, `contextIsolation: true`, no node integration, dedicated session with every non-`file:` request cancelled and `file:` limited to the template folder, the bundled fonts and the logos folder;
   - wait for `document.fonts.ready`, image decode, optional `window.__ready`, with a 10 s timeout that fails with a clear error;
   - CDP device metrics override at scale 1 and `Page.captureScreenshot` clipped to the root element;
   - verify the PNG header reports exactly `width × height`, else throw.
8. A small pool (2 windows) and a queue, so generating 20 images does not open 20 windows.
9. `planRender(request)`: dry run returning the list of images that would be produced and all warnings, without rendering.
10. `render(request)`: writes files with the naming scheme of §6 (never overwrites: adds `-2`, `-3`), stores `RenderRecord`s through `RenderRepo`, returns records and warnings. Progress callback per image.
11. `scripts/demo-render.ts` and npm script `demo:render`: renders all installed templates from the shared fixtures into `out/demo/`.
12. Tests live in `tests/electron/render/` (they need a real Electron process) and use two tiny templates under `src/server/services/render/__fixtures__/` (one single, one list), so this task does not wait for T1.2. Pure logic (context building, pagination, naming, zip validation) is unit-tested with Vitest.

**Acceptance**

- [ ] Output is exactly `width × height` with the display scale factor forced to 1 and to 2 in tests.
- [ ] A template that requests `https://…` renders with that request blocked and a warning recorded.
- [ ] List pagination: 23 rows with pageSize 10 → 3 images with `1/3`, `2/3`, `3/3`.
- [ ] Zip tests: valid, missing manifest, path traversal, oversize.
- [ ] Rendering the same context twice gives byte-identical PNGs.
- [ ] `npm run check` passes, including `test:electron`.

---

## T1.4 — Fake data (seed)

| | |
|---|---|
| **Agent / model** | `chore-runner` · haiku |
| **Depends on** | T0.2 |
| **Size** | S |

Haiku is enough: the shapes are fixed by the schemas and the content is invented.

**Features**

1. `seed/teams.json`: 10 teams (Prima Squadra, Juniores, Allievi U17, Allievi U16, Giovanissimi U15, Giovanissimi U14, Esordienti, Pulcini, Primi Calci, Femminile), with `sortOrder` and `isFirstTeam` on the first.
2. `seed/opponents.json`: 20 **invented** clubs (no real club names), including: three names over 35 characters, two with legal prefixes (`A.S.D.`, `Pol.`), one with an apostrophe and an accent, four without a logo.
3. `seed/logos/`: 16 simple generated SVG crests (shape + initials, varied colours). They are fake data and safe to commit.
4. `seed/generate-matches.ts`: pure function `generateMatches(today)` producing matches for the **next four weekends** from `today`: 8–11 matches per weekend, mixed Saturday/Sunday, home and away, one postponed, one without a time, one weekend with 12 matches (to force two programme pages), plus last weekend's matches with scores and half-time scores.
5. `seed/index.ts`: `loadSeed(repos, today)` that clears seed-sourced rows and inserts everything with `source: 'seed'`, using only the interfaces in `src/shared/repositories.ts`.
6. Tests: all JSON validates against the schemas; generator is deterministic for a given date; counts and edge cases above are present.

**Acceptance**

- [ ] `npm run check` passes.
- [ ] No real club name, logo or person appears in the seed.
- [ ] `loadSeed` run twice leaves the same number of rows.

---

## T1.5 — Packaging and CI (walking skeleton)

| | |
|---|---|
| **Agent / model** | `release-engineer` · sonnet · effort medium |
| **Depends on** | T0.1 |
| **Size** | M |

Done in Wave 1, not at the end, so that packaging problems (native SQLite module, signing, architectures) appear while the app is still tiny. Background and sources: `05-macos-packaging.md`.

**Features**

1. `electron-builder.yml`: product name `Sergnanese Social`, app id `it.sergnanese.social`, targets `dmg` and `zip`, architectures `arm64` and `x64`, ad-hoc signing, `templates-builtin/` and fonts shipped as extra resources, app icon (`build/icon.icns`) generated from the club crest PNG found inside the `template-demo` zips.
2. Native module: `better-sqlite3` rebuilt for Electron for each architecture. If cross-building x64 on an arm64 runner fails, switch the workflow to a two-job matrix (one runner per architecture). If that fails too, report to the orchestrator with the fallback options listed in `05-macos-packaging.md`; do not swap the database library yourself.
3. `electron/smoke.ts` and a `--smoke` launch flag. In this wave the check is self-contained, because the real engine is being written in parallel: the packaged app opens a SQLite database in a temp dir (proves the native module loads), captures a tiny inline HTML page in a hidden window and checks the PNG size (proves offscreen capture works when packaged), prints `SMOKE OK`, exits 0. T3.1 later switches it to the real engine. `electron/main.ts` is not edited: T0.1 already routes the `--smoke` flag to `electron/smoke.ts` when that file exists.
4. `.github/workflows/ci.yml`: on pull request and push to `main` → `npm ci`, `npm run check` on Ubuntu (with `xvfb-run`).
5. `.github/workflows/release.yml`: on tag `v*` and manual dispatch → macOS runner, build, package both architectures, run the packaged app with `--smoke`, upload `.dmg` and `.zip` to a GitHub Release (draft for manual runs).
6. `docs/INSTALL.md` (Italian + English): download, drag to Applications, first-launch approval in System Settings → Privacy & Security → "Open Anyway", how to update, where the data lives, how to uninstall.
7. Workflow uses only the built-in `GITHUB_TOKEN` with `contents: write` on the release job. No other secrets.

**Acceptance**

- [ ] A manual run of `release.yml` on the task branch produces two `.dmg` files and the smoke step prints `SMOKE OK`.
- [ ] `ci.yml` is green on the task branch.
- [ ] `npm run dist:mac` works locally on a Mac (documented; verified by the user at the wave gate).
- [ ] `INSTALL.md` matches what actually happens on first launch.

---

## T1.6 — UI shell, shared components, API client

| | |
|---|---|
| **Agent / model** | `ui-dev` · sonnet · effort medium |
| **Depends on** | T0.2 |
| **Size** | M |

**Features**

1. App layout: left navigation (Partite, Avversari, Squadre, Template, Genera, Archivio, Impostazioni), content area, toast area. Works from 1024 px wide down to a phone width (needed later for T4.4).
2. Router with one route per page; each page is a **placeholder component in its own folder** under `src/ui/pages/<name>/index.tsx`, so Wave 2 tasks replace their own folder and never edit the router.
3. Typed API client generated from `src/shared/api.ts`: one function per route, zod-parsed responses, a single `ApiError`.
4. TanStack Query setup with sensible defaults and query-key helpers per entity.
5. MSW mock handlers for every route, backed by the T0.2 fixtures, switched on with `VITE_MOCK=1`. Wave 2 UI tasks develop against these.
6. Shared components: `Button`, `Field` (text/number/date/time/select/checkbox), `Table` (sortable, empty state), `Dialog`, `ConfirmDialog`, `Toast`, `Badge`, `DateRangePicker` with **weekend shortcuts** (questo weekend / prossimo / precedente), `FileDrop`, `ImageThumb`, `Spinner`, `EmptyState`.
7. Design tokens in CSS variables (club red `#CF3326`, neutrals, spacing, radius), Barlow fonts.
8. `src/ui/i18n/`: shared strings (navigation, buttons, common errors) and a tiny `t()` helper. Each page keeps its own `strings.it.ts` in its folder, so Wave 2 pages never edit a common file.
9. Component tests for `DateRangePicker` (weekend maths) and `Table`.

**Acceptance**

- [ ] `VITE_MOCK=1 npm run dev` shows the shell; every nav item opens its placeholder.
- [ ] The API client has a function for every route in `api.ts` (type-level test).
- [ ] No hard-coded user-visible string outside the strings files.
- [ ] `npm run check` passes.
