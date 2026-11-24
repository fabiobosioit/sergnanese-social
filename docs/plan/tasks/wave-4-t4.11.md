# T4.11 — Tuttocampo season import: task sheet (Step 3)

The full sheet for the work after the T4.11 contract step. The decisions (scope, team checklist, estimate, one request
at a time, byes, three-failures stop, ticks, opponents, season length) are in `wave-4-later.md` § T4.11 and the spike
findings in `docs/plan/notes/t4.2-spike.md` § Season. Read both before starting; this sheet does not repeat them
except where the spike or the contract refined them.

**Blocked on:** the T4.11 contract step merged; the tuttocampo terms-of-use check covering ~30 requests per team per
run (T4.2's blocking input). No live network in any test.

**Contract (Step 2, merged first).** Code against these; do not edit `Sources/SSCore/` or `Sources/SSCoreFakes/`. If
one is wrong, stop and report. The comment at the top of `Sources/SSCore/Season.swift` is the recipe.

| Contract | Where | Used by |
|---|---|---|
| `SeasonScope` (`.fromCurrentMatchday` "Da oggi a fine stagione", `.wholeSeason` "Tutta la stagione"; `String` raw values, `Codable`). "Questo weekend" is not a scope: it stays `fetchFixtures` | `Season.swift` | a, b |
| `SeasonLimits`: `maxMatchdaysPerTeam` 60, `maxPagesPerRun` 400, `failuresInARowToStop` 3, `secondsPerPage` 1.5, `assumedMatchdays` 30 | `Season.swift` | a, b |
| `SeasonPage` (`matchday` = head `currentMatchDay`, `matchdayCount` = head `matchesNumber`, `outcome: FixtureFetch`): what the source's parser gives per page | `Season.swift` | a |
| `readSeason(scope:readPage:onProgress:) async throws -> SeasonFetch`: **the season loop**. Order (default page, then ascending, current not re-read), bye, problem and failure rules, three-in-a-row stop, the end probe when `matchesNumber` is missing, the 60 cap, cancellation (never throws `CancellationError`), progress after every page. The real source calls it; do not reimplement it | `Season.swift` | a |
| `SeasonLength` (`currentMatchday`, `lastMatchday`), `otherMatchdays(_:)`, `pages(_:)` = exact request count when nothing fails | `Season.swift` | a, b |
| `SeasonProgress` (`matchday`, `lastMatchday?`, `pagesRead`, `pagesTotal?`) | `Season.swift` | b |
| `SeasonFetch` (`fixtures` by date, one per date; `byes`; `currentMatchday?`; `lastMatchday?`; `failedMatchdays: [MatchdayFailure]`; `problems: [MatchdayProblem]` (`matchday` `nil` = default page without a number); `stoppedAfter?`; `notYetAvailable`; `pagesRead`; `length: SeasonLength?`) | `Season.swift` | a, b |
| `SeasonEstimate(scope:teams: [SeasonLength?])` → `requests`, `minutes`, `message` ("circa 40 richieste, circa 1 minuto") | `Season.swift` | b |
| `FixtureSource.fetchSeason(for:settings:scope:onProgress:) async throws -> SeasonFetch`; `onProgress: @Sendable (SeasonProgress) async -> Void`. Default implementation throws `FixtureFetchError.unavailable` | `Import.swift` | a, b, Step 4 |
| `ImportIssue.seasonBye(team:matchday:)` (information), `.seasonMatchdayFailed(team:matchday:reason:)`, `.seasonMatchdayChanged(team:matchday:)`, `.seasonStopped(team:afterMatchday:)`, and `ImportIssue.seasonNotices(team:fetch:clubShortName:)` (the report lines of one run, in order) | `Import.swift`, `CoreStrings.swift` | b |
| Fakes: `FakeFixtureSource.fetchSeason` (runs `readSeason` over canned pages, `delay` per page); `FakeFixtureSource.Season`; `seasons:` in `init`; `scenarioSeason(referenceSaturday:)` = Primi Calci (widget 9), 10 matchdays, current 5 (the locked match), timeout on 3, bye on 7, one unknown opponent, one match without time (table in its doc comment). Every other scenario widget answers a one-matchday season made of its weekend answer | `SSCoreFakes` | b |

**Package.swift:** no change. No new target, no new dependency.

**Already changed in Step 2:** nothing outside `SSCore`, `SSCoreFakes` and `Tests/SSCoreTests`; no existing test
expectation changed. Until Step 4, `LoggingFixtureSource` (`Sources/SergnaneseSocial/Composition.swift`) does not
forward `fetchSeason`, so the real app answers "non disponibile" for a season run: expected.

**Spike findings that refine the plan** (`t4.2-spike.md` § Season):

1. `matchesNumber` (page head) **is the number of matchdays**, not of matches or teams; it cannot be derived from the
   team count (16 teams → 30, 11 teams → 11). Season length = `matchesNumber` (decision 9 holds).
2. A matchday above `matchesNumber` returns **HTTP 200 with the empty state** ("Risultati non ancora disponibili.",
   `currentMatchDay` echoes the requested number, `matchesNumber` kept). Stop rule: matchday > `matchesNumber`, or
   (only when `matchesNumber` is missing) the first page with no results table. `readSeason` implements both.
3. A **bye** in an odd league is an extra last row `<tr class="repose"><td colspan="4"><span>Riposa:</span> … NAME</td></tr>`.
   Bye detection = no match row of ours on a page with a results table; the `repose` row naming us may confirm it but
   is not required. The `repose` row is **never** a match row.
4. **Future matchdays show dates and times**; far-future times look like a provisional default (all 14:30). No blank
   time was observed live; a missing time must still be tolerated (`time == nil`, the row kept).
5. **Always send `?y=<season>`** on matchday URLs (`/WidgetV2/Risultati/<id>/<n>?y=2026-27`), built from
   `ClubSettings.season` (`2026/27` → `2026-27`). The default page keeps today's URL.
6. Dates have no year: September–December = first year of the season, January–July = second (existing rule).

| Task | Agent | Model | Owns |
|---|---|---|---|
| T4.11a Season source | `render-engineer` | sonnet · effort medium | `Sources/SSImport/TuttocampoParser.swift`, `TuttocampoWidgetSource.swift`, `TuttocampoHTTPClient.swift` (matchday URL only), `Tests/SSImportTests/Tuttocampo*`, `Tests/SSImportTests/Support/` (stub additions), `Tests/Fixtures/tuttocampo/` (new files only) |
| T4.11b Season UI | `ui-dev` | sonnet · effort medium | `Sources/SSApp/Features/Import/` (new `TuttocampoScopeSheet.swift`, `ImportModel.swift`, `ImportSheet.swift`, `ImportStrings.swift`), `Sources/SSApp/Features/Matches/MatchesView.swift` (only if the command's entry point moves), `Tests/SSAppTests/Import/` (not `CSIBrowser/`) |

T4.11a and T4.11b run in parallel and share nothing but the contract.

**Gate:** `Scripts/check.sh` green on each branch; `qa-reviewer` (sonnet, medium) per task. After Step 4: one live run
with the user on one team: request count = `SeasonFetch.pagesRead` (the default page counts as one; the current
matchday is not requested twice), spacing ≥ 1 s in the log, no request after Annulla.

---

## T4.11a — Season source

| | |
|---|---|
| **Agent / model** | `render-engineer` · sonnet · effort medium |
| **Depends on** | T4.11 contract step |
| **Size** | S |

**Features**

1. **Head values.** The parser also reads `var currentMatchDay='N'` and `var matchesNumber='M'` from the page's
   scripts (an empty or non-numeric value → `nil`) and returns a `SeasonPage`, e.g. a new internal
   `parseResultsPage(html:pageURL:clubShortName:season:) -> SeasonPage` whose `outcome` is exactly what
   `parseResults` returns today (keep `parseResults` for `fetchFixtures`, or make it call the new one).
2. **Bye.** On a page with a results table, match rows but none of ours → `.sourceProblem(.noFixturesOfOurs)` (as
   today). `tr.repose` is skipped as a match row (it must not make a row fail and turn the page into
   `.structureChanged`). Do not require the `repose` row.
3. **Missing time.** An empty `.match-time` text gives `time == nil` with the row kept and its status read as
   usual.
4. **Beyond the end.** The empty state with a head is `SeasonPage(matchday: n, matchdayCount: M, outcome:
   .notYetAvailable)`; `readSeason` never requests it when `M` is known.
5. **Matchday URL.** `https://www.tuttocampo.it/WidgetV2/Risultati/<id>/<n>?y=<yyyy-yy>`, `n` in
   `1...SeasonLimits.maxMatchdaysPerTeam`, season from `settings.season` (`isValidSeason` format `2026/27` → `2026-27`);
   an invalid season → no `y` (the site defaults to the current season). Host allowlist, https, timeout, size cap,
   `User-Agent` unchanged. The default page keeps today's URL.
6. **`fetchSeason`** in `TuttocampoWidgetSource`: `.missingWidgetID` first; then `readSeason(scope:readPage:onProgress:)`
   with `readPage(nil)` = the default page and `readPage(n)` = the matchday URL, both through the existing client
   (so the `RequestSpacer` spaces every request ≥ 1 s), parsed with the team's `clubShortName` and `season`.
   `readPage` throws only `FixtureFetchError` or `CancellationError` (map `URLError.cancelled` and a cancelled spacer
   wait to `CancellationError`). No retries, no concurrency, no other loop.

**Acceptance criteria**

- With a `URLProtocol` stub serving a 10-matchday season (built from the new fixtures with `currentMatchDay` and
  `matchesNumber` adjusted), the request list is exact: `.fromCurrentMatchday` from current 4 → default page, then
  `/5?y=2026-27` … `/10?y=2026-27` (7 requests); `.wholeSeason` → default page, `/1` … `/3`, `/5` … `/10`
  (10 requests); `pagesRead` equals the number of stubbed requests.
- `risultati-bye.html` gives a bye for its matchday; `risultati-future-no-time.html` a fixture with `time == nil`
  and status `.scheduled`; `risultati-beyond-end.html` `.notYetAvailable` with `matchday 31`, `matchdayCount 30`;
  `risultati-matchday-1.html` and `-last.html` `matchdayCount 30` and their matchday.
- A stubbed HTTP 500 on one matchday → `failedMatchdays` and the run goes on; three in a row → `stoppedAfter`.
- Cancelling the task while page 4 is in flight: no further request reaches the stub, the result keeps pages 1–3,
  nothing is thrown.
- A default page that fails throws its `FixtureFetchError`; the default empty state gives `notYetAvailable`.
- Every request goes through the spacer (a test with a fake clock or the existing spacer test seam shows ≥ 1 s gaps,
  or a counter shows each request waited its turn).

**Tests (Swift Testing, no live network)**

- Parser: head values on all five new fixtures, missing `matchesNumber`, `matchesNumber=''`; bye page; no-time row;
  `repose` row ignored on a page where we play.
- URL builder: `n` and `y` for `2026/27`, invalid season, `n` out of range rejected.
- Source with the stub: the request lists above, bye, failing matchday, three failures, beyond-end never requested,
  cancellation after page 4, `.missingWidgetID`, progress count = pages.
- The existing `fetchFixtures` tests stay green.

---

## T4.11b — Season UI

| | |
|---|---|
| **Agent / model** | `ui-dev` · sonnet · effort medium |
| **Depends on** | T4.11 contract step |
| **Size** | M |

**Features**

1. **Start panel** (`TuttocampoScopeSheet`), opened by the existing "Importa da Tuttocampo…" command:
   - scope as a radio group: **Questo weekend** (default; today's flow, unchanged), **Da oggi a fine stagione**,
     **Tutta la stagione**, each with its one-line help from decision 1;
   - team checklist: active teams with a widget ID, all ticked; at least one must be ticked;
   - for the two season scopes, the line `SeasonEstimate(scope:teams:).message`, one `SeasonLength?` per ticked team
     from the last season run of that team (kept by the UI, see 6), `nil` otherwise;
   - **Avvia** (default button) / **Annulla** (Esc). No request before Avvia.
2. **Progress** for a season run: "Squadra 2 di 8 · Giornata 14 di 30" (`progress.matchday`, `progress.lastMatchday`;
   "Giornata 14" when the last is unknown), a determinate bar from `pagesRead` / `pagesTotal` (indeterminate while
   `pagesTotal` is `nil`), and **Annulla**. Progress updates arrive through the `@Sendable async` callback: hop to the
   main actor inside it.
3. **Loop**: one team at a time, `fetchSeason` in a child task per team. Per team: `ImportIssue.seasonNotices` for the
   report (drop `.seasonStopped` when the user cancelled), `.fetchFailed` when it throws, candidates with
   `ImportCandidate.make` for every fixture. **Annulla** cancels the current team's task, starts no other team and
   keeps every row already read. **Per-run cap**: count `progress.pagesRead` over the run; when the total reaches
   `SeasonLimits.maxPagesPerRun`, cancel the current team, start no other, and say which teams were not read.
4. **Ticks (decision 7)**: new or changed rows dated today or later; with **Tutta la stagione** also past new or
   changed rows. Unchanged and locked rows never ticked. Locked matches are never written (existing rule).
5. **Review additions**: team filter pop-up ("Tutte le squadre" or one team); past weekends collapsed by default when
   the scope includes them; header line "N partite in N giornate, N squadre; N riposi; N giornate non lette" (riposi =
   byes, non lette = failed + problems with a matchday); "Seleziona tutte / nessuna" for the visible rows. Logos
   deduplicated by ClubId over the whole run, only missing ones downloaded (existing rule).
6. **Season lengths for the estimate**: after each run, keep `fetch.length` per team id (in memory for the session,
   and in `UserDefaults` under a key of your own so the next launch has it). Never in the database (no contract for it).
7. All new text in `ImportStrings` (Italian). Messages from `ImportIssue.message` and `SeasonEstimate.message` are
   used as they are.

**Acceptance criteria**

- Against `AppServices.fake()`: "Tutta la stagione" on Primi Calci only shows 8 rows: 3 past new (ticked), locked
  matchday 5 (not ticked), changed matchday 6, new matchday 8 and 10 (without time), matchday 9 "non trovato"; report:
  "impossibile leggere la giornata 3 …" and "Primi Calci, giornata 7: riposo."; header "8 partite in 8 giornate,
  1 squadre; 1 riposi; 1 giornate non lette" (or the grammatically correct singular you choose in `ImportStrings`).
- "Da oggi a fine stagione" on Primi Calci: 5 rows, the past ones absent; the estimate before the first run reads
  "circa 30 richieste, circa 1 minuto" and, after it, "circa 6 richieste, circa 1 minuto".
- All teams, "Tutta la stagione": Esordienti listed as failed, Giovanissimi U14 "non ancora disponibili", Giovanissimi
  U15 "la sorgente potrebbe essere cambiata", the other teams one row each as in the weekend scenario.
- Annulla during the run keeps the rows read so far and no other team starts.
- "Questo weekend" behaves exactly as before (existing tests unchanged).
- Light and Dark Mode; keyboard: Return = Avvia, Esc = Annulla; VoiceOver reads the scope choices, the estimate and
  the progress line.

**Tests (Swift Testing)**

- `ImportModel` with the fake: season run states and ticks for both scopes, issues order, header counts, team filter,
  select all/none on visible rows, cancellation (use a `FakeFixtureSource` with `delay` and cancel after the
  first progress), per-run cap (a fake with `seasons` long enough and a test seam for the cap, or several teams).
- Estimate: unknown teams → 30 each; after a run → `SeasonLength.pages`.

---

## Step 4 — wiring (`core-dev`, after T4.11a and T4.11b merge)

`LoggingFixtureSource` forwards `fetchSeason` to its base (the protocol default would answer "non disponibile") and
logs one line per page from `onProgress` (team, matchday, pages read) and the outcome (fixtures, byes, failures,
stoppedAfter, pagesRead); never HTML or URLs with ids. Integration test: the stubbed 10-matchday season → staging →
database → logos in the temp `SS_DATA_DIR`; a second "Da oggi a fine stagione" run gives only unchanged and locked rows.
