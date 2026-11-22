# Wave 4 — After v0.1.0

These tasks are independent of each other and can run in parallel in any combination. They are specified more briefly than Waves 0–3 on purpose: each one gets a full task sheet (same format as Wave 1) written by `foundation-architect` just before it starts, using what was learned from real use.

Contract changes needed by a task are done first, by `foundation-architect`, in a short sequential step.

From here on the user has real data on this Mac. Every task keeps working in the Dev data folder; nothing may open the release data folder.

| Task | Agent | Model | Blocked on |
|---|---|---|---|
| T4.1 CSV/Excel import | `core-dev` + `ui-dev` | sonnet | sample file from the user |
| T4.2 Tuttocampo import (matches, names, logos) | `foundation-architect` (contract), `render-engineer`, `core-dev`, `ui-dev` | opus (contract, final gate) + sonnet | terms-of-use check, widget → team mapping |
| T4.3 PDF import | `render-engineer` | opus | sample PDFs |
| T4.4 Shortcuts support | `ui-dev` | sonnet | — |
| T4.5 Results workflow | `ui-dev` | sonnet | — |
| T4.6 Captions | `ui-dev` | sonnet | — |
| T4.7 Developer-ID signing and in-app updates | `release-engineer` | sonnet | paid Apple Developer account |
| T4.8 CSI Live import (matches, names, logos) through an in-app browser | `foundation-architect` (contract), `render-engineer`, `core-dev`, `ui-dev` | opus (contract, final gate) + sonnet | CSI terms-of-use check, a page saved by the user, team → page mapping |

---

## T4.1 — CSV/Excel import with review

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

## T4.3 — PDF import

- Text extraction from federation-style fixture PDFs with PDFKit, table detection, mapping to staging rows.
- Always through the staging review. Rows the parser is unsure about are flagged.
- Model: opus; PDF layouts vary and parsing needs careful heuristics. Reassess after seeing the user's sample files: if they are regular, sonnet is enough.

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
