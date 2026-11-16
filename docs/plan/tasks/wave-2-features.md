# Wave 2 — Features (6 tasks in parallel)

Two API tasks and four UI tasks. The UI tasks develop against the mock API from T1.6, so they do not wait for the API tasks. Real wiring happens in T3.1.

**Gate to Wave 3:** all six merged into `main`, `npm run check` green, and with `VITE_MOCK=1` every page is usable end to end.

| Task | Agent | Model | Owns |
|---|---|---|---|
| T2.1 Data API | `backend-dev` | sonnet | `src/server/routes/data/**`, `scripts/seed.ts` |
| T2.2 Templates + render API | `backend-dev` | sonnet | `src/server/routes/render/**` |
| T2.3 Matches page | `ui-dev` | sonnet | `src/ui/pages/matches/**` |
| T2.4 Opponents, teams, settings pages | `chore-runner` | haiku | `src/ui/pages/opponents/**`, `teams/**`, `settings/**` |
| T2.5 Templates page | `ui-dev` | sonnet | `src/ui/pages/templates/**` |
| T2.6 Generate + archive pages | `ui-dev` | sonnet | `src/ui/pages/generate/**`, `archive/**` |

Each UI page keeps its strings in its own `strings.it.ts` inside its folder.

---

## T2.1 — Data API

| | |
|---|---|
| **Agent / model** | `backend-dev` · sonnet · effort medium |
| **Depends on** | T1.1, T1.4 |
| **Size** | M |

**Features**

1. Fastify plugins for teams, opponents, matches, settings exactly as in `src/shared/api.ts`; request and response validated with the shared schemas.
2. `GET /matches?from&to&teamId`: defaults to the coming weekend when no range is given.
3. `POST /matches/:id/duplicate`: copies a match to a given date (for repeated fixtures).
4. Opponent logo: `PUT /opponents/:id/logo` (multipart; PNG, JPEG, WebP or SVG; max 2 MB; stored in `userData/logos/` under a generated name; old file removed), `DELETE` to clear, `GET /logos/:file` to serve with caching headers and no path traversal.
5. SVG uploads are sanitised (scripts and external references removed) before saving.
6. Conflict errors from repositories mapped to HTTP 409 with a readable Italian message.
7. `POST /dev/seed` and `scripts/seed.ts` (`npm run seed`): load the fake data with today's date; copies seed logos into `userData/logos/`.
8. Integration tests with Fastify `inject` on an in-memory database: happy path and one failure per route, logo upload/replace/delete, seed endpoint.

**Acceptance**

- [ ] Every data route in `api.ts` is implemented and tested.
- [ ] `npm run seed` then `GET /api/matches` returns next weekend's fake matches.
- [ ] `npm run check` passes.

---

## T2.2 — Templates and render API

| | |
|---|---|
| **Agent / model** | `backend-dev` · sonnet · effort medium |
| **Depends on** | T1.1, T1.2, T1.3 |
| **Size** | M |

**Features**

1. `GET /templates` (manifest + a cached thumbnail URL), `POST /templates` (zip upload → validation problems returned as a list), `DELETE /templates/:id`, restore of built-ins.
2. `POST /templates/:id/preview`: body = optional match ids; without ids it uses the shared fixture. Returns a PNG. Thumbnails are generated once per template version and cached on disk.
3. `POST /render/plan`: body = `{ from, to, matchIds?, templateIds }` → images that would be produced and all warnings. No files written.
4. `POST /render`: same body → runs the render service, returns `RenderRecord`s and warnings. Progress is streamed with Server-Sent Events on `GET /render/progress/:jobId`.
5. `GET /renders`, `GET /renders/:id/file`, `POST /renders/zip` (streamed zip named `sergnanese_<from>_<to>.zip`), `POST /renders/reveal` (opens the folder in Finder).
6. Default selection rules, used when the request does not list templates:
   - `story-programme`: all scheduled matches in the range, one story set per day;
   - `post-prematch`: the first team's match in the range.
7. Postponed and cancelled matches are excluded by default and listed in the plan as "skipped".
8. Integration tests with the render service mocked, plus one real render test under Electron.

**Acceptance**

- [ ] Every render route in `api.ts` is implemented and tested.
- [ ] After `npm run seed`, `POST /render` for next weekend produces programme stories and one pre-match post on disk.
- [ ] Uploading a broken zip returns readable problems and installs nothing.
- [ ] `npm run check` passes.

---

## T2.3 — Matches page (the review-and-edit screen)

| | |
|---|---|
| **Agent / model** | `ui-dev` · sonnet · effort medium |
| **Depends on** | T1.6 |
| **Size** | M |

This page is decision D7: check and fix the weekend before generating.

**Features**

1. Weekend selector at the top (previous / this / next, or custom range); matches grouped by day, ordered by time.
2. Row: time, team, home/away marker, opponent with logo thumbnail, venue, round, status badge, lock icon, source badge.
3. Add and edit in a side dialog: team (select), opponent (searchable select with "create new" inline), date, time, home/away toggle that pre-fills the venue with the club's home venue, competition, round, status, score and half-time score, notes.
4. Inline quick edit for the two things that change most: time and venue.
5. Duplicate, delete (with confirm), lock/unlock.
6. Problems shown on the row before generating: no time, no venue, opponent without logo, opponent name that will be truncated (using `displayName` and the largest slot limit).
7. Filter by team and by status; a counter "N partite, M con avvisi".
8. Button "Genera immagini per questo weekend" → opens the Generate page with the range pre-selected.
9. Empty state with "Carica dati demo" (calls the seed endpoint) and "Aggiungi partita".
10. Component tests for the form validation and the warning logic.

**Acceptance**

- [ ] With mocks: add, edit, duplicate, delete, lock all work and the list refreshes.
- [ ] Warnings appear for the fixture match with the 45-character opponent and the one without a logo.
- [ ] Usable with keyboard only (tab order, Enter to save, Esc to close).
- [ ] `npm run check` passes.

---

## T2.4 — Opponents, teams and settings pages

| | |
|---|---|
| **Agent / model** | `chore-runner` · haiku |
| **Depends on** | T1.6 |
| **Size** | M |

Three plain CRUD screens built only from the shared components and the typed client. No design decisions, so haiku is assigned. If the reviewer rejects it twice, rerun on sonnet.

**Features**

1. **Avversari**: searchable table (logo, name, short name, number of matches); dialog to create/edit name, short name, aliases (chips); logo drop zone with preview and remove; a live "come apparirà" line showing `displayName` truncated to the default slot; delete blocked with the API's 409 message.
2. **Squadre**: table with drag or up/down ordering, name, short label, first-team radio (exactly one), active toggle; create/edit/delete.
3. **Impostazioni**: club name, short name, season, accent colour (colour input + hex), social handle, home venue, output folder (text field + "apri cartella"), a read-only line with the data folder path and app version.
4. Form validation from the shared zod schemas; errors shown next to fields.
5. Component tests: one per page for create and for a validation error.

**Acceptance**

- [ ] With mocks: full create/edit/delete cycle on opponents and teams; settings save and reload.
- [ ] Only shared components are used; no new styling system.
- [ ] `npm run check` passes.

---

## T2.5 — Templates page

| | |
|---|---|
| **Agent / model** | `ui-dev` · sonnet · effort medium |
| **Depends on** | T1.6 |
| **Size** | S–M |

**Features**

1. Grid of template cards: thumbnail, name, format badge (Post 1080×1350 / Story 1080×1920), kind (singola / elenco), purpose, version, "integrato" badge for built-ins.
2. Upload by drag-and-drop or file picker (`.zip`); validation problems listed clearly; on id clash ask "sostituire?".
3. Detail view: large preview, manifest fields, list of slots with their limits, list of required fields.
4. "Anteprima con una partita": pick a match (or a weekend for list templates) and see the real render.
5. Delete (user templates) and "ripristina" (built-ins).
6. Help panel linking to the template-writing guide from T1.2.

**Acceptance**

- [ ] With mocks: list, upload success, upload with problems, preview, delete, restore.
- [ ] Thumbnails keep the right aspect ratio for post and story.
- [ ] `npm run check` passes.

---

## T2.6 — Generate and archive pages

| | |
|---|---|
| **Agent / model** | `ui-dev` · sonnet · effort medium |
| **Depends on** | T1.6 |
| **Size** | M |

**Features — Genera**

1. Step 1, **Quando**: weekend selector (default: next weekend).
2. Step 2, **Partite**: the matches in range with checkboxes, pre-selected by the default rules; warnings per match with an "modifica" link that opens the match dialog; skipped (postponed/cancelled) matches shown greyed.
3. Step 3, **Template**: checkboxes per template, with a line saying what each will produce ("Story programma: 2 immagini (12 partite)", "Post pre-partita: Prima Squadra vs …").
4. Live plan from `POST /render/plan`: total images and all warnings, before anything is generated.
5. **Genera** → progress bar per image (SSE) → result gallery.
6. Gallery: thumbnails at the right aspect ratio, click to enlarge, per-image "mostra nel Finder" and "rigenera", plus "scarica ZIP" and "apri cartella".

**Features — Archivio**

7. Past renders grouped by weekend, filter by date range and template, same gallery actions, delete from archive (file stays unless "elimina anche il file" is ticked).

**Tests**

8. Component tests for the plan summary and for the step logic with zero matches, one match, twelve matches.

**Acceptance**

- [ ] With mocks: the full flow from weekend to gallery works, including the two-page programme case.
- [ ] Nothing is generated while the plan has blocking problems (no template selected, no match selected); warnings do not block.
- [ ] `npm run check` passes.
