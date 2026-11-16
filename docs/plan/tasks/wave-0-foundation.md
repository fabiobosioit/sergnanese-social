# Wave 0 — Foundation (sequential)

Nothing in this wave runs in parallel: each task needs the one before it. The wave is small on purpose. Its output is what lets twelve later tasks run side by side.

**Gate to Wave 1:** T0.0–T0.2 merged into `main`, `npm run check` green, `npm run dev` opens an empty app window.

---

## T0.0 — Bootstrap Claude Code project files

| | |
|---|---|
| **Agent** | none — main session |
| **Model** | any (sonnet is fine; this is one command) |
| **Depends on** | plan merged into `main` |
| **Owns** | `CLAUDE.md`, `.claude/agents/**` |
| **Size** | XS |

**Do**

```bash
mkdir -p .claude/agents
cp docs/plan/agents/*.md .claude/agents/
cp docs/plan/CLAUDE.template.md CLAUDE.md
git add .claude CLAUDE.md && git commit -m "T0.0: Claude Code agents and project instructions"
```

**Acceptance**

- [ ] The eight agents are listed by Claude Code (ask: "which subagents are available?").
- [ ] `CLAUDE.md` is at the repo root.

---

## T0.1 — Project scaffold and tooling

| | |
|---|---|
| **Agent** | `backend-dev` |
| **Model** | sonnet · effort medium |
| **Depends on** | T0.0 |
| **Owns** | `package.json`, `tsconfig*.json`, `electron.vite.config.ts`, `eslint.config.*`, `.prettierrc`, `.gitignore`, `.nvmrc`, `electron/main.ts`, `src/server/app.ts`, `src/server/paths.ts`, `src/ui/index.html`, `src/ui/main.tsx` (placeholder), `playwright.electron.config.ts`, `tests/electron/app.spec.ts` |
| **Size** | M |

**Features**

1. Electron + electron-vite + TypeScript strict project at the repo root, Node version pinned in `.nvmrc`.
2. Three build targets: `electron/` (main), `src/server/` (bundled into main), `src/ui/` (renderer, React).
3. `electron/main.ts`: start the Fastify app on `127.0.0.1` with a free port, then open one `BrowserWindow` on that address. Single-instance lock. Quit when the window closes. When launched with `--smoke`, load `electron/smoke.ts` if it exists and exit with its result (the file is written by T1.5).
4. `src/server/app.ts`: Fastify factory `buildApp(deps)` that
   - autoloads every plugin under `src/server/routes/**` (so later tasks add files and never edit `app.ts`),
   - serves the built UI as static files,
   - has the single error shape `{ error: { code, message, details? } }`,
   - exposes `GET /api/health`.
5. `src/server/paths.ts`: resolves `userData`, `db.sqlite`, `logos/`, `templates/`, default output dir; creates folders on first run; overridable by `SS_DATA_DIR` env var for tests.
6. Dependencies installed now for the whole of v0.1.0, so later tasks do not touch `package.json`: `fastify`, `@fastify/static`, `@fastify/multipart`, `@fastify/autoload`, `zod`, `better-sqlite3`, `handlebars`, `nanoid`, `yauzl`, `yazl`, `react`, `react-dom`, `react-router-dom`, `@tanstack/react-query`, `@fontsource/barlow`, `@fontsource/barlow-condensed`; dev: `electron`, `electron-vite`, `electron-builder`, `typescript`, `vitest`, `@playwright/test`, `msw`, `eslint`, `prettier`, `@types/*`.
7. **All** npm scripts for v0.1.0 are defined now, so no later task edits `package.json`. Scripts whose target file is created by a later task print "not implemented yet (Txx)" and exit 0 until that file exists:

   | Script | Runs | Target created by |
   |---|---|---|
   | `dev`, `build`, `typecheck`, `lint` | electron-vite / tsc / eslint | T0.1 |
   | `test` | Vitest | T0.1 |
   | `test:electron` | Playwright `_electron` project in `tests/electron/` (under `xvfb-run` on Linux) | T0.1 |
   | `check` | `typecheck` + `lint` + `test` + `test:electron` + `test:e2e` | T0.1 |
   | `seed` | `scripts/seed.ts` | T2.1 |
   | `demo:render` | `scripts/demo-render.ts` | T1.3 |
   | `template:preview` | `scripts/template-preview.mjs` | T1.2 |
   | `dist:mac` | `electron-builder --mac --config electron-builder.yml` | T1.5 |
   | `test:e2e` | Playwright project in `tests/e2e/`, passing when there are no tests yet | T3.1 |
8. `.gitignore`: `node_modules`, `out`, `dist`, `release`, `.env*`, local data dirs, `*.sqlite`, `logos/`.
9. One trivial Vitest test and one trivial Electron test (`tests/electron/app.spec.ts`: the app starts and `/api/health` answers), so `npm run check` is meaningful and later tasks have a working harness to add to.

**Acceptance**

- [ ] `npm ci && npm run check` passes on a clean clone.
- [ ] `npm run dev` opens a window showing a placeholder page served by Fastify; `GET /api/health` returns `{ ok: true }`.
- [ ] A new file `src/server/routes/x/ping.ts` exporting a Fastify plugin is picked up without editing `app.ts` (covered by a test).
- [ ] Exact dependency versions recorded in `package.json` and `package-lock.json`.

---

## T0.2 — Shared contracts

| | |
|---|---|
| **Agent** | `foundation-architect` |
| **Model** | opus · effort high |
| **Depends on** | T0.1 |
| **Owns** | `src/shared/**` |
| **Size** | M |

Opus is used here because every other task codes against these files. A gap found in Wave 2 would stall six agents at once.

**Features**

1. `types.ts` and `schemas.ts`: the entities of `01-architecture.md` §3 as TypeScript types **inferred from zod schemas**, plus create/update input schemas for each entity.
2. `api.ts`: one typed route table for every endpoint in §7: method, path, params, query, body, response. Exported so that the server can register validators from it and the UI can build a typed client from it.
3. `render-context.ts`: `SingleContext`, `ListContext` and helpers' signatures (§5).
4. `manifest.ts`: template manifest schema (§4) with clear error messages for each invalid field.
5. `repositories.ts`: interfaces `TeamRepo`, `OpponentRepo`, `MatchRepo`, `SettingsRepo`, `RenderRepo`, including the query shapes (`matches.list({ from, to, teamId })`) and the "has matches" delete guard.
6. `text.ts`, implemented and unit-tested here because three tasks need it:
   - `stripLegalPrefixes(name)`,
   - `truncateAtWord(text, maxChars)` → `{ text, truncated }`,
   - `displayName(opponent)`, `initials(name)`, `slug(text)`,
   - `formatDateLong/Short(date, 'it')`, `weekendOf(date)` → `{ from: Saturday, to: Sunday }`.
7. `fixtures/`: `single.context.json`, `list.context.json` (10 rows), `list-23.context.json` (23 rows, for pagination), one of them with a 45-character opponent name and one opponent with no logo. These are the common test data for T1.2 and T1.3.
8. `README.md` in `src/shared/` explaining the freeze rule and how to request a change.

**Acceptance**

- [ ] Every endpoint in `01-architecture.md` §7 exists in `api.ts`; every entity in §3 has a schema.
- [ ] Fixtures validate against the schemas (test).
- [ ] `text.ts` has tests for: prefixes, word-boundary truncation, names shorter than the limit, accented characters, empty input.
- [ ] No runtime dependency other than `zod`.
- [ ] `npm run check` passes.
- [ ] `qa-reviewer` confirms the contracts cover every Wave 1 and Wave 2 task (it reads the task files and looks for anything a task needs that the contracts lack).
