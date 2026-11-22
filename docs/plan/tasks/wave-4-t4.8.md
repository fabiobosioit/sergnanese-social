# T4.8 — CSI Live import: task sheets (Step 4 and Step 5)

Full sheets for the work after the T4.8 contract step. The background, the method (the user opens the
page in an in-app browser window, the app reads what is on screen), the logo rules and the errors are in
`wave-4-later.md` § T4.8; the facts about the page are in `docs/plan/notes/t4.8-csi-spike.md`. Read both
before starting; this sheet does not repeat them.

**Blocked on:**
- Step 1 (user): the CSI Live terms-of-use check, a girone page saved outside the repo, and which club team
  each CSI page belongs to. No task below starts before the user has confirmed them.
- Step 2 (spike): the **sanitised** fixture in `Tests/Fixtures/csi/` (fake names, fake 8-digit ids, the 5×
  repetition, one played row, one unplayed row, one placeholder-logo row) and the confirmed selectors in the
  spike notes. T4.8a and Step 5's integration test start only when it is merged. The real page
  (`csi-exampl-page-source.txt`) is **never** committed, copied or read by an agent working in a worktree.

**Contract (Step 3, merged first).** Code against these; do not edit `Sources/SSCore/` or
`Sources/SSCoreFakes/`. If one is wrong, stop and report.

| Contract | Where | Used by |
|---|---|---|
| `Team.csiPageURL`, `TeamDraft.csiPageURL` (normalised: trimmed, `https://` added when missing, empty → `nil`), `ValidationField.csiPageURL`, `FieldLimits.csiPageURL` (500), `AppError.csiPageURLInUse(by:)`, CSI-page rule on `TeamRepository` (one page per team, compared by `csiPageKey`) | `Models.swift`, `Validation.swift`, `Repositories.swift` | b, Step 5 |
| `CSILive.pageHost`, `CSILive.logoHost`, `isValidCSIPageURL`, `csiPageURL(from:)`, `csiPageKey` | `CSI.swift` | b, c, Step 5 |
| `csiTeamID(fromLogoURL:)`, `isCSIPlaceholderLogo`, `csiLogoFileName(id:name:)`; `isValidImportedLogoFileName` also accepts `csi-[a-z0-9-]{1,60}.png` | `CSI.swift`, `Tuttocampo.swift` | a, b, c |
| `PageFixtureParser` (`parse(html:pageURL:settings:) -> FixtureFetch`, pure; its doc comment is the parser's contract), `AppServices.csiPageParser` (default: "not a CSI girone" for every page) | `CSI.swift`, `Services.swift` | a, Step 5 |
| `FetchedFixture.venue` (optional; `ImportCandidate.make` uses it for **away** drafts, cut to `FieldLimits.venue`; tuttocampo leaves it `nil`, so T4.2 behaviour is unchanged) | `Import.swift` | a, Step 5 |
| `CSIPageReadError` (`.tooLarge`, `.failed`) | `CSI.swift` | c, Step 5 |
| `ImportIssue.csiPageReadFailed`, `.csiNotAGirone`, `.csiNoFixturesOfOurs`, `.csiLogoUnavailable` (information) — every message starts with "CSI: " — and `ImportIssue.csiPage(team:outcome:clubShortName:)` | `Import.swift`, `CoreStrings.swift` | Step 5 |
| `CSILogoRequest` (+ `init?(opponent:fixture:)`: `nil` for no logo or the placeholder shield), `CSILogoData`, `CSILogoResult`, `PageLogoSource` (`@MainActor`, `fetchLogos(_:)`, reads bytes only), `storeCSILogos(_:in:)` (stores through `LogoStore`, one file per `fileName`) | `CSI.swift` | c, Step 5 |
| `FakePageFixtureParser` and its `scenario` (table in its doc comment; key: Pulcini's fake page `FakePageFixtureParser.scenarioPageURL`), `FakePageLogoSource`; fake teams: Pulcini has a CSI page; fake `TeamRepository` follows the CSI-page rule | `SSCoreFakes`, `Resources/Fixtures/matches.json` | Step 5 |

`FixtureSource` is unchanged: it stays the network path for tuttocampo. CSI has no `FixtureSource`: the page
comes from the browser window, the logos from `PageLogoSource`.

**Package.swift:** no change. `SSImport` already depends on SwiftSoup; WebKit is a system framework that
`SSApp` can import. `SSApp` still does **not** depend on `SSImport`: the UI reaches the parser through
`AppServices.csiPageParser`.

| Task | Agent | Model | Owns |
|---|---|---|---|
| T4.8a CSI parser | `render-engineer` | sonnet · effort medium | `Sources/SSImport/CSI/**` (new), `Tests/SSImportTests/CSI/**` (new), new files in `Tests/Fixtures/csi/` (derived from the Step 2 fixture only) |
| T4.8b Data | `core-dev` | sonnet · effort low | `Sources/SSData/**`, `Tests/SSDataTests/**` |
| T4.8c Browser and logos | `render-engineer` | sonnet · effort high (opus if it fails twice) | `Sources/SSApp/Features/Import/CSIBrowser/**` (new), `Tests/SSAppTests/Import/CSIBrowser/**` (new) |
| Step 5 UI and wiring | `ui-dev` | sonnet · effort medium | `Sources/SSApp/Features/Import/**` except `CSIBrowser/`, `Tests/SSAppTests/Import/**` except `CSIBrowser/`, and for this task only: `Sources/SSApp/Features/Teams/**`, `Tests/SSAppTests/Teams/**`, the Partite toolbar in `Sources/SSApp/Features/Matches/MatchesView.swift`, `Sources/SSApp/Shell/AppCommands.swift`, `Sources/SSApp/Shell/CommandActions.swift`, `Sources/SSApp/Shell/ShellScenes.swift` (the browser window scene), `Sources/SSApp/Strings/AppStrings.swift`, `Sources/SergnaneseSocial/Composition.swift`, `Tests/IntegrationTests/CSIImportTests.swift` (new), `docs/plan/01-architecture.md` §8 |

T4.8a, T4.8b and T4.8c run in parallel; Step 5 starts when all three are merged.

**Gate after Step 5:** `Scripts/check.sh` green; `qa-reviewer` (sonnet) for T4.8a, T4.8b and Step 5;
`qa-reviewer` (opus) for T4.8c and the final result (navigation policy, data store, no message handlers,
file names from remote data, Light/Dark, Mac design rules for the browser window); one live run with the
user on the real page in the Dev data folder (one page read, the logos of the opponents without one).

---

## T4.8a — CSI page parser

| | |
|---|---|
| **Agent / model** | `render-engineer` · sonnet · effort medium |
| **Depends on** | T4.8 Step 3; the Step 2 fixture in `Tests/Fixtures/csi/` |
| **Size** | M |

**Features**

1. `public struct CSIPageParser: PageFixtureParser` with `public init()`, in `Sources/SSImport/CSI/`. A pure
   function exactly as documented on `PageFixtureParser`: SwiftSoup only, nothing is loaded, rendered or run,
   no network, no file access, no state. No regular expressions on HTML (they are fine on an attribute value
   such as an `href` or a tooltip once SwiftSoup has extracted it). It must stay fast on the 1.8 MB page
   (550 rows): one parse, one pass over the rows.
2. Rows, per the spike notes (Step 2 confirms the selectors; if they differ, follow the notes and say so in
   the report):
   - row: `a.btn-gara`; match code: the `P…` path segment of its `href` (`P263A1`). Rows are **deduped by
     match code**, keeping the first in document order; a row without a code is deduped by date + home name
     + away name.
   - date: `dd/MM/yy` → year `2000 + yy`; a date that does not parse or does not exist on one of **our**
     rows → the whole page is `.sourceProblem(.structureChanged)` (`FetchedFixture.date` cannot be missing;
     same rule as T4.2a).
   - time: `span.js-gg-min` through `ClockTime(_:)`; missing or unreadable → `nil` (the app then warns
     "Manca l'orario").
   - sides: the two `div.d-flex.align-items-center` blocks in order, first = home, second = away; name =
     `span.nome-squadra` text, trimmed, whitespace collapsed.
   - ours: one side equals `settings.clubShortName` under `searchKey(stripLegalPrefixes(_:))`. Exactly one side
     ours → a fixture; neither or both → the row is ignored. Our name is written "Sergnanese" (spike); do not
     strip an age group or year from either side (opponents keep theirs: "US Esempio 2016").
   - score: `div.js-gg-pt`, two values, home then away. Both whole numbers within `0...FieldLimits.maxGoals` →
     `.played`, `Score(us:them:)` by side. Both `-` (or empty) → `.scheduled`, `score == nil`. Anything else
     → `status == nil` (needs review). `statusText` = the score cell's text, whitespace collapsed (it is shown
     only when the status is not recognised). Postponed or cancelled texts are not in the sample: when one is
     found, it goes to review; the mapping is added later with a fixture.
   - round: the number in the nearest preceding `div.label-giornata > label`: "Andata giornata N" → `N`;
     "Ritorno giornata N" → `N +` the highest andata number on the page. Kept only within
     `1...FieldLimits.maxRound`, else `nil`.
   - venue: the link's `data-bs-title` (entities decoded by SwiftSoup), with a trailing `(<code>)` removed,
     whitespace collapsed; empty → `nil`. Kept for home and away rows (`ImportCandidate.make` decides).
   - opponent logo: the `img` of the opponent's side, `src` (not `srcset`) made absolute against `<base href>`
     when present, else `pageURL`. Only `https`/`http` addresses; `isCSIPlaceholderLogo` → `nil`.
   - `opponentClubID` is always `nil`; the CSI team id is never put in a `FetchedFixture` (it is read from the
     logo address by `CSILogoRequest`).
3. Outcome: zero `a.btn-gara` rows (or no match list at all) → `.sourceProblem(.structureChanged)`; rows but
   none ours → `.sourceProblem(.noFixturesOfOurs)`; else `.fixtures` in document order. Never
   `.notYetAvailable`.
4. Nothing in `Sources/SSImport/CSI/` imports SwiftUI, WebKit or AppKit.

**Acceptance**

- [ ] Fixture test on the Step 2 file with the full expected `[FetchedFixture]`: every match of ours once
      (the 5× repetition deduped), the played row (score from our side, `isHome` right), an unplayed row
      (`.scheduled`, time), the placeholder row (`opponentLogoURL == nil`), a logo address whose
      `csiTeamID(fromLogoURL:)` is the fake id, venues without the trailing code and with entities decoded,
      andata and ritorno round numbers.
- [ ] Variants built from the fixture as strings: no rows → `.structureChanged`; a page that is not a girone
      (any other HTML) → `.structureChanged`; rows without ours → `.noFixturesOfOurs`; an unknown score text →
      `status == nil` with that `statusText`; "31/02/26" on our row → `.structureChanged`; "ASD Sergnanese"
      counts as ours; both sides ours → ignored; a relative `img src` is resolved; a missing time → `nil`;
      a venue over 60 characters is returned as it is (the cut is `make`'s job).
- [ ] `Scripts/check.sh` passes.

---

## T4.8b — Data: CSI page column and CSI logo names

| | |
|---|---|
| **Agent / model** | `core-dev` · sonnet · effort low |
| **Depends on** | T4.8 Step 3 |
| **Size** | S |

Until this task lands, `SSData` ignores `csiPageURL` (it compiles; the field is dropped on save).

**Features**

1. A new migration (never edit an existing one): `ALTER TABLE teams ADD COLUMN csi_page_url TEXT` (nullable).
   No unique index: pages are compared by `csiPageKey` (the `?j=…` query varies), which SQLite cannot compute.
2. `Team(row:prefix:)` reads the column; `create` and `update` write `draft.csiPageURL` (already normalised by
   `validated()`).
3. The CSI-page rule of `TeamRepository`, inside the write transaction: if another team's `csi_page_url` has the
   same `csiPageKey` as the draft's, throw `AppError.csiPageURLInUse(by: <that team's name>)`.
4. `LogoFileStore.importLogo(data:fileName:replacing:)` already calls `isValidImportedLogoFileName`, which now
   accepts `csi-…png` names: check it, and update `DataStrings.invalidLogoFileName` so it names both forms
   ("917410.png o csi-12345678.png").

**Acceptance**

- [ ] Migration test: a database file created by the previous schema opens, keeps its teams and matches, every
      team has `csiPageURL == nil` and keeps its `tuttocampoWidgetID`; opening again changes nothing.
- [ ] Repository tests: create with a page, update to another page, clear it (`""` → `nil`), a page pasted
      without `https://` is stored with it, the same page with another `?j=` or another case on another team
      throws `AppError.csiPageURLInUse(by:)` naming that team (create and update), a team may save its own page
      again, a page on another host throws `.validation(field: .csiPageURL, …)`.
- [ ] `LogoFileStore` tests: a JPEG stored as `csi-12345678.png` is a PNG ≤ 1024 px; `csi-us-esempio-2016.png`
      is accepted; `csi-../x.png`, `csi-ABC.png`, `csi-.png` are refused and nothing is written.
- [ ] Existing team, match, seed and widget-id tests unchanged and green.
- [ ] `Scripts/check.sh` passes.

---

## T4.8c — Browser window and logos from the page session

| | |
|---|---|
| **Agent / model** | `render-engineer` · sonnet · effort high (opus if it fails twice) |
| **Depends on** | T4.8 Step 3 |
| **Size** | M |

Everything here is `@MainActor` and lives in `Sources/SSApp/Features/Import/CSIBrowser/`. Italian strings in a
`CSIBrowserStrings` file there. Standard controls, system font, Light and Dark Mode.

**Features**

1. `@MainActor @Observable final class CSIBrowserController: PageLogoSource`, `init(team: Team)` (the team must
   have a `csiPageURL`). It owns one `WKWebView` and exposes what Step 5 needs: `team`, `currentURL`,
   `isLoading`, `canGoBack`/`canGoForward`, `canImport` (`currentURL` passes `isValidCSIPageURL` and the page
   is not loading), `isOnTeamPage` (`csiPageKey(currentURL) == csiPageKey(team.csiPageURL)`),
   `func readPage() async -> Result<CSIPageSnapshot, CSIPageReadError>` with
   `struct CSIPageSnapshot: Sendable { var html: String; var pageURL: URL }`, `fetchLogos(_:)`, and
   `static func clearWebsiteData() async`.
2. `CSIBrowserView(controller:onImport:)`: the web view, a toolbar with Indietro, Avanti, Ricarica (all
   user-operated), the current address (read-only text), "Cancella dati del sito CSI" (in a toolbar menu, with a
   confirmation), and the prominent **"Importa questa pagina"** button, enabled by `canImport`, which calls
   `onImport`. The view does not parse or store anything; Step 5 presents it in its own window.
3. Web view configuration:
   - `websiteDataStore = WKWebsiteDataStore(forIdentifier:)` with one fixed UUID constant for CSI (persistent,
     separate from the renderer's non-persistent store). `clearWebsiteData()` removes all its data
     (`removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)`).
   - No script message handlers, no user scripts, no custom user agent (no faked identity), no
     `javaScriptCanOpenWindowsAutomatically`. JavaScript stays on (the site and the check need it).
   - The app never calls `load`, `reload` or `goBack` by itself, except the single initial `load` of
     `team.csiPageURL` when the window opens.
4. Navigation policy, a pure, tested function (e.g. `CSINavigationPolicy.decision(for:isMainFrame:isUserAction:)`
   → `.allow` / `.openInBrowser` / `.cancel`):
   - `https` to `CSILive.pageHost` or `challenges.cloudflare.com`, any frame → allow;
   - `about:blank` / `about:srcdoc` in a subframe → allow;
   - a main-frame navigation the user started to any other `https`/`http` address → cancel and open it with
     `NSWorkspace` in the default browser;
   - everything else (other schemes, other hosts in subframes, non-user main-frame redirects off the
     allowlist) → cancel.
   - Pop-ups (`createWebViewWith`) → `nil`; a user-clicked `target=_blank` link follows the rule above.
     Responses that are downloads → cancel.
5. `readPage()`: one `callAsyncJavaScript` in `WKContentWorld.defaultClient` that returns
   `document.documentElement.outerHTML` (or `null` past the cap, checked in the page first); in Swift, more than
   **2 MB** of UTF-8 → `.tooLarge`; a JavaScript error, `nil`, a closed window or a still-loading page →
   `.failed`. `pageURL` is `currentURL`. Nothing else is read from the page.
6. `fetchLogos(_:)` (the `PageLogoSource` contract): for each request, in order, at most 3 at a time:
   - in the page session: `callAsyncJavaScript` in `.defaultClient` that `fetch`es `request.logoURL` (only
     `https`/`http`), refuses a response that is not `ok`, not `image/*` or over **5 MB**, and returns the bytes
     as base64; Swift decodes and re-checks the size;
   - if that fails and the logo host is shown **not** to be behind the bot check (check it live with the user
     during acceptance; until then a constant `allowsDirectLogoDownload = false`): a `URLSession` download with
     the T4.2 rules — `https` only, host exactly `CSILive.logoHost` for the request and every redirect,
     ephemeral configuration with cookies and the URL cache off, 15 s request / 30 s resource timeout, 5 MB cap
     while reading, content type `image/png`, `image/jpeg` or `image/webp`, `User-Agent: SergnaneseSocial/<version>`;
   - otherwise `data == nil`.
   Never navigates, never throws; cancellation → the rest `nil`. It does **not** store anything: Step 5 passes
   the result to `storeCSILogos(_:in:)`.
7. `01-architecture.md` §8 already describes this window; report any difference instead of editing it (Step 5
   owns that file).

**Acceptance**

- [ ] Navigation policy table tests: the page host, the challenge host, a subframe on another host, a user click
      to another host (open in browser), `http://` to the page host, `file:`, `javascript:`, `data:`, a redirect
      off the allowlist, `about:blank` in a subframe.
- [ ] Page reading: the size cap (a helper that takes the string is tested: 2 MB + 1 byte → `.tooLarge`),
      `nil`/error → `.failed`; `canImport` and `isOnTeamPage` from addresses (with another `?j=`, another
      girone, the challenge host).
- [ ] Logos: base64 decoding and the 5 MB cap (helper tests); with `allowsDirectLogoDownload` on, the
      `URLSession` client on a `URLProtocol` stub: other host refused before any request, redirect off the host
      refused, `http://` refused, over 5 MB refused, `text/html` refused, no cookies sent; the stub fails the test
      on any unexpected URL. **No live network in tests.**
- [ ] The configuration has no message handlers and no user scripts (asserted on the built
      `WKWebViewConfiguration`), and its data store is the fixed CSI identifier, not `.default()` and not the
      renderer's.
- [ ] Manual run with the user on the real page (Dev data folder): the page opens, the check (if shown) can be
      passed, "Importa questa pagina" reads the page, logos are fetched in the page session; whether the logo
      host is protected is recorded in the report and in the spike notes.
- [ ] `Scripts/check.sh` passes.

---

## Step 5 — UI and wiring

| | |
|---|---|
| **Agent / model** | `ui-dev` · sonnet · effort medium |
| **Depends on** | T4.8a, T4.8b, T4.8c merged |
| **Size** | M |

Built and tested against `AppServices.fake()` (`FakePageFixtureParser.scenario` answers for Pulcini's page) and
`FakePageLogoSource`. The staging sheet, report and commit are T4.2c's: reuse them, do not copy them. Italian
strings in `ImportStrings` / `TeamsStrings` / `AppStrings`; core messages (`ImportIssue.message`,
`ImportCandidate.reviewMessages`, `FieldProblem.message`) are shown as they are.

**Features**

1. **Squadre**: a "Pagina CSI" text field per team next to the widget id field, help line "Incolla l'indirizzo
   della pagina del girone su CSI Live". Saved through `TeamRepository.update`; the `.csiPageURL` problem (invalid
   address, page already used) is shown under the field.
2. **Command**: "Importa da CSI…" in the File menu after "Importa da Tuttocampo…" (no shortcut), published by
   Partite as a focused action, and a toolbar button in Partite next to the Tuttocampo one. Disabled, with the
   reason as help text, while no active team has a CSI page.
3. **Team**: with one active team with a page, open it directly; with several, a small sheet with a picker of
   those teams (in `sortOrder`) and Apri / Annulla.
4. **Browser window**: a `WindowGroup(id: "csi-browser", for: EntityID.self)` scene in `ShellScenes.swift` showing
   T4.8c's `CSIBrowserView` for the team, titled "CSI – <team name>", a sensible default size (about 1100×800).
   One window per team; opening it again brings it to the front.
5. **"Importa questa pagina"** (`onImport`):
   - `controller.readPage()`; `.failure` → `ImportIssue.csiPageReadFailed(team:reason:)` shown in the report;
   - when `!controller.isOnTeamPage`, a standard confirmation first: "La pagina aperta non è quella salvata per
     <team>. Importare comunque?" (Importa / Annulla);
   - parse off the main actor (`services.csiPageParser` is `Sendable`; the HTML is up to 2 MB) with
     `settings.load()`;
   - `ImportIssue.csiPage(team:outcome:clubShortName:)` non-`nil` → shown in the report, nothing staged;
   - otherwise candidates with `ImportCandidate.make` (as T4.2c) into the **same staging sheet**, presented on the
     browser window. Ticks, create/link opponent, away venue (now usually filled from CSI), locked rows: as
     T4.2c. The import model gains a source (Tuttocampo / CSI with its team and `PageLogoSource`) instead of a
     second model.
6. **Commit**: `upsertFromImport` exactly as T4.2c. Logos for the same opponents T4.2c picks (no logo, or
   "Sostituisci il logo" on): `CSILogoRequest(opponent:fixture:)`; `nil` → `.csiLogoUnavailable` in the report;
   the others → `controller.fetchLogos` → `storeCSILogos(_:in: services.logos)` → for each `fileName`,
   `opponents.update` and removal of the old file when it differs (T4.2c's helper). Closing the browser window
   while staging cancels the import.
7. **Composition**: `Composition.makeServices` passes `csiPageParser: CSIPageParser()`. Log each CSI import outcome
   under `Log.imports` (team name and outcome only; no HTML, no addresses).
8. **`01-architecture.md` §8**: check that the CSI note matches what was built (hosts, data store, navigation,
   no message handlers, caps, logo names, whether the logo host download is on) and correct it if not.

**Acceptance**

- [ ] Model tests on the fake scenario (Pulcini's page, `FakePageLogoSource`): the states of
      `FakePageFixtureParser.scenario`'s table; linking "Valdorso 2016" to F.C. Valdorso saves the alias and the row
      becomes `.changed`; creating "Polisportiva Fontanella" gives a `.new` row whose venue is the CSI venue;
      committing writes exactly the ticked drafts with source `.scrape`; logos: Atletico Montesello stored as
      `csi-90000104.png` and saved on the opponent, Borgo Lucente reported `.csiLogoUnavailable`, Prato Fiorito
      (already has a logo) not requested.
- [ ] Another page address → the "non sembra un girone CSI" line; a read failure → the read-failure line; the
      confirmation appears when the page is not the team's.
- [ ] Pagina CSI field: a pasted address without `https://` is stored with it; a page used by another team shows
      the error under the field.
- [ ] The command is disabled with no CSI page; Tuttocampo import unchanged (its tests green).
- [ ] Integration test (`Tests/IntegrationTests/CSIImportTests.swift`) in a temporary `SS_DATA_DIR`, real database
      and `LogoFileStore`: the Step 2 fixture HTML → `CSIPageParser` → `ImportCandidate.make` →
      `upsertFromImport` → `storeCSILogos` with JPEG bytes from a test file → opponent updated; the match is
      stored with source `.scrape` and the away venue from CSI, the logo is `logos/csi-<fake id>.png`. No
      browser, no network.
- [ ] Screens checked in Light and Dark Mode; standard controls only; the browser window follows the Mac design
      rules (toolbar, title, resizable, remembers its size).
- [ ] `Scripts/check.sh` passes.
