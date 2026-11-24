# Wave 4 — After v0.1.0

These tasks are independent of each other and can run in parallel in any combination. They are specified more briefly than Waves 0–3 on purpose: each one gets a full task sheet (same format as Wave 1) written by `foundation-architect` just before it starts, using what was learned from real use.

Contract changes needed by a task are done first, by `foundation-architect`, in a short sequential step.

From here on the user has real data on this Mac. Every task keeps working in the Dev data folder; nothing may open the release data folder.

| Task | Agent | Model | Blocked on |
|---|---|---|---|
| T4.1 CSV/Excel import | — | — | **Suspended 2026-11-24** (user: no longer necessary; tuttocampo, CSI and PDF import cover it) |
| T4.2 Tuttocampo import (matches, names, logos) | `foundation-architect` (contract), `render-engineer`, `core-dev`, `ui-dev` | opus (contract, final gate) + sonnet | terms-of-use check, widget → team mapping |
| T4.3 PDF import (federation calendar: matches, names, venues, times) | `foundation-architect` (contract), `render-engineer`, `ui-dev`, `core-dev` | opus (contract) + sonnet | sample received 2026-11-24; spring-phase sample later |
| T4.4 Shortcuts support | `ui-dev` | sonnet | — |
| T4.5 Results workflow | `ui-dev` | sonnet | — |
| T4.6 Captions | `ui-dev` | sonnet | — |
| T4.7 Developer-ID signing and in-app updates | `release-engineer` | sonnet | paid Apple Developer account |
| T4.8 CSI Live import (matches, names, logos) through an in-app browser | `foundation-architect` (contract), `render-engineer`, `core-dev`, `ui-dev` | opus (contract, final gate) + sonnet | CSI terms-of-use check, a page saved by the user, team → page mapping |
| T4.9 Download all opponents (names + logos) from the tuttocampo standings and the CSI pages already read | `foundation-architect` (contract), `render-engineer`, `core-dev`, `ui-dev` | opus (contract) + sonnet | T4.2 and T4.8 merged |
| T4.10 Opponent matching: pre-filled links and proposals in every import review | `foundation-architect` (contract + matcher), `ui-dev` | opus medium (contract) + sonnet | **merged 2026-11-24** |
| T4.11 Tuttocampo season import: every matchday of each team, from today or the whole season | `render-engineer` (spike, source), `foundation-architect` (contract), `ui-dev`, `core-dev` | opus medium (contract) + sonnet | T4.2 merged (done); tuttocampo terms check covering ~30 requests per team |

---

## T4.1 — CSV/Excel import with review

**Suspended 2026-11-24.** Not needed any more; do not implement. The text below is kept for reference only.

- Open or drop a `.csv` or `.xlsx`; column mapping screen (date, time, team, opponent, home/away, venue) with the mapping remembered per file layout.
- Rows land in a **staging list**, never straight in the database. Each row is marked new / changed / unchanged / conflict with a locked match.
- Opponent matching by name and aliases with a similarity score; unmatched names offer "create" or "link to existing", and the choice is saved as an alias.
- Commit selected rows; an exportable template file with the expected columns.
- Model: sonnet. The logic is ordinary; the staging design is fixed by the contract step. `.xlsx` reading needs a library, chosen in the contract step.

## T4.2 — Tuttocampo import: matches, opponent names and logos

Decision D4: logos come from tuttocampo.it. The club site (sergnanese.com) shows tuttocampo.it widgets in an iframe. Method changed on 2026-11-22: the app does **not** read the iframe and does not use a `WKWebView`. The `htmlASD` experiment (`/Users/fabiobosio/src/prove/htmlASD/`) showed that each iframe URL, `https://www.tuttocampo.it/WidgetV2/{Risultati|Classifica}/<id>`, returns plain server-rendered HTML with the matches and the logo URLs. A browser is blocked only by CORS; a native app is not, so `URLSession` makes the same request directly.

Scope: matches, opponent names and opponent logos. Standings (`Classifica`) are not imported.

### Decisions (user, 2026-11-22)

- Only T4.2 is rewritten; Waves 0–3 are untouched.
- The tuttocampo.it terms-of-use check stays a **blocking** step before any code.

### Facts from the old project

- Widget IDs (snapshot of 2026-11-21): `c1e4e5c7-493e-46d6-b5a6-b53e6730900c`, `7486cae6-e1df-41a4-af64-ccc8e5c13786`, `1c6b18be-36a2-4ea4-add9-0604e671d95a`, `7b9d04d9-a571-45e2-b281-25d39c0d122a`, `0e12aeec-a1bd-4fc7-98e6-01fdcd28b507`, `e6c85afd-4f8f-482a-b971-108ffc9d8267`. Which ID belongs to which club team is **unknown**; the spike finds out.
- Results selectors: `#table_results_content table`, then `tr.date` (date in `span`) and `tr.match` → `.team.home` / `.team.away` → `.team-name`, `.goal`, `img[src]`; `.match-time` (+ `a[href]`). The matchday label is `.swiper-slide.selected span`.
- Empty state: `#content .message_info` = `Risultati non ancora disponibili.` is information, not an error.
- Relative URLs resolve against `<base href>` if present, else against the final response URL.
- A request returns only the **default matchday**, a fresh snapshot not tied to anything shown in an iframe.
- A widget is a whole league matchday (about 8 matches), not only our matches.

### Logo rule

The widget's `img[src]` points to a small copy, for example `https://b2-content.tuttocampo.it/Teams/40/917410.png?v=2`. The size folder and query string vary. Every club team has a numeric **ClubId** (`917410` is only an example), and a medium-size logo is at `https://b2-content.tuttocampo.it/Teams/200/<ClubId>.png` (chosen by the user over `Teams/Original/`, which reaches 1 MB).

1. **Get the ClubId** from the widget logo URL: host `b2-content.tuttocampo.it`, path `/Teams/<anything>/<digits>.<ext>`. ClubId = the digits; ignore the query string. A URL that does not match is not guessed: that opponent gets no logo and appears in the import report.
2. **Download `Teams/200/<ClubId>.png`**. If it fails (HTTP error, not an image, over the size cap), fall back to the widget's own `img[src]` once and note it in the report.
3. **Save it as `<ClubId>.png`** in the logos folder. `LogoStore` still converts every logo to PNG, at most 1024 px. One file per ClubId: the same ClubId seen twice is downloaded once.
4. Opponents are matched by name and aliases (as in T4.1). The ClubId is **not** a cross-team key: the spike (2026-11-22) showed the same real club has a different ClubId in each widget, and our own six teams each have their own. The opponent keeps a reference to the logo file it was given.
5. **Our side** is the row side whose team name is `Sergnanese` (compared with `ClubSettings.clubShortName`, normalised), not a ClubId. That side gives `isHome`; the other side is the opponent. Our own logo is not stored as an opponent logo. A row with no `Sergnanese` side is ignored. A widget that returns rows but none of ours raises the health check ("nessuna partita della Sergnanese trovata").
6. Do not download a logo when the opponent already has one, unless the user asks to replace it. A logo added by hand is never overwritten automatically.

The imported matches and logos are what the templates are filled from, through the normal match and opponent data.

### Errors

Any widget failure (network error, HTTP error, timeout, page structure changed, no rows of ours) is shown **in the app** as an Italian message naming the team, for example "Tuttocampo: impossibile leggere i risultati di <squadra>", never silently ignored. "Risultati non ancora disponibili." is information, not an error. A failure on one team or one logo does not stop the others.

Venue: the widget has none. Home = `ClubSettings.homeVenue`. Away = empty and flagged "da completare" in staging.

Widget-to-team mapping is done by the user in the app, in the widget ID field of each team. Spike findings (year inference, matchday path `/WidgetV2/Risultati/<id>/<N>?y=2026-27`, statuses, fixtures) are in `docs/plan/notes/t4.2-spike.md`; sanitised fixtures are in `Tests/Fixtures/tuttocampo/`.

### Corrections to the first draft

- A short contract step **is** needed: `Team` and `ClubSettings` have nowhere to store the widget ID, `AppServices` has no fixture source, there is no staging type, and `LogoStore` names files itself (`Services.swift:13-17`). `Sources/SSCore/` is frozen, so `foundation-architect` does it.
- T4.2 **builds** the staging review; T4.1 reuses it later (T4.1 is not implemented).
- `LogoStore` accepts PNG/JPEG/WebP/HEIC/SVG up to 5 MB, not GIF.

### Steps

**Step 0 — plan edit (this commit, docs only).**

**Step 1 — user, blocking.**
- Check the tuttocampo.it terms of use for automated reading. If not allowed, T4.2 stops and T4.1 (CSV) is the import path.
- Confirm the widget → team mapping proposed by the spike.

**Step 2 — spike** (`render-engineer`; throwaway, only a notes file is committed). Fetch each of the 12 widgets **once**. Record: team names per widget (the mapping proposal); date and time text formats; text for postponed or suspended matches; the `Giornata N` label; image hosts and content types; whether every logo `src` follows `Teams/<size>/<ClubId>.png` and every `Teams/Original/<ClubId>.png` exists (size, format); that ClubId `917410` appears in each of the 6 results widgets (and on which side); whether the URL accepts a matchday or date parameter. Produce **sanitised** HTML fixtures (fake team names, logo URLs pointing to a placeholder; the repo is public). Output: `docs/plan/notes/t4.2-spike.md` + fixtures.

**Step 3 — contract step** (`foundation-architect`, sequential).
- `Team.tuttocampoWidgetID: String?` (one ID serves Risultati and Classifica), with validation.
- No ClubId on `Opponent` or `ClubSettings` (see Logo rule): opponents match by name and alias.
- `LogoStore.importLogo(data:fileName:replacing:)`: the caller chooses the stored name, digits followed by `.png` only, rejected otherwise; an existing file with that name is replaced. The generated-name methods stay for logos added by hand.
- Pure functions `tuttocampoClubID(fromLogoURL:) -> String?` and `tuttocampoLogoURL(clubID:) -> URL` (the `Teams/200` URL).
- New types: `FixtureSource` protocol (`fetchFixtures(for team: Team) async throws -> FixtureFetch`; `FixtureFetch` = rows, or "not yet available", or a health problem); `FetchedFixture` (date, time, isHome, opponentName, opponentClubID (for the logo only), opponentLogoURL, score, round, raw status text); `ImportCandidate` with state new / changed / unchanged / locked / needs review.
- `AppServices.fixtureSource`, plus a fake in `SSCoreFakes`.
- Write the full T4.2 task sheet (Wave 1 format: owned paths, acceptance criteria, tests). Done:
  `wave-4-t4.2.md` (T4.2a, T4.2b, T4.2c, Step 5 and the exact `Package.swift` change).
- The orchestrator edits `Package.swift`: SwiftSoup pinned exact, new target `SSImport` (SSCore + SwiftSoup), `SSImportTests`, and `SSImport` added to the app and integration targets.

**Step 4 — three tasks in parallel, after Step 3 merges.**

| Task | Agent | Owns | Work |
|---|---|---|---|
| T4.2a fetch + parse | `render-engineer` | `Sources/SSImport/`, `Tests/SSImportTests/` | HTTP client (https only, host allowlist, timeout, response size cap, app `User-Agent`). Pure parser `HTML + baseURL → [FetchedFixture]`. Italian date parsing (year from `ClubSettings.season`). Keep only rows whose home or away name is `Sergnanese`; that side sets `isHome`. Year inferred from the season; fetch the default matchday. Score `-` → scheduled; numeric score → played; unknown status text → needs review. Health check on missing table or zero rows. Errors surface as typed failures, one per team. Logo downloader per the Logo rule: deduplicated by ClubId, limited concurrency, size and type check, saved through `LogoStore.importLogo(data:fileName:)`. Failures go to the report and never abort the import. Tests: ClubId extraction (`/Teams/40/917410.png?v=2`, other size folders, a non-matching URL), `Teams/200` first, fallback, deduplication. Sanitised fixtures and a `URLProtocol` stub; **no live network in tests**. |
| T4.2b data | `core-dev` | `Sources/SSData/`, `Tests/SSDataTests/` | Migration for `teams.tuttocampoWidgetID`. `LogoStore.importLogo(data:fileName:)` with name validation and replace. Repository tests. |
| T4.2c UI | `ui-dev` | `Sources/SSApp/Features/Import/` (new), Teams editor field, `Strings` | Menu/toolbar "Importa da Tuttocampo…" in Matches. Staging sheet with candidates grouped by weekend; the coming weekend ticked by default. Each row shows new/changed/unchanged/locked/needs review. Opponents not found: "crea" or "collega a esistente" (saved as an alias). Away venue to fill in. Messages "la sorgente potrebbe essere cambiata" and "risultati non ancora disponibili". Commit via `upsertFromImport` with `source: .scrape`. Widget ID field in the Team inspector. Built against the fake source. |

**Step 5 — wiring** (`core-dev`). Real `TuttocampoWidgetSource` in `Sources/SergnaneseSocial/Composition.swift`. Integration test with the `URLProtocol` stub: fixture HTML → staging → database → logos in the temp `SS_DATA_DIR`.

**Step 6 — gate and release.** `qa-reviewer`: acceptance criteria, Mac design rules, Light/Dark, a manual run against the live site. `chore-runner`: USER-GUIDE section. `release-engineer`: v0.2.0.

### Model and effort per step

Rule from `02-agents-and-models.md`: the cheapest model that finishes without rework. Overrides are passed at dispatch (the Agent tool's `model` / `effort`); the agent files do not change.

| Step | Agent | Agent default | Dispatch with | Why |
|---|---|---|---|---|
| 0 plan edit | main session | — | sonnet, medium | Content is fixed; transcription only. |
| 2 spike | `render-engineer` | opus, high | sonnet, medium | Selectors are known; fetch, record, anonymise. |
| 3 contract + sheet | `foundation-architect` | opus, high | opus, high | Frozen contracts: a mistake costs every later task. |
| 3b `Package.swift` | main session | — | sonnet, low | A few lines, exact versions given. |
| 4 T4.2a | `render-engineer` | opus, high | sonnet, high | Ordinary parsing against real fixtures; `high` for the Swift 6 async parts. Escalate to opus if it fails twice. |
| 4 T4.2b | `core-dev` | sonnet, medium | sonnet, medium | Small GRDB migration. |
| 4 T4.2c | `ui-dev` | sonnet, medium | sonnet, medium | Standard SwiftUI against the fake source; `high` only on retry. |
| 5 wiring | `core-dev` | sonnet, medium | sonnet, medium | One composition change and one test. |
| gate (T4.2b, T4.2c, step 5) | `qa-reviewer` | opus, high | sonnet, medium | Well-defined acceptance criteria. |
| gate (T4.2a + final) | `qa-reviewer` | opus, high | opus, high | Network, untrusted HTML, file names from remote data. |
| 6 USER-GUIDE | `chore-runner` | haiku | haiku | Prose only. |
| 6 release v0.2.0 | `release-engineer` | sonnet, medium | sonnet, low | Scripts exist; bump, changelog, tag. |

Escalation is unchanged: a failed task retries once on the same model with the reviewer's findings; a second failure reruns one model up (sonnet → opus). A needed contract change stops the task and goes to `foundation-architect`.

### Rules

- Requests only when the user presses import: one per mapped team plus missing logos. No polling or background work.
- Third-party HTML is parsed only, never rendered or run. SVG logos are rasterised by `LogoStore`.
- Locked matches are never overwritten (existing `upsertFromImport` rule).
- Dev data folder only; no real logos or club HTML committed.
- The security notes in `01-architecture.md` §8 are updated with this feature.

## T4.3 — PDF import: federation calendar

Rewritten on 2026-11-24 from the user's sample, `examples/Calendario_EsordientiMiste_Femm_Aut.pdf`: the U13 women championship ("ESORDIENTI MISTE FEMM. AUT."), autumn phase, girone B, 9 teams, 9 matchdays. The file stays **outside git**: it holds real club names and addresses, and the repo is public. Tests use a synthetic PDF.

Scope: our scheduled matches (date, time, home/away, opponent, venue, round, competition) and the opponents' names. The PDF has **no team logos**: opponents get logos from T4.9, from tuttocampo/CSI imports, or by hand.

### The layout (checked with PDFKit on 2026-11-24)

Two A4 landscape pages (842 × 595 pt), created by PDFium, with real text (no OCR needed). `page.string` returns the text in a **jumbled order** (columns run into each other), so the parser must use **line positions**: `page.selection(for: mediaBox).selectionsByLine()` gives one line per entry, each with its own bounds. That gave clean results on the sample.

**Page 1 — calendar grid**

| Item | Where | Example |
|---|---|---|
| Category | title line, top centre | `ESORDIENTI MISTE FEMM. AUT.` |
| Phase and girone | second title line | `FASE AUTUNNALE - GIRONE B` |
| Matchday blocks | 3 columns (x ≈ 60, 340, 610) × 3 rows | `GIORNATA 1` … `GIORNATA 9` |
| Matchday date | the line under each `GIORNATA n` | `A. 03/10/2026`: `A.` = andata (autumn); the spring phase is expected to use `R.`. The date is always the Saturday of the weekend. |
| Match rows | lines under the date, same column, until the next block | `CREMONESE- RIOZZESE`: home, then `"- "`, then away |
| Bye | a row whose home side is `Riposo` | `Riposo- PAVIA CALCIO 1911` |

Lines are assigned to a block by column (x of the line's centre) and by vertical band (between this block's `GIORNATA` line and the next one below it).

**Page 2 — club table**

Header `Società | N. | Campo / Località | Indirizzo | Orario | Giorno`; one row per club, aligned by y (rows about 16 pt apart). Columns are found from the header x positions.

| Column | Example | Use |
|---|---|---|
| Società | `SAN BERNARDO CALCIO`, `ALCIONE MILANO SSD A RL`, `SERGNANESE A.S.D.` | full official name → alias of the opponent |
| N. | `2015` | club number in the federation; recorded, not used as a key |
| Campo / Località | `C.S.COMUNALE N.1 - SERGNANO - SERGNANO` | venue |
| Indirizzo | `VIA VALLARSA 4` | appended to the venue in notes (venue field limits apply) |
| Orario | `15.30`, `9.30` | home kick-off time → `ClockTime` (`9.30` → `09:30`) |
| Giorno | `Sabato`, `Domenica` | home match day |

### Rules (user decisions, 2026-11-24)

1. **Date and time come from the home club.** Date = the matchday date, **+1 day when the home club's Giorno is Domenica**. Time = the home club's Orario. Example: `RIOZZESE- REAL MEDA CF Sq.B` on `A. 10/10/2026`, where RIOZZESE plays Domenica at 9.30, becomes **Sun 11/10/2026, 09:30**. A home club missing from page 2 → the Saturday date, no time, "needs review".
2. **Venue:** away matches get the home club's `Campo / Località` from page 2. **Our home matches keep `ClubSettings.homeVenue`.**
3. **Opponent name = the short page-1 name** (`S. BERNARDO CALCIO`, `ALCIONE`, `REAL MEDA CF Sq.B`). **The full page-2 name becomes an alias** (`SAN BERNARDO CALCIO`, `ALCIONE MILANO SSD A RL`), so other imports still match it.
4. **Our matches:** rows where one side is our club. Compare with `ClubSettings.clubShortName` using `searchKey` after `stripLegalPrefixes`: `SERGNANESE` matches, and on page 2 `SERGNANESE A.S.D.` matches after the suffix is stripped. That side gives `isHome`. Other rows are ignored.
5. **Our bye** (`Riposo- SERGNANESE`) creates no match. The review shows it as information: "Giornata 8: riposo".
6. **Layout:** this federation layout only (calendar grid + club table), for other categories and for the spring phase. A PDF that does not fit it is refused with "Formato PDF non riconosciuto"; nothing is guessed.
7. **Team:** the user picks which of our teams the PDF belongs to (picker in the import flow). The category title is shown to help. Remembering the choice per title is optional; the contract step decides.
8. Every row goes through the **same staging review** as T4.2/T4.8 (`ImportCandidate.make`, states, create/link opponent, commit with `upsertFromImport`, `source: .pdf`). Round = the GIORNATA number. Competition = `<category> – <phase> – <girone>` (cut to the field limit). Status = scheduled.

### Short name → page-2 club

Page 1 uses short names and page 2 full names, so each page-1 name is linked to one page-2 row:
1. Normalise both: upper case, collapse spaces, remove dots. Strip legal words and suffixes (`A.S.D.`, `ASD`, `S.P.A.`, `SSD`, `A RL`, `A R.L.`, `S.R.L.`, the `stripLegalPrefixes` list). Compare the squad letter case-insensitively (`Sq.B` = `sq.B`).
2. Expand `S.` to `SAN`/`SANTO`/`SANTA` only to compare.
3. Link when exactly one page-2 row equals the short name, or starts with all of its words (`ALCIONE` → `ALCIONE MILANO SSD A RL`, `CREMONESE` → `CREMONESE S.P.A.`).
4. When one page-1 name and one page-2 row are left over after the others are linked, link them.
5. Anything still unlinked → that club's home matches get no time or venue and are flagged "needs review". The review shows the unlinked names.

**Health check:** the number of distinct page-1 teams (without `Riposo`) must equal the page-2 rows. If they differ, the review shows a warning ("il PDF sembra incompleto") but still lists what was read.

**Sample coverage:** all 9 short names link by rules 1–3. Sergnanese plays 8 matches in 9 matchdays, with the bye on matchday 8.

### Contract changes needed (`foundation-architect`)

- `PDFCalendar`: category, phase, girone, matchdays (`number`, `leg` = andata/ritorno, `date`), clubs (`fullName`, `number`, `venue`, `address`, `time`, `weekday`), the short-to-full links, and `fixtures: [FetchedFixture]` for our matches. Plus `byes` and `problems` (unlinked names, count mismatch, unrecognised layout).
- `PDFCalendarParser` protocol: `parse(pdf: Data, settings: ClubSettings) throws -> PDFCalendar`, pure, no network. Errors: not a PDF, too large (cap 10 MB / 20 pages), encrypted, layout not recognised.
- `FetchedFixture` gains `opponentAliases: [String]` (the page-2 full name), used by `ImportCandidate.make` when an opponent is created or linked. `venue` already exists.
- `ImportIssue` cases: layout not recognised, PDF incomplete (count mismatch), club not linked (name).
- Fake parser in `SSCoreFakes`.
- Task sheet `docs/plan/tasks/wave-4-t4.3.md` (Wave 1 format). PDFKit is a system framework: no `Package.swift` change is expected. The parser goes in `SSImport/PDF/`.

### Steps

**Step 0 — plan edit** (this section, docs only).

**Step 1 — user.**
- Keep the sample outside git: `examples/` is untracked; add it to `.gitignore` or move the file out.
- Send a spring-phase PDF (`R.` dates) when available. The parser treats `R.` like `A.`; the sample confirms it later.

**Step 2 — fixture and spike** (`render-engineer`). A small Swift script that **generates a synthetic PDF** with the same layout and coordinates (PDFKit/CoreGraphics). It uses fake club names, including a squad letter, an `S.` name, a Domenica home club, a `9.30` time and our club with one bye. Commit it with the generated file in `Tests/Fixtures/pdf/` (generator + `calendar-sample.pdf`), plus two variants: a page-2 club missing, and a non-federation PDF. Record the measured column x positions and line spacing of the real sample in `docs/plan/notes/t4.3-pdf-spike.md`. **No real names in the repo.**

**Step 3 — contract step** (`foundation-architect`): the changes above + the task sheet.

**Step 4 — two tasks in parallel.**

| Task | Agent | Owns | Work |
|---|---|---|---|
| T4.3a parser | `render-engineer` | `Sources/SSImport/PDF/`, `Tests/SSImportTests/PDF/` | Read lines with bounds through PDFKit. Page 1: blocks by column and band; date and leg; rows split at `"- "` (exactly one split, else needs review); byes. Page 2: columns from the header; rows by y. Short-to-full linking (rules above). Our fixtures with date +1 on Domenica, home time, away venue, round, competition, aliases. Health checks. Tests on the synthetic fixtures, including rule 1's Sunday example, a missing club, an unrecognised PDF, encrypted and oversized files. |
| T4.3b UI | `ui-dev` | `Sources/SSApp/Features/Import/` (PDF entry), Strings | "Importa da PDF…" in Matches (toolbar and File menu). Open panel limited to PDF, plus dropping a PDF on the Matches list. Team picker showing the category title. Then the existing staging sheet and report, with the extra notices (byes, unlinked clubs, incomplete PDF). Italian strings. Built against the fake parser. |

**Step 5 — wiring** (`core-dev`). Real parser in `Sources/SergnaneseSocial/Composition.swift`. Integration test: synthetic PDF → parser → staging → database, checking a Sunday date, a home time, an away venue, an alias and our home venue from Settings.

**Step 6 — gate and release.** `qa-reviewer`: acceptance criteria, Mac design (open panel, drop target, Light/Dark), and one run with the user on the real sample. Expected: 8 Sergnanese matches with the right dates, times and venues. `chore-runner`: USER-GUIDE subsection "Importare un calendario PDF". `release-engineer`: in the next release.

### Model and effort per step

The sample is regular and its text comes out cleanly with positions, so the original "opus for the parser" drops to sonnet. Opus stays only on the contract.

| Step | Agent | Agent default | Dispatch with | Why |
|---|---|---|---|---|
| 0 plan edit | main session | — | sonnet, low | This section is the content. |
| 2 fixture + spike | `render-engineer` | opus, high | sonnet, medium | A generator script reproducing measured coordinates. |
| 3 contract + sheet | `foundation-architect` | opus, high | opus, high | Frozen contracts; `FetchedFixture` is shared with T4.2/T4.8. |
| 4 T4.3a parser | `render-engineer` | opus, high | sonnet, high | Geometry grouping and name linking need care, but the layout is fixed and fully described here. Escalate to opus if it fails twice. |
| 4 T4.3b UI | `ui-dev` | sonnet, medium | sonnet, medium | Open panel, drop and picker in front of the existing staging sheet. |
| 5 wiring | `core-dev` | sonnet, medium | sonnet, low | One composition line + one integration test. |
| gate (each task) | `qa-reviewer` | opus, high | sonnet, medium | Well-defined acceptance criteria. |
| gate (final, real sample) | `qa-reviewer` | opus, high | sonnet, high | Local file, no network. The risk is wrong dates or times, checked against the real sample. |
| 6 USER-GUIDE | `chore-runner` | haiku | haiku | Prose only. |
| 6 release | `release-engineer` | sonnet, medium | sonnet, low | Existing scripts. |

Escalation is unchanged: retry once on the same model with the reviewer's findings, then one model up.

### Rules

- Local files only: no network, and nothing in the PDF is run (PDFKit text only).
- Size and page caps; encrypted PDFs are refused with a message.
- Locked matches are never overwritten. Opponents are created or linked only from the review.
- No real PDFs, names or addresses in the repo; tests use the synthetic fixture.

## T4.4 — Shortcuts support

- App Intents for "Genera le immagini del weekend" and "Mostra le partite del weekend", so the weekly job can be started from Shortcuts or Spotlight.
- Needs a check that App Intents metadata can be produced without Xcode; if not, this task waits for T4.7's toolchain decision.
- Model: sonnet.

## T4.5 — Results workflow

- Quick form per match: half-time score, final score, scorers → one click to generate the half-time or full-time story and open the share picker.
- Weekly results recap template (new built-in, `kind: list`).
- Model: sonnet. The recap template itself goes to `template-converter`.

## T4.6 — Captions

- For each generated image, a ready caption (Italian) with date, opponent, venue, club hashtags; copied with the image or on its own; editable caption patterns in Settings.
- Model: sonnet. Small, but it touches the gallery component and Settings.

## T4.7 — Developer-ID signing, notarization and in-app updates

- Only if the first-launch approval step proves to be a real obstacle for other volunteers.
- Needs a paid Apple Developer account and certificates stored as GitHub Actions secrets.
- With proper signing, add in-app updates (Sparkle) so "Scarica aggiornamenti…" installs the new version itself.
- Model: sonnet.

## T4.8 — CSI Live import: matches, opponent names and logos

Second import source, added on 2026-11-22. Some club teams play in CSI (Centro Sportivo Italiano) leagues. Their league ("girone") page on CSI Live shows the standings and the matches, with or without results, and the opponents' logos. Example (a 2016-born age group, Crema committee):

```
https://live.centrosportivoitaliano.it/26/Calcio-a-11/Lombardia/Crema/C36048/G283123-girone-a-2016/?j=NEU9RUZGJjRGPVBOWSY0Rz1HSkRITCY0SD1GTEdFRkcmNEk9VHY0MTByIE4gLSBGREVKJjRMPUVGRiY0Mj1l
```

Scope is the same as T4.2: matches, opponent names and opponent logos. Standings are **not** imported.

### Why the T4.2 method cannot be used

Checked on 2026-11-22: a plain request for the page returns `HTTP 403` with `cf-mitigated: challenge` and `server: cloudflare`. The site deliberately runs a Cloudflare bot check, so **the app does not fetch CSI pages by itself**. The plan does not get around the check: no faked browser identity, no automated solving of the check, no reuse of the browser's cookies outside its web view.

### Method: the user opens the page, the app reads what is on screen

1. In Matches, "Importa da CSI…" opens a **visible browser window** (`WKWebView`) on the CSI page stored for the chosen team.
2. The user browses as in Safari. If Cloudflare shows a check, the user passes it.
3. The user presses **"Importa questa pagina"**. The app reads that page's HTML once (`document.documentElement.outerHTML`), parses it in Swift with SwiftSoup, and opens the **same staging sheet as T4.2** (`ImportCandidate.make`, states, create/link opponent, away venue, report, commit with `upsertFromImport`, `source: .scrape`).

The app never navigates, clicks or reloads by itself and does no polling or background work. One press reads one page, the one on screen.

Browser window rules:
- Its own persistent website data store (`WKWebsiteDataStore(forIdentifier:)`, one fixed identifier for CSI). It is separate from the template renderer's non-persistent store, so the user is not checked every week. A "Cancella dati del sito CSI" command removes it.
- Navigation only to `live.centrosportivoitaliano.it` and `challenges.cloudflare.com` (the check). Any other link opens in the default browser. Pop-ups are refused.
- No script message handlers. The page cannot call into the app; only the app queries the page (`evaluateJavaScript` / `callAsyncJavaScript`).
- The page HTML is parsed, never passed to the template engine. It has a size cap (2 MB).

### Our matches and opponents

- **Ours:** same rule as T4.2. A row is ours when one side's name equals `ClubSettings.clubShortName`, compared with `searchKey` after `stripLegalPrefixes`. That side gives `isHome`; other rows are ignored. The spike confirms how CSI writes our name (for example "Sergnanese", "ASD Sergnanese", or with the age group appended). If CSI appends text, the parser normalises it with an explicit rule recorded in the notes.
- **Opponents:** matched by name and aliases, as in T4.2. No CSI ID is used as an opponent key, for the same reason as the tuttocampo ClubId: an ID per team, not per club, is likely. The spike checks this.
- **Dates and years:** CSI writes `dd/MM/yy` with a two-digit year (spike), so no season inference is needed. An unparseable row → needs review.
- **Duplicates:** the rendered page repeats every match about five times (110 matches, 550 rows in the example). The parser dedupes by the match code in the row link (`P263A1`).
- **Venue:** read from the row's tooltip (`data-bs-title`, name and address, trailing `(code)` removed).
- **Status:** score present → played; no score → scheduled; known CSI texts for postponed or cancelled matches map to those statuses; anything else → needs review with the raw text shown.
- **Whole calendar:** the page may show every round, not one matchday. The staging sheet already groups by weekend and ticks only the coming weekend by default.

### Logos

Logos are taken **inside the page session**, never by a separate request against the protected site:

1. In the page, with `callAsyncJavaScript`, `fetch(img.src)` for each opponent logo the page already shows; the bytes come back to Swift (base64), with a 5 MB cap per logo. This works when the image is same-origin or allows CORS.
2. If the logo host is **not** behind the bot check (the spike found `static.centrosportivoitaliano.it`, a different host from the page; T4.8c confirms it live with the user), a plain `URLSession` download, using the T4.2 rules: https, a host allowlist (that one host), a timeout, the size cap and no cookies.
3. Otherwise: no logo, and the opponent is listed in the report ("logo non disponibile").

The CSI placeholder shield (`csi-shield-b.svg`, host `cdncsi.csi-net.it`) means "no logo": never imported, never fetched. Logos are JPEG; `LogoFileStore` converts them to PNG.

The logo is stored with `LogoStore.importLogo(data:fileName:replacing:)` as `csi-<id>.png` when the logo URL carries a stable numeric ID, else `csi-<slug(opponent name)>.png`. T4.2's rule 6 applies: an opponent that already has a logo, from tuttocampo or added by hand, is not changed unless the user asks.

### Errors

Shown in the app in Italian, naming the team, never silently:
- page with no recognisable match table → "CSI: la pagina aperta non sembra un girone CSI";
- rows found but none of ours → "nessuna partita della Sergnanese in questa pagina";
- page too large, or reading the page failed.

A logo failure never stops the import.

### Contract changes needed (`foundation-architect`)

Built on the T4.2 contract (`Sources/SSCore/Import.swift`, `Tuttocampo.swift`):
- `Team.csiPageURL: String?` with validation (https, host exactly `live.centrosportivoitaliano.it`, length cap), its `ValidationField`, and the `TeamRepository` rule (one page per team).
- `isValidImportedLogoFileName` also accepts `csi-[a-z0-9-]{1,60}.png`; add a pure `csiLogoFileName(id:name:)`.
- `ImportIssue` gains a source (tuttocampo / CSI) or CSI cases, so messages say "CSI: …" instead of "Tuttocampo: …". Also cases for "page is not a CSI girone" and "logo not available".
- A logo request for CSI: carries page-obtained bytes or a URL, not a `clubID`. `FetchedFixture.opponentClubID` stays tuttocampo-only.
- `PageFixtureParser` protocol: `parse(html:pageURL:settings:) -> FixtureFetch`, a pure function. It reuses `FetchedFixture`, `FixtureFetch` and `FixtureHealthProblem`. A fake in `SSCoreFakes`.
- No change to `FixtureSource`: it stays the network path for tuttocampo.

### Steps

**Step 1 — user, blocking.**
- Check the CSI Live terms of use for reading pages the user opens in an app. If not allowed, T4.8 stops. T4.2 is not affected.
- In Safari, open the girone page and save it twice into a folder **outside the repo**: File → Save As → "Archivio web", and File → Save As → "Sorgente pagina". Repeat for a second CSI team if one exists.
- Say which club team each CSI page belongs to.

**Step 2 — spike** (`render-engineer`; **local files only, no requests to CSI**). First findings from the user's example page are in `docs/plan/notes/t4.8-csi-spike.md` (2026-11-22); the spike confirms them, sanitises the fixture and fills the gaps (postponed text, missing time, per team or per club IDs). From the saved page, record:
- the selectors for match rows: date, time, home, away, score, round, status text;
- whether the page has a venue;
- the date format;
- how our team is named;
- whether teams have stable IDs in links or logo URLs, and whether they are per team or per club;
- the logo URLs and their host (from the URL only);
- whether the page shows one round or the whole calendar.

Produce a **sanitised** fixture (fake names, placeholder logo URLs; the repo is public). Output: `docs/plan/notes/t4.8-csi-spike.md` and `Tests/Fixtures/csi/`.

**Step 3 — contract step** (`foundation-architect`): the changes above + the full task sheet `docs/plan/tasks/wave-4-t4.8.md` (Wave 1 format). No `Package.swift` change is expected: `SSImport` already depends on SwiftSoup, and WebKit is a system framework. If the browser needs a new target, the sheet says so and the orchestrator adds it.

**Step 4 — three tasks in parallel, after Step 3 merges.**

| Task | Agent | Owns | Work |
|---|---|---|---|
| T4.8a CSI parser | `render-engineer` | `Sources/SSImport/CSI/`, `Tests/SSImportTests/CSI/` | Pure parser `HTML + page URL → FixtureFetch` from the spike fixture: our side by name, `isHome`, dates and year, statuses, round, opponent name, logo URL and ID. Health checks. Tests on the fixture, plus variants: no table, no rows of ours, unknown status, missing year. |
| T4.8b data | `core-dev` | `Sources/SSData/`, `Tests/SSDataTests/` | Migration for `teams.csiPageURL`; the `LogoFileStore` accepts `csi-…png` names; tests. |
| T4.8c browser + logos | `render-engineer` | `Sources/SSApp/Features/Import/CSIBrowser/`, its tests | Browser window: persistent CSI data store, navigation allowlist, external links in the default browser, no pop-ups, no message handlers, page size cap, "Importa questa pagina" (one `outerHTML` read). Logo retrieval in the page session (in-page `fetch`, else `URLSession` only to a host proven unprotected, else none); stored as `csi-<id or slug>.png`. "Cancella dati del sito CSI". Tests: navigation decisions, file names, logo size cap. Acceptance includes one manual run with the user on the real page. |

**Step 5 — UI and wiring** (`ui-dev`, after Step 4). "Importa da CSI…" in Matches (menu and toolbar, next to "Importa da Tuttocampo…"), with a team picker limited to teams that have a CSI page. Opening the browser; the parser result goes into the existing staging sheet and report (`Sources/SSApp/Features/Import/`). "Pagina CSI" field in the Team inspector (paste the address). Italian strings in `ImportStrings`/`Strings`. Real parser wired in `Sources/SergnaneseSocial/Composition.swift`. Integration test: fixture HTML → parser → staging → database (no browser, no network).

**Step 6 — gate and release.** `qa-reviewer`: acceptance criteria, Mac design rules for the browser window, Light/Dark, security (navigation policy, data store, no message handlers), and one live run with the user. `chore-runner`: a USER-GUIDE section "Importare da CSI". `release-engineer`: in the next release after T4.2's v0.2.0.

### Model and effort per step

Same rule as T4.2: the cheapest model that finishes without rework. Overrides are passed at dispatch.

| Step | Agent | Agent default | Dispatch with | Why |
|---|---|---|---|---|
| 2 spike | `render-engineer` | opus, high | sonnet, medium | Reads a local file; records selectors; anonymises. |
| 3 contract + sheet | `foundation-architect` | opus, high | opus, high | Frozen contracts shared with T4.2's import types. |
| 4 T4.8a parser | `render-engineer` | opus, high | sonnet, medium | A pure parser against a fixture, like T4.2a but with no network or concurrency. |
| 4 T4.8b data | `core-dev` | sonnet, medium | sonnet, low | One column and one file-name rule. |
| 4 T4.8c browser + logos | `render-engineer` | opus, high | sonnet, high | `WKWebView` on the main actor, a persistent data store, `callAsyncJavaScript`, the navigation policy. Escalate to opus if it fails twice. |
| 5 UI + wiring | `ui-dev` | sonnet, medium | sonnet, medium | Reuses the T4.2 staging sheet; a new menu item and field. |
| gate (T4.8a, T4.8b, step 5) | `qa-reviewer` | opus, high | sonnet, medium | Well-defined acceptance criteria. |
| gate (T4.8c + final) | `qa-reviewer` | opus, high | opus, high | A visible web view on an untrusted site, a persistent data store, file names from remote data. |
| 6 USER-GUIDE | `chore-runner` | haiku | haiku | Prose only. |
| 6 release | `release-engineer` | sonnet, medium | sonnet, low | Existing scripts. |

Escalation is unchanged: retry once on the same model with the reviewer's findings, then one model up.

### Rules

- The page is read only when the user presses "Importa questa pagina"; logos are read only from that page's session.
- No bypass of the site's protection, and no automated navigation.
- Third-party HTML is parsed only. SVG logos are rasterised by `LogoStore`.
- Locked matches are never overwritten. Logos already present are not replaced automatically.
- Dev data folder only; no real logos or club HTML committed.
- The security notes in `01-architecture.md` §8 cover the CSI browser window.

## T4.9 — Download all opponents at once

Added on 2026-11-24. One action in **Avversari** fills the opponent list, names and logos, for every league our teams play in. The user no longer waits for each opponent to appear in a match import. It reuses the addresses already stored for T4.2 and T4.8; no new site and no new address to enter.

### Decisions (user, 2026-11-24)

- **Where:** a toolbar button **"Scarica tutti gli avversari…"** in Avversari (and the same item in the File menu).
- **Tuttocampo:** read live from each team's **Classifica** widget (`https://www.tuttocampo.it/WidgetV2/Classifica/<id>`, the same id as Risultati). It lists every team of the league, even teams we have not met yet, and it is filled even when Risultati says "Risultati non ancora disponibili." (spike, widget 6).
- **CSI:** **no new page read.** When a CSI page is read for a match import (T4.8, "Importa questa pagina"), the app also keeps the list of every team on that page. "Scarica tutti gli avversari…" uses the last stored list of each CSI team. A team with a CSI page but no stored list yet is named in the report: "CSI: nessuna lettura per <squadra>, usa prima Importa da CSI…".
- **Review before saving:** a sheet lists what was found; nothing is written until the user presses "Salva".
- **Existing opponents:** never renamed automatically. They get a downloaded logo **only when they have none**. A logo added by hand is never replaced.
- **Possible duplicates:** the app **asks** for each pair: keep name A, keep name B, or keep them separate. Merging makes one opponent and stores the other spelling as an alias.

### What is read

| Source | Page | Team rows | Name | Logo |
|---|---|---|---|---|
| Tuttocampo | Classifica widget, one request per active team with a widget id | `table.table_ranking tbody tr` | `td.team > a` | `td.team_logo > img[src]` → ClubId → `Teams/200/<ClubId>.png`, stored as `<ClubId>.png` (T4.2 rule) |
| CSI | The stored team list from the last CSI page read | every team on the girone page (calendar and standings; deduplicated by team id) | `span.nome-squadra` | `static.centrosportivoitaliano.it/modulistica/logo/<id>_<timestamp>.jpg`, stored as `csi-<id>.png` (T4.8 rule); the CSI shield placeholder = no logo |

- Our own row is left out: the name equals `ClubSettings.clubShortName` (same comparison as the match import). In tuttocampo it is also the row with class `selected`.
- The fixture `Tests/Fixtures/tuttocampo/classifica-normal.html` (16 rows) and `Tests/Fixtures/csi/girone-sample.html` already cover both shapes. No spike is needed; the contract step reads them.
- Requests: one per tuttocampo team (at least 1 s apart, the T4.2 client and allowlist), then the logos actually missing. No CSI request at all. Only when the user presses the button.

### Review sheet

One row per distinct name found (names are compared with `importNameKey`; the same name seen in two leagues is one row listing both teams/leagues):

| State | Meaning | Default |
|---|---|---|
| **Nuovo** | No opponent with this name or alias | ticked: create it, with its logo |
| **Già presente, senza logo** | Matches an existing opponent that has no logo | ticked: download the logo only |
| **Già presente** | Matches an existing opponent that has a logo | nothing to do, shown greyed |
| **Possibile duplicato** | Looks like another row or an existing opponent (rule below) | **a choice is required**: "Usa «A»" / "Usa «B»" / "Tieni separati". "Salva" stays disabled until every pair has a choice. |

- **Duplicate rule** (pure function in the contract, tested): two names are a possible pair when they differ but are equal after `importNameKey` **and** after removing one trailing age-group token: a year from 2000 to 2030 ("US Standard 2016"), `U<n>`/`Under <n>`, or a squad letter ("B"). Pairs are checked among the rows found and against existing opponents (name and aliases).
- **Merging into an existing opponent:** if the user picks the existing name, the found name becomes an alias. If the user picks the found name, the existing opponent is renamed and the old name becomes an alias. Its matches, logo and id do not change.
- **Merging two new rows:** one opponent with the chosen name, the other as alias, the first logo found (tuttocampo before CSI).
- Each row shows where it was seen ("Tuttocampo · <squadra>", "CSI · <squadra>, letto il <data>") and a logo thumbnail when the source has one.
- After "Salva": create/rename/alias in one database transaction, then download logos for the ticked rows, then a report (created, logos stored, logos failed or not available, teams that could not be read). One failing team or logo never stops the others.

### Contract changes needed (`foundation-architect`)

- `SourceTeam`: source (tuttocampo / CSI), our team it was seen with, name as written, logo reference (tuttocampo ClubId + fallback URL, or CSI logo id + URL; `nil` for none or the placeholder).
- `FixtureSource.fetchLeagueTeams(for team: Team, settings: ClubSettings) async throws -> [SourceTeam]`: reads the Classifica widget; the same errors as `fetchFixtures`, plus a structure-changed health problem. Default implementation on `UnavailableFixtureSource`.
- `PageFixtureParser` (CSI) gains `teams(html:pageURL:settings:) -> [SourceTeam]`, or `parse` returns the teams alongside the fixtures (architect's choice).
- **Stored CSI team lists:** `SourceTeamListRepository { save(teamID:source:teams:readAt:), latest(teamID:source:) }`, so the list survives app restarts. Table `source_team_lists` (team id, source, read at, teams as JSON). Deleting a team deletes its lists. Fake in `SSCoreFakes`.
- `OpponentCandidate` with the four states above, `make(found:existing:)` and `possibleDuplicatePairs(...)`, pure and in SSCore.
- `OpponentMergeChoice` (keep A / keep B / separate), and a repository method that applies the ticked candidates and choices in one transaction (create, rename + alias, add alias).
- `ImportIssue` cases: "Tuttocampo: impossibile leggere la classifica di <squadra>", "CSI: nessuna lettura per <squadra>", reusing the existing logo cases.
- Logo download reuses `FixtureSource.downloadLogos` (tuttocampo) and the T4.8c CSI logo path.
- Task sheet: `docs/plan/tasks/wave-4-t4.9.md` (Wave 1 format: owned paths, acceptance criteria, tests). No `Package.swift` change expected.

### Steps

**Step 0 — plan edit** (this section, docs only).

**Step 1 — contract step** (`foundation-architect`), sequential.

**Step 2 — three tasks in parallel, after Step 1 merges.**

| Task | Agent | Owns | Work |
|---|---|---|---|
| T4.9a sources | `render-engineer` | `Sources/SSImport/` (Classifica parser, `fetchLeagueTeams`; CSI team-list extraction), `Tests/SSImportTests/` | Classifica parser on `classifica-normal.html` (16 rows → 15 teams without ours; names; ClubIds); variants: no table, a row without a logo, our row missing. CSI team list from `girone-sample.html`: dedupe by team id, placeholder shield → no logo, ours left out. `URLProtocol` stub for the fetch; **no live network in tests**. |
| T4.9b data | `core-dev` | `Sources/SSData/`, `Tests/SSDataTests/` | Migration `source_team_lists`; repository; cascade on team delete; the transaction that applies candidates and merge choices (create, rename + alias, alias); tests, including rollback when one write fails. |
| T4.9c UI | `ui-dev` | `Sources/SSApp/Features/Opponents/` (button, review sheet, merge choice, report), the CSI save hook in `Sources/SSApp/Features/Import/` (store the team list after "Importa questa pagina"), Strings | The toolbar button and File menu item. Progress while tuttocampo teams are read. The review sheet with states, ticks, a duplicate choice per pair ("Salva" disabled until every pair is resolved), source and date labels, thumbnails. The report. Italian strings. Built against fakes. |

**Step 3 — wiring** (`core-dev`). Real sources and repository in `Sources/SergnaneseSocial/Composition.swift`. Integration test: stubbed Classifica + a stored CSI list → candidates → choices → database → logos in the temp `SS_DATA_DIR`.

**Step 4 — gate and release.** `qa-reviewer`: acceptance criteria, Mac design (sheet, toolbar, Light/Dark), one live run with the user (tuttocampo read + a stored CSI list). `chore-runner`: USER-GUIDE subsection "Scaricare tutti gli avversari". `release-engineer`: in the same release as T4.2 and T4.8 if not shipped yet.

### Model and effort per step

The network client, the allowlist, the logo download and the CSI page read already exist and were reviewed in T4.2/T4.8. T4.9 adds one pure parser, one table and one sheet. So only the contract step stays on opus.

| Step | Agent | Agent default | Dispatch with | Why |
|---|---|---|---|---|
| 0 plan edit | main session | — | sonnet, low | This section is the content. |
| 1 contract + sheet | `foundation-architect` | opus, high | opus, high | Frozen contracts; the merge transaction and the duplicate rule are where data can be damaged. |
| 2 T4.9a sources | `render-engineer` | opus, high | sonnet, medium | A pure parser against existing fixtures and one method on an existing client. |
| 2 T4.9b data | `core-dev` | sonnet, medium | sonnet, medium | Migration + a multi-step transaction with rollback tests. |
| 2 T4.9c UI | `ui-dev` | sonnet, medium | sonnet, medium | A staging-style sheet like the T4.2 one; `high` only on retry. |
| 3 wiring | `core-dev` | sonnet, medium | sonnet, medium | Composition + one integration test. |
| gate (each task) | `qa-reviewer` | opus, high | sonnet, medium | Well-defined acceptance criteria. |
| gate (final, live run) | `qa-reviewer` | opus, high | sonnet, high | Reuses reviewed network code; the new risk is merging data, covered by tests. Escalate to opus if the review finds data problems. |
| 4 USER-GUIDE | `chore-runner` | haiku | haiku | Prose only. |
| 4 release | `release-engineer` | sonnet, medium | sonnet, low | Existing scripts. |

Escalation is unchanged: retry once on the same model with the reviewer's findings, then one model up.

### Rules

- Tuttocampo requests only when the user presses the button; no CSI request ever (only lists stored from pages the user opened).
- Nothing is written before "Salva"; every write is in one transaction.
- No opponent is deleted. Merging only adds aliases or renames, and only after the user's choice.
- Logos already present are never replaced; our own club is never added as an opponent.
- Dev data folder only; no real names, logos or HTML committed.

---

## T4.10 — Opponent matching: pre-filled links and proposals

**Goal (user, 2026-11-24):** when a PDF is imported, its opponents are assumed to be stored already (from tuttocampo or CSI). The review must arrive with every opponent already matched where possible, so the user only corrects what is wrong. The same review serves tuttocampo, CSI and PDF, so all three get the improvement.

### What was checked on 2026-11-24 (real PDF, Dev data, current `main`)

| Observation | Cause |
|---|---|
| "Cremonese is not matched." | With the current code and the current Dev data it **is** matched: the G2 row (SERGNANESE–CREMONESE) comes out `new`, linked to the stored "Cremonese" (checked with a throwaway test on the real PDF). The match is exact-only (`opponentsMatching`: equal after `importNameKey`), so it fails for any other spelling: "U.S. Cremonese" works only because `US` is a legal prefix; "Cremonese S.p.A.", "Cremonese Femminile", "Cremonese 1903" do not. The row also does not show whether its opponent was matched or is still the PDF name (only the capitalisation differs). |
| "The opponents offered are not the ones stored before." | The 8 stored opponents (Albinoleffe, Atalanta, Cremonese, Monterosso, Orceana, Orobica, Pro Palazzolo, Sporting Valentino Mazzola) came from the tuttocampo Classifica of widget `e6c85afd…`, mapped to "U13 Regionale Femminile" (their ClubIds 1252666–1252668 are in the same range as ours there, 1252673). The federation PDF is a **different girone** (Alcione, Fiamma Monza 1970, Pavia Calcio 1911, Real Meda CF Sq.B, San Bernardo Calcio, Women Rivanazzanese, Riozzese, Cremonese). Only Cremonese is in both. So 7 of 8 PDF opponents are genuinely not stored. The link picker does list every stored opponent, but unranked and only on rows marked "non trovato". |

**User action:** check on sergnanese.com which tuttocampo widget shows the U13 femminile girone of the federation calendar. Until its opponents are stored, the first PDF import creates them ("Crea"), with the page-2 full name as alias.

### Matching levels

Computed in SSCore for every fixture (name + `opponentAliases`) against every stored opponent (name, short name, aliases).

1. **Exact → linked.** Equal under the new `opponentMatchKey`: today's `importNameKey` (legal prefixes out, case, accents, spaces, apostrophes) **plus** punctuation treated as spaces and **legal suffixes removed** at the end: `spa`, `srl`, `arl`, `a rl`, `scarl`, `ssd`, `asd`, `ssd arl`, `ssd a rl`, `ssdrl`, in any dotting (`S.p.A.`, `A R.L.`, `S.S.D. a r.l.`). Linked as today, no tag.
2. **Close → proposed and pre-filled.** Significant tokens are compared: the key's words minus generic ones (`calcio`, `football`, `club`, `fc`, `cf`, `ac`, `as`, `us`, `sc`, `pol`, `polisportiva`, `women`, `femminile`, `femm`). Abbreviations are expanded first (`s` → `san`, `sta` → `santa`, `sto` → `santo`). Two tokens are equal when they are identical, or when both have 6+ letters and their edit distance is 1. A stored opponent is a **proposal** when every significant token of the shorter side is in the longer side (containment; when the shorter side has a single token, it counts only with 7+ letters: "Alcione" yes, "Meda" no — user decision 2026-11-24 after T4.10a), or the Dice score of the two token sets is ≥ 0.8. In both cases:
   - **years** (4 digits) present on both sides must be equal, else no proposal;
   - a **squad marker** (`sq b`, `sq. b`, a single trailing letter, `2`) present on one side only, or different, allows a proposal but never an exact link.
   The row is pre-filled only when exactly **one** opponent is proposed. Two or more → no pre-fill, `opponentAmbiguous`, all of them on top of the picker.
3. **None → to link or create.** As today ("Crea" / "Collega a esistente…"), with the picker ranked.

### Expected results (these pairs become the core test table)

| Fixture name (aliases) | Stored opponent | Result |
|---|---|---|
| CREMONESE (CREMONESE S.P.A.) | Cremonese | exact (works today) |
| CREMONESE (CREMONESE S.P.A.) | U.S. Cremonese S.p.A. | exact |
| RIOZZESE (RIOZZESE A R.L.) | Riozzese | exact |
| ALCIONE (ALCIONE MILANO SSD A RL) | Alcione Milano | exact through the alias |
| ALCIONE | Alcione Milano | proposed (containment) |
| S. BERNARDO CALCIO (SAN BERNARDO CALCIO) | San Bernardo | proposed |
| WOMEN RIVANAZZANESE | Rivanazzanese | proposed |
| PAVIA CALCIO 1911 | Pavia 1911 | proposed |
| PAVIA CALCIO 1911 | Pavia 1950 | none (years differ) |
| REAL MEDA CF Sq.B | Real Meda Cf | proposed, never exact (squad marker) |
| FIAMMA MONZA 1970 | Atalanta Bc | none |
| ALCIONE | Alcione Milano, Alcione Bergamo | none pre-filled: ambiguous, both proposed first in the picker |
| CREMONESE | Cremonese Women, Cremonese | exact on "Cremonese" wins; the proposal is not used |

### Review sheet (all sources)

- **Linked (exact):** as today. The row shows the stored opponent's name.
- **Proposed:** the row is pre-filled. It has a draft, its state is new / changed / unchanged as for a linked row, and it is ticked by the usual rules. It shows a secondary tag "Proposto" with the line "Abbinato a «Alcione Milano» (proposta automatica)" and two buttons: **Conferma** (removes the tag) and **Cambia…**. Importing without pressing Conferma accepts the proposal.
- On "Importa", a proposed or exact link is saved like a manual link: the fixture's name and aliases are added to the opponent's aliases when they do not match already (`Opponent.draftAddingImportNames(of:)`, as "Collega a esistente…" does today). The next import of the same PDF is then exact everywhere.
- **Every row with an opponent** has "Cambia avversario…" (row button and context menu), so a wrong automatic match can be fixed. Today only "non trovato" rows can be linked.
- **Picker:** with an empty search it lists **all** stored opponents, proposals first (best score first) under "Proposti", then the rest alphabetically under "Tutti gli avversari". At the bottom: "Crea nuovo «<fixture name>»".
- **Header line:** "N abbinati, N proposti, N da collegare".
- VoiceOver reads the tag ("abbinamento proposto"); the tag uses a semantic colour and a symbol, not colour alone.

### Contract changes (`foundation-architect`)

- `opponentMatchKey(_:)` (level 1). `opponentsMatching(name:in:)` uses it. `opponentDuplicateKey` (T4.9) builds on it, so T4.9's duplicate pairs improve too. All T4.2/T4.8/T4.9 tests must still pass. Any test whose expectation changes is listed in the report with the reason.
- `public struct OpponentProposal: Sendable, Equatable { opponent: Opponent; score: Double; kind: .containment | .similar }`.
- `public func rankOpponents(name: String, aliases: [String], in: [Opponent]) -> [OpponentProposal]`: proposals only, best first, ties by name.
- `ImportCandidate`:
  - `opponentMatch: OpponentMatch` (`.exact`, `.proposed`, `.linked` by the user, `.none`, `.ambiguous`);
  - `proposals: [OpponentProposal]` (at most 5, for the picker);
  - `make(…)` fills `opponent` and the draft for a single proposal. No new `ReviewReason`: a proposal is not "needs review".
- `SSCoreFakes`: proposals in the fake data (one exact, one proposed, one ambiguous, one none).

### Steps

**Step 0 — plan edit** (this section, docs only).

**Step 1 — T4.10a contract + matcher** (`foundation-architect`), sequential. Owns `Sources/SSCore/`, `Sources/SSCoreFakes/`, `Tests/SSCoreTests/`. The table above as Swift Testing arguments, plus the legal-suffix list, edit distance, years and squad markers. Writes the short `wave-4-t4.10.md` sheet.

**Step 2 — T4.10b review UI** (`ui-dev`), after Step 1 merges. Owns `Sources/SSApp/Features/Import/` (`ImportModel`, `ImportSheet`, `ImportStrings`), `Tests/SSAppTests/Import/`, and the PDF integration test `Tests/IntegrationTests/PDFImportTests.swift` (one extra case: stored opponents spelled differently → exact + proposed + none, then a re-import is all exact). Tag, Conferma / Cambia…, "Cambia avversario…" on every linked row, ranked picker with sections, header counts, Italian strings.

No wiring step: no new service.

**Step 3 — gate.** `qa-reviewer`: acceptance, Light/Dark, VoiceOver labels. One live run with the user: the real PDF on the Dev data, after storing the girone's opponents with different spellings. `chore-runner`: one paragraph in the USER-GUIDE import section ("Avversari abbinati e proposti").

### Model and effort per step

| Step | Agent | Agent default | Dispatch with | Why |
|---|---|---|---|---|
| 0 plan edit | main session | — | done | This section. |
| 1 T4.10a contract + matcher | `foundation-architect` | opus, high | **opus, medium** | Frozen code used by four import paths, and a wrong match writes wrong data. But the rules and the test table are fixed here, so `medium` is enough. |
| 2 T4.10b UI | `ui-dev` | sonnet, medium | **sonnet, medium** | Changes to an existing sheet and picker against fakes. |
| gate | `qa-reviewer` | opus, high | **sonnet, medium** | Fixed acceptance table; no network, no new storage. |
| 3 USER-GUIDE | `chore-runner` | haiku | **haiku** | Prose only. |

Escalation is unchanged: retry once on the same model with the reviewer's findings, then one model up.

### Rules

- Nothing is written before "Importa". Proposals change nothing in the database until then.
- An automatic link (exact or proposed) never renames an opponent. It only adds aliases on import.
- A proposal never replaces an exact match, and two proposals never pre-fill.
- Dev data folder only. Test names are invented, apart from the club names already in this sheet (public league data).

---

## T4.11 — Tuttocampo season import: every matchday of each team

**Goal (user, 2026-11-24):** import all the season's matches of each team at once, not only this weekend's. CSI (T4.8) and PDF (T4.3) already bring a whole calendar per page or file. Tuttocampo (T4.2) reads only the widget's default matchday, so this task covers tuttocampo.

### Facts (T4.2 spike, `docs/plan/notes/t4.2-spike.md`)

- Any matchday can be read: `https://www.tuttocampo.it/WidgetV2/Risultati/<id>/<N>?y=2026-27`. The page's own matchday strip links to these; `y` is optional and defaults to the current season.
- The page head has `var currentMatchDay='11';var matchesNumber='30';`. The spike read `matchesNumber` as "matches in the season". But the widget with `30` is a **16-team** league, and (16 − 1) × 2 = 30, so it is most likely the **number of matchdays**. Step 1 confirms this.
- The empty state ("Risultati non ancora disponibili.") has `matchesNumber=''`, no table and no strip.
- A request costs ~1 s of spacing (`TuttocampoHTTPClient`'s `RequestSpacer`, `minimumInterval` 1 s), with no retries.

### Decisions in this plan (change them before Step 2 if you disagree)

| # | Decision |
|---|---|
| 1 | The import scope is chosen in a small start panel of the existing "Importa da Tuttocampo…" command. **Questo weekend** is today's behaviour and the default. **Da oggi a fine stagione** reads from the current matchday to the last; use it regularly, it needs fewer requests. **Tutta la stagione** reads from matchday 1 to the last, results included; use it at the start of a phase or to fill the archive. |
| 2 | Team choice: a checklist of active teams with a widget ID, all ticked by default. One team or all of them in one run. |
| 3 | Before starting, the panel shows an estimate: "circa N richieste, circa M minuti". N = the remaining (or all) matchdays summed over the ticked teams, taken from the last import when known, else 30 per team. |
| 4 | Requests run **one at a time**, through the existing spacing (≥ 1 s apart), only after the user presses Avvia. No polling, no background or scheduled run, no retries. Hard caps: 60 matchdays per team, 400 page requests per run. |
| 5 | A matchday page without our row is a **bye** ("Giornata 8: riposo"), shown as information, not an error. |
| 6 | A failed matchday is listed in the report and the run goes on. After 3 failures in a row for one team, that team stops ("lettura interrotta dopo la giornata N"). Cancelling keeps every row already read. |
| 7 | The usual review sheet. Default ticks: every new or changed row dated today or later; with **Tutta la stagione**, past new or changed rows too (the user asked for them). Unchanged and locked rows are never ticked; locked matches are never overwritten (existing rule). |
| 8 | Opponents are matched as in every import (T4.10: exact, proposed, none). Logos are deduplicated by ClubId over the whole run, and only missing ones are downloaded (existing logo rule). |
| 9 | Season length: `matchesNumber` when Step 1 confirms it. Otherwise, after the current matchday, read on until the first page with no results table, or the page whose matchday strip has no higher entry, within the 60-matchday cap. |

### Review sheet with many rows

A season run gives up to ~30 rows per team (≈ 240 for 8 teams). Grouping by weekend stays. Added:
- a **team filter** (pop-up: "Tutte le squadre" or one team);
- **past weekends collapsed** by default when the scope includes them;
- a header line: "N partite in N giornate, N squadre; N riposi; N giornate non lette";
- "Seleziona tutte / nessuna" for the visible rows.

### Step 1 — spike (no app code; notes and sanitised fixtures only)

On two widgets (the 16-team adult one and one youth widget), about 10 requests in total, spaced. Record:
- `matchesNumber` against the number of teams in the Classifica: is it the number of matchdays?
- matchday 1, the last matchday, and last + 1: what does a page beyond the end return (empty state, error, the last matchday again)?
- a matchday where Sergnanese rests (from the strip, if the league has an odd number of teams);
- future matchdays: are dates shown, are times shown or blank ("da definire")?
- whether `?y=` must be sent for the season after the turn of the year.

Output: a "Season" section in `docs/plan/notes/t4.2-spike.md` and sanitised fixtures under `Tests/Fixtures/tuttocampo/`: `risultati-matchday-1.html`, `risultati-matchday-last.html`, `risultati-beyond-end.html`, `risultati-bye.html`, `risultati-future-no-time.html` (invented names, placeholder logos).

### Contract changes (`foundation-architect`)

- `public enum SeasonScope: Sendable { case fromCurrentMatchday, wholeSeason }`.
- `public struct SeasonProgress: Sendable, Equatable { matchday: Int; lastMatchday: Int? }`.
- `public struct SeasonFetch: Sendable, Equatable`, with:
  - `fixtures` (ours, in date order; one per date, the later-read page wins);
  - `byes: [Int]`;
  - `lastMatchday: Int?`;
  - `failedMatchdays: [MatchdayFailure]` (matchday + `FixtureFetchError`);
  - `problems: [MatchdayProblem]` (matchday + `FixtureHealthProblem`, except `noFixturesOfOurs`, which is a bye);
  - `stoppedAfter: Int?` (the three-failures rule).
- `FixtureSource.fetchSeason(for:settings:scope:onProgress:) async throws -> SeasonFetch`:
  - first reads the default matchday (gives the current matchday and the season length), then the others in ascending order;
  - throws `FixtureFetchError` only when that first page cannot be read;
  - on cancellation it stops before the next request and **returns** what was read, with `stoppedAfter` set; it never throws `CancellationError`; callers check `Task.isCancelled`;
  - `.notYetAvailable` on the first page → an empty `SeasonFetch` and `lastMatchday == nil`.
- `ImportIssue`: `.seasonBye(team:, matchday:)` (information), `.seasonMatchdayFailed(team:, matchday:, reason:)`, `.seasonStopped(team:, afterMatchday:)`; their `CoreStrings` messages.
- `SSCoreFakes`: `FakeFixtureSource.fetchSeason` with a season of 10 matchdays: one bye, one failing matchday, one locked existing match, progress callbacks.

### Step 2 — contract step (`foundation-architect`), sequential

Owns `Sources/SSCore/`, `Sources/SSCoreFakes/`, `Tests/SSCoreTests/`. Writes `wave-4-t4.11.md`.

### Step 3 — two tasks in parallel, after Step 2 merges

| Task | Agent | Owns | Work |
|---|---|---|---|
| T4.11a season source | `render-engineer` | `Sources/SSImport/TuttocampoParser.swift`, `TuttocampoWidgetSource.swift`, `TuttocampoHTTPClient.swift` (matchday URL only), `Tests/SSImportTests/Tuttocampo*`, the new fixtures | Matchday URL builder (`/<id>/<N>`; allowlist unchanged). The parser also returns `currentMatchDay` and `matchesNumber`. `fetchSeason` per decisions 4, 5, 6 and 9: sequential, through the spacer, caps, bye detection, three-in-a-row stop, cancellation between requests, progress per page. Tests: a `URLProtocol` stub serving a 10-matchday season, scope from current vs whole (exact request lists), bye, a failing matchday, three failures, beyond-end, cancellation after page 4, caps. **No live network in tests.** |
| T4.11b UI | `ui-dev` | `Sources/SSApp/Features/Import/` (start panel as a new `TuttocampoScopeSheet.swift`, season path in `ImportModel`, sheet additions, `ImportStrings`), `Tests/SSAppTests/Import/` | The start panel: scope, team checklist, estimate, Avvia/Annulla. Progress "Squadra 2 di 8 · Giornata 14 di 30" with a determinate bar and Annulla. The season fetch loop over teams; issues for byes, failed matchdays and stops. The ticks of decision 7. Team filter, collapsed past weekends, header line, select all/none. Italian strings. Built against the fake source. |

**Step 4 — wiring** (`core-dev`). `LoggingFixtureSource` in `Sources/SergnaneseSocial/Composition.swift` forwards and logs `fetchSeason` (one line per matchday). Integration test: the stubbed 10-matchday season → staging → database → logos in the temp `SS_DATA_DIR`; a second run of "Da oggi a fine stagione" makes no changes (all unchanged).

**Step 5 — gate and release.** `qa-reviewer` checks:
- the acceptance criteria;
- Light/Dark, keyboard and VoiceOver on the start panel and the progress;
- one live run with the user on one team: request count = matchdays read + 1, spacing ≥ 1 s in the log, no requests after Annulla.

`chore-runner`: USER-GUIDE subsection "Importare la stagione intera". `release-engineer`: next release.

### Model and effort per step

| Step | Agent | Agent default | Dispatch with | Why |
|---|---|---|---|---|
| 0 plan edit | main session | — | done | This section. |
| 1 spike | `render-engineer` | opus, high | **sonnet, low** | ~10 requests against a fixed checklist, plus sanitising 5 files. |
| 2 contract + sheet | `foundation-architect` | opus, high | **opus, medium** | Frozen protocol shared by fakes, source and UI. The shapes are fixed here, so `medium` is enough. |
| 3 T4.11a season source | `render-engineer` | opus, high | **sonnet, medium** | A sequential loop over the existing client: cancellation, partial failures, caps. Patterns already in T4.2. |
| 3 T4.11b UI | `ui-dev` | sonnet, medium | **sonnet, medium** | A small panel, a progress view and a filter on the existing sheet. |
| 4 wiring | `core-dev` | sonnet, medium | **sonnet, low** | One forwarding method + one integration test. |
| gate (each task) | `qa-reviewer` | opus, high | **sonnet, medium** | Fixed acceptance; the network code was reviewed in T4.2. |
| gate (final, live run) | `qa-reviewer` | opus, high | **sonnet, medium** | The live check is counting requests and spacing in the log. |
| 5 USER-GUIDE | `chore-runner` | haiku | **haiku** | Prose only. |
| 5 release | `release-engineer` | sonnet, medium | **sonnet, low** | Existing scripts. |

Escalation is unchanged: retry once on the same model with the reviewer's findings, then one model up.

### Order with the other tasks

T4.10 is merged (2026-11-24), so T4.11 builds on its review sheet and matcher; nothing to combine. Order: Step 1 spike (can start now) → Step 2 contract → T4.11a ∥ T4.11b → Step 4 wiring → Step 5 gates.

### Rules

- Network only after Avvia, one request at a time, ≥ 1 s apart, within the caps; nothing in the background.
- The tuttocampo terms-of-use check (T4.2's blocking input) must cover reading every matchday (~30 requests per team per run). If it does not, this task stops; T4.2's weekend import stays.
- Nothing is written before "Importa"; locked matches are never overwritten; existing logos are never replaced automatically.
- Dev data folder only; fixtures sanitised; no real HTML, names or logos committed.
