# 01 — Architecture

This file is the technical reference for every task. Wave 0 turns the contracts below into real code in `src/shared/`. After Wave 0 that folder is **frozen**: no task may change it without going back through the `foundation-architect` agent.

## 1. Stack

| Layer | Choice | Notes |
|---|---|---|
| Shell | Electron (latest stable at implementation time) | Main process hosts the API and the renderer service. |
| Build | electron-vite + TypeScript (strict) | One `package.json` at the repo root. |
| API | Fastify, bound to `127.0.0.1` on a free port | Window loads `http://127.0.0.1:<port>`. LAN binding arrives in T4.4. |
| Validation | zod schemas in `src/shared/` | Same schemas for API, DB rows and template manifests. |
| Database | SQLite via `better-sqlite3` | Native module: validated on CI in T1.5. Fallback in `05-macos-packaging.md`. |
| Templating | Handlebars | Logic-less; safe for user-supplied templates. |
| Rendering | Hidden Electron `BrowserWindow` + Chrome DevTools Protocol screenshot | Exact pixel size regardless of Retina displays. |
| UI | React + React Router + TanStack Query, CSS modules | No UI framework; small set of shared components. |
| Fonts | `@fontsource/barlow`, `@fontsource/barlow-condensed` bundled | No Google Fonts request at render time. |
| Tests | Vitest (unit/integration); Playwright `_electron` for tests that need a real Electron process (`npm run test:electron`) and for e2e | `npm run check` runs all of them. |
| Packaging | electron-builder → `.dmg` + `.zip`, arm64 and x64 | Built by GitHub Actions, published to GitHub Releases. |

Exact versions are pinned in `package.json` by T0.1 and never bumped inside a feature task.

## 2. Repository layout and ownership

Ownership means: only the listed task may create or edit files there during its wave. This is what makes parallel work safe.

```
.
├── CLAUDE.md                      T0.0
├── .claude/agents/                T0.0 (copied from docs/plan/agents)
├── package.json, tsconfig*.json   T0.1 defines every npm script and dependency for v0.1.0; later only the orchestrator edits it
├── electron.vite.config.ts        T0.1
├── electron-builder.yml           T1.5
├── build/                         T1.5 (icons, entitlements)
├── .github/workflows/             T1.5
├── electron/
│   ├── main.ts                    T0.1 (skeleton), T3.1 (final wiring)
│   └── smoke.ts                   T1.5 (minimal), T3.1 (real engine)
├── src/
│   ├── shared/                    T0.2 — FROZEN after Wave 0
│   │   ├── types.ts               entities
│   │   ├── schemas.ts             zod schemas
│   │   ├── api.ts                 route table: method, path, request, response
│   │   ├── render-context.ts      data handed to templates
│   │   ├── manifest.ts            template manifest schema
│   │   ├── repositories.ts        repository interfaces
│   │   ├── text.ts                truncate / prefix-strip / slug / initials (pure functions + tests)
│   │   └── fixtures/              sample RenderContext JSON (single + list)
│   ├── server/
│   │   ├── app.ts                 T0.1 (autoloads route plugins; no task edits it later)
│   │   ├── paths.ts               T0.1 (userData, logos, templates, output dirs)
│   │   ├── db/                    T1.1
│   │   ├── services/templates/    T1.3
│   │   ├── services/render/       T1.3
│   │   ├── routes/data/           T2.1
│   │   └── routes/render/         T2.2
│   └── ui/
│       ├── app/                   T1.6 (layout, router, providers)
│       ├── components/            T1.6
│       ├── api/                   T1.6 (typed client + MSW mocks)
│       ├── i18n/                  T1.6 (shared strings + t() helper); each page keeps its own strings.it.ts in its folder
│       └── pages/
│           ├── matches/           T2.3
│           ├── opponents/         T2.4
│           ├── teams/             T2.4
│           ├── settings/          T2.4
│           ├── templates/         T2.5
│           ├── generate/          T2.6
│           └── archive/           T2.6
├── templates-builtin/             T1.2 (the 4 converted templates)
├── seed/                          T1.4
├── scripts/                       each task may add its own script, prefixed with its area
├── tests/electron/                T0.1 (harness + one trivial test), render/ subfolder T1.3
├── tests/e2e/                     T3.1
├── README.md                      T3.3
└── docs/                          plan (this folder), INSTALL.md (T1.5), USER-GUIDE.md + TEMPLATES.md (T3.3), qa/ (qa-reviewer)
```

Runtime data lives **outside the repo**, under Electron's `userData` folder (`~/Library/Application Support/Sergnanese Social/`):

```
db.sqlite            database
logos/               opponent logos (never committed: other clubs' trademarks, public repo)
templates/           installed templates (built-ins are copied here on first run)
```

Generated images go to `~/Pictures/Sergnanese Social/<YYYY-MM-DD>/` by default; the folder is a setting.

## 3. Data model

```ts
type ID = string;               // nanoid
type ISODate = string;          // 'YYYY-MM-DD'
type HHmm = string;             // '15:30'

interface Team {                // one of OUR teams
  id: ID; name: string;         // 'Prima Squadra', 'Juniores', 'Under 15'
  shortLabel: string;           // label used in programme rows
  sortOrder: number; isFirstTeam: boolean; active: boolean;
}

interface Opponent {
  id: ID; name: string;         // full official name
  shortName: string | null;     // manual override for display
  aliases: string[];            // name variants (used by imports in Wave 4)
  logoFile: string | null;      // file name inside userData/logos
}

type MatchStatus = 'scheduled' | 'postponed' | 'cancelled' | 'played';
type MatchSource = 'manual' | 'seed' | 'csv' | 'scrape' | 'pdf';

interface Match {
  id: ID; teamId: ID; opponentId: ID;
  date: ISODate; time: HHmm | null;
  isHome: boolean; venue: string;
  competition: string | null; round: number | null;      // 'Giornata N'
  status: MatchStatus;
  score: { us: number; them: number } | null;
  halfTime: { us: number; them: number } | null;
  notes: string | null;                                    // scorers / free text
  source: MatchSource; locked: boolean;                    // locked rows are never overwritten by imports
  createdAt: string; updatedAt: string;
}

interface Settings {
  clubName: string; clubShortName: string;                 // 'ASD Sergnanese', 'Sergnanese'
  season: string;                                          // '2026/27'
  accentColor: string;                                     // '#CF3326'
  socialHandle: string; homeVenue: string;
  outputDir: string; uiLanguage: 'it';
}

interface RenderRecord {
  id: ID; templateId: string; templateVersion: string;
  matchIds: ID[]; page: { index: number; total: number } | null;
  file: string; width: number; height: number;
  warnings: string[]; createdAt: string;
}
```

SQLite tables mirror these: `teams`, `opponents`, `matches`, `settings` (key/value), `renders`. Arrays and small objects are stored as JSON text. Foreign keys are on. Deleting a team or opponent that has matches is refused with a clear error.

## 4. Template format

A template is a folder (uploaded as a `.zip`):

```
post-prematch/
├── manifest.json
├── template.html        Handlebars; one root element of exactly width×height px
└── assets/              images, extra fonts, css, js
```

```jsonc
// manifest.json
{
  "id": "post-prematch",
  "name": "Post · Pre-partita",
  "version": "1.0.0",
  "format": "post",                 // 'post' | 'story'
  "width": 1080, "height": 1350,
  "kind": "single",                 // 'single' = one match per image, 'list' = many matches per image
  "purpose": "prematch",            // 'prematch' | 'programme' | 'halftime' | 'fulltime' | 'other'
  "pageSize": null,                 // list only: rows per image (programme = 10)
  "requires": ["match.time", "match.venue"],   // fields that must be present, else a warning
  "slots": {                        // text slots with overflow rules
    "teamName":  { "maxChars": 16, "onOverflow": "truncate" },
    "venue":     { "maxChars": 14, "onOverflow": "truncate" }
  }
}
```

Rules:

- **Network is blocked during render.** Everything a template needs is inside its folder or provided by the app (`{{asset "..."}}`, bundled fonts). This makes output identical on every machine.
- Template JS may run (animations must settle); the renderer waits for fonts, images and an optional `window.__ready` promise.
- Handlebars helpers provided by the app: `slot` (apply the slot's overflow rule), `upper`, `initials`, `asset`, `eq`, `pageLabel`.
- Uploads are validated: manifest schema, root size, no path traversal in the zip, size limit 20 MB, allowed file types only.

### Converting the four demo templates

`template-demo/*.zip` are design exports: an `<x-dc>` block with inline styles, `[Bracket]` placeholders, an `{{accent}}` variable, a React runtime (`support.js`, `vendor/`) and a Google Fonts link. Conversion (T1.2) keeps the markup and styles and:

- drops the runtime scripts and the `<x-dc>`/`<helmet>` wrappers;
- replaces Google Fonts with the bundled Barlow fonts;
- replaces `[Bracket]` text with Handlebars fields from the RenderContext;
- turns the ten copy-pasted programme rows into one `{{#each rows}}` block;
- replaces the dashed "LOGO" circle with the opponent logo, falling back to an initials circle;
- makes left/right follow home/away instead of always putting Sergnanese on the left.

## 5. RenderContext — the data a template receives

```ts
interface ClubCtx { name: string; shortName: string; logo: string; accent: string; season: string; handle: string; }

interface SideCtx { name: string; displayName: string; logo: string | null; initials: string; isUs: boolean; score: number | null; }

interface MatchCtx {
  category: string;                 // our team's name
  round: number | null; competition: string | null;
  dateLong: string;                 // 'Domenica 22 novembre'
  dateShort: string;                // 'Dom 22 nov'
  time: string | null; venue: string; isHome: boolean;
  home: SideCtx; away: SideCtx;     // in fixture order
  us: SideCtx; opponent: SideCtx;   // same objects, by role
  halfTime: { us: number; them: number } | null;
  notes: string | null; status: MatchStatus;
}

interface SingleContext { kind: 'single'; club: ClubCtx; match: MatchCtx; }

interface ListContext {
  kind: 'list'; club: ClubCtx;
  title: string;                    // 'Oggi in campo' / 'Weekend in campo'
  dateLabel: string;                // one day or a range
  rows: MatchCtx[];                 // already sliced to pageSize
  page: { index: number; total: number };
}
```

### Name display rule (decision D5)

`displayName` is computed once, in `src/shared/text.ts`:

1. If the opponent has a `shortName`, use it.
2. Otherwise strip common legal prefixes (`A.S.D.`, `ASD`, `U.S.`, `U.S.D.`, `G.S.`, `F.C.`, `A.C.`, `S.S.D.`, `Pol.`, `Polisportiva`). Words that identify the club, such as `Oratorio`, are kept.
3. In the template, `{{slot "teamName" match.opponent.displayName}}` truncates to the slot's `maxChars` at a word boundary and appends `…`.
4. Every truncation produces a warning shown in the Generate screen, with a link to set a short name.

## 6. Render pipeline

```
select matches + template
  → build RenderContext(s)            (list templates: sort by date/time, paginate by pageSize)
  → compile template.html with Handlebars
  → write filled HTML next to the template's assets (temp file)
  → hidden BrowserWindow (sandbox on, node off, network blocked) loads it
  → wait: document.fonts.ready, all <img> decoded, window.__ready if present
  → CDP Emulation.setDeviceMetricsOverride {width, height, deviceScaleFactor: 1}
  → CDP Page.captureScreenshot (png, clip = root size)
  → save file, insert RenderRecord, return warnings
```

Output file names:

```
<outputDir>/<match date>/<date>_<template id>_<team slug>_vs_<opponent slug>.png      single
<outputDir>/<first date>/<date>_<template id>_<page>of<total>.png                     list
```

Hard requirement: every PNG is **exactly** `width × height` pixels on Retina and non-Retina Macs.

## 7. API (all under `/api`, JSON, zod-validated)

| Method | Path | Purpose | Task |
|---|---|---|---|
| GET/POST | `/teams` | list / create | T2.1 |
| PATCH/DELETE | `/teams/:id` | update / delete | T2.1 |
| GET/POST | `/opponents` | list (search `?q=`) / create | T2.1 |
| PATCH/DELETE | `/opponents/:id` | update / delete | T2.1 |
| PUT/DELETE | `/opponents/:id/logo` | upload (multipart) / remove logo | T2.1 |
| GET | `/logos/:file` | serve a logo | T2.1 |
| GET/POST | `/matches` | list (`?from=&to=&teamId=`) / create | T2.1 |
| PATCH/DELETE | `/matches/:id` | update / delete | T2.1 |
| POST | `/matches/:id/duplicate` | copy a match | T2.1 |
| GET/PUT | `/settings` | read / write | T2.1 |
| POST | `/dev/seed` | load the fake data (also `npm run seed`) | T2.1 |
| GET | `/templates` | list installed templates | T2.2 |
| POST | `/templates` | upload a zip | T2.2 |
| DELETE | `/templates/:id` | remove (built-ins can be restored) | T2.2 |
| POST | `/templates/:id/preview` | render to a temp PNG, return it | T2.2 |
| POST | `/render/plan` | dry run: which images, which warnings | T2.2 |
| POST | `/render` | generate images | T2.2 |
| GET | `/renders` | archive (`?from=&to=`) | T2.2 |
| GET | `/renders/:id/file` | the PNG | T2.2 |
| POST | `/renders/zip` | zip of selected renders | T2.2 |
| POST | `/renders/reveal` | open the output folder in Finder | T2.2 |

Errors use one shape: `{ error: { code, message, details? } }`.

## 8. Security notes

- API listens on `127.0.0.1` only in v0.1.0.
- Template windows: `sandbox: true`, `contextIsolation: true`, `nodeIntegration: false`, all network requests cancelled.
- Zip uploads: reject absolute paths and `..`, cap size and file count.
- No secrets are needed by the app. Nothing private goes in the public repo.
