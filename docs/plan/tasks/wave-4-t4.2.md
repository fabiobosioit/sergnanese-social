# T4.2 — Tuttocampo import: task sheets (Step 4 and Step 5)

Full sheets for the work after the T4.2 contract step. The background, the decisions and the logo rule
are in `wave-4-later.md` § T4.2; the facts about the widgets are in `docs/plan/notes/t4.2-spike.md`;
sanitised pages are in `Tests/Fixtures/tuttocampo/`. Read the T4.2 section and the spike notes before
starting; this sheet does not repeat them.

**Blocked on:** Step 1 (user): the tuttocampo.it terms-of-use check and the widget → team mapping.
No task below starts before the user has confirmed both.

**Contract (Step 3, merged first).** Code against these; do not edit `Sources/SSCore/` or
`Sources/SSCoreFakes/`. If one is wrong, stop and report.

| Contract | Where | Used by |
|---|---|---|
| `Team.tuttocampoWidgetID`, `TeamDraft.tuttocampoWidgetID` (normalised: a pasted widget address becomes the id), `ValidationField.tuttocampoWidgetID`, `AppError.widgetIDInUse(by:)`, widget-id rule on `TeamRepository` | `Models.swift`, `Validation.swift`, `Repositories.swift` | b, c |
| `isValidTuttocampoWidgetID`, `tuttocampoWidgetID(from:)`, `tuttocampoClubID(fromLogoURL:)`, `tuttocampoLogoURL(clubID:)` (`Teams/200`), `tuttocampoLogoFileName(clubID:)`, `isValidImportedLogoFileName` | `Tuttocampo.swift` | a, b |
| `LogoStore.importLogo(data:fileName:replacing:)` (default implementation exists) | `Services.swift` | a, b |
| `FixtureSource` (`fetchFixtures(for:settings:)`, `downloadLogos(_:)`), `FetchedFixture`, `FixtureFetch`, `FixtureHealthProblem`, `FixtureFetchError`, `LogoRequest`, `LogoResult` | `Import.swift` | a, c, Step 5 |
| `ImportCandidate` (+ `State`, `ReviewReason`, `make(…)`), `opponentsMatching(name:in:)`, `ImportIssue` (Italian `message`, `isError`) | `Import.swift` | c, Step 5 |
| `AppServices.fixtureSource` (default: a source that throws `.unavailable`) | `Services.swift` | c, Step 5 |
| `FakeFixtureSource` and its `scenario` (every staging state and report line; table in its doc comment); fake teams carry widget ids | `SSCoreFakes`, `Resources/Fixtures/matches.json` | c |

**Package.swift (orchestrator, before Step 4).** Exactly this change, then `swift package resolve` and
commit `Package.swift` + `Package.resolved` (SwiftSoup 2.14.4 was checked to build with these
Command Line Tools in Swift 6 mode with warnings as errors):

```swift
let libraries = ["SSCore", "SSCoreFakes", "SSData", "SSTemplates", "SSRender", "SSSeed", "SSApp", "SSImport"]
// dependencies: add
    .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.14.4"),
// targets: add
    .target(name: "SSImport", dependencies: ["SSCore", .product(name: "SwiftSoup", package: "SwiftSoup")]),
    .testTarget(name: "SSImportTests", dependencies: ["SSImport", "SSCoreFakes"]),
```

Adding `SSImport` to `libraries` puts it in `SergnaneseSocial`, `ss-tool` and `IntegrationTests`. `SSApp`
does **not** depend on `SSImport`: the UI only sees `AppServices.fixtureSource`. Until T4.2a lands,
create `Sources/SSImport/SSImport.swift` and `Tests/SSImportTests/Placeholder.swift` (an empty
`enum SSImport {}` and an empty file) so the package builds; T4.2a replaces them.

| Task | Agent | Model | Owns |
|---|---|---|---|
| T4.2a Fetch, parse, logos | `render-engineer` | sonnet · effort high | `Sources/SSImport/**`, `Tests/SSImportTests/**`, new files in `Tests/Fixtures/tuttocampo/` |
| T4.2b Data | `core-dev` | sonnet · effort medium | `Sources/SSData/**`, `Tests/SSDataTests/**` |
| T4.2c UI | `ui-dev` | sonnet · effort medium | `Sources/SSApp/Features/Import/**` (new), `Tests/SSAppTests/Import/**` (new), and for this task only: `Sources/SSApp/Features/Teams/**`, `Tests/SSAppTests/Teams/**`, the Partite toolbar in `Sources/SSApp/Features/Matches/MatchesView.swift`, `Sources/SSApp/Shell/AppCommands.swift`, `Sources/SSApp/Shell/CommandActions.swift`, `Sources/SSApp/Strings/AppStrings.swift` |
| Step 5 Wiring | `core-dev` | sonnet · effort medium | `Sources/SergnaneseSocial/Composition.swift`, `Tests/IntegrationTests/TuttocampoImportTests.swift` (new), `docs/plan/01-architecture.md` §8 |

T4.2a, T4.2b and T4.2c run in parallel; Step 5 starts when all three are merged.

**Gate after Step 5:** `Scripts/check.sh` green; `qa-reviewer` (opus) checks T4.2a and the final
result; one manual import against the live site in the Dev data folder, by the user or with the user
watching (one request per mapped team plus missing logos).

---

## T4.2a — Fetch, parse and logo download

| | |
|---|---|
| **Agent / model** | `render-engineer` · sonnet · effort high (opus if it fails twice) |
| **Depends on** | T4.2 Step 3, the `Package.swift` change |
| **Size** | M |

**Features**

1. `public struct TuttocampoWidgetSource: FixtureSource` with
   `public init(logos: any LogoStore, configuration: URLSessionConfiguration = .ephemeral, minimumInterval: Duration = .seconds(1))`.
   Tests pass a configuration whose `protocolClasses` holds a `URLProtocol` stub.
2. **HTTP client** (internal):
   - https only; every request **and every redirect** (`URLSessionTaskDelegate` redirect callback) is
     checked against the allowlist `www.tuttocampo.it`, `b2-content.tuttocampo.it`; anything else →
     `FixtureFetchError.notAllowed`, nothing is read.
   - Session: the given configuration with cookies off (`httpCookieStorage = nil`,
     `httpShouldSetCookies = false`), `urlCache = nil`, request timeout 15 s, resource timeout 30 s.
   - Header `User-Agent: SergnaneseSocial/<CFBundleShortVersionString, or "dev">`. No other identifying data.
   - Size caps, enforced while reading (`bytes(for:)`, stop past the cap): page 1 MB → `.responseTooLarge`;
     logo 5 MB (the `LogoStore` limit).
   - Mapping: status ≠ 200 → `.httpStatus(code)`; `URLError.timedOut` → `.timeout`; other `URLError`s →
     `.network`; cancellation → `CancellationError`.
   - Politeness: an actor keeps at least `minimumInterval` between two **page** requests. No retries.
3. **`fetchFixtures(for:settings:)`**: `team.tuttocampoWidgetID` missing or not
   `isValidTuttocampoWidgetID` → `.missingWidgetID`. One GET of
   `https://www.tuttocampo.it/WidgetV2/Risultati/<id>` (the default matchday; no matchday segment,
   no `y`), then the parser.
4. **Parser**, a pure internal function `parseResults(html: String, pageURL: URL, clubShortName: String, season: String) -> FixtureFetch`
   with SwiftSoup (no regular expressions on HTML; nothing is loaded, rendered or run):
   - `#content .message_info` whose text contains "non ancora disponibili" → `.notYetAvailable`.
   - Table: `#table_results_content table`. Missing (and no message) → `.sourceProblem(.structureChanged)`.
   - Round: the number in the table caption's `title` ("Risultati Giornata 11"), else the `title` of
     `.swiper-slide.selected span`; kept only within `1...FieldLimits.maxRound`.
   - Rows in document order: a `tr.date` sets the current date from its `span` text
     ("Dom. 22 novembre": weekday ignored, day without leading zero, full Italian month name, any case);
     a `tr.match` before any date row, or a date that does not parse or does not exist → `.structureChanged`.
   - Year: from `season` ("2026/27"): months August–December → 2026, January–July → 2027.
   - Time: `.match-time` text, trimmed, through `ClockTime(_:)`; unreadable → `nil`.
   - Sides: `td.team.home` and `td.team.away`; name = `.team-name` text (trimmed); logo = `img`
     `src` (not `srcset`) made absolute against `<base href>` when present, else `pageURL`; goal =
     `span.goal` text and `title`.
   - Ours: a side whose name equals `clubShortName` under `searchKey(stripLegalPrefixes(_:))`. Exactly one
     side ours → a `FetchedFixture` (`isHome` = our side is home; opponent = the other side, with
     `opponentClubID = tuttocampoClubID(fromLogoURL:)` and `opponentLogoURL` = its absolute `src`).
     Neither or both sides ours → row ignored.
   - Status from the goal `title` (statusText = that title, trimmed):

     | Title | `status` | `score` |
     |---|---|---|
     | "Partita da giocare" | `.scheduled` | `nil` |
     | "Partita terminata" with a number in both goals | `.played` | `Score(us:them:)` by side |
     | "Partita terminata" without both numbers | `nil` (review) | `nil` |
     | "Partita rinviata" | `.postponed` | `nil` |
     | starts with "Partita in corso" | `.scheduled` | `nil` (a live score is not imported; import again after the match) |
     | anything else | `nil` (review) | `nil` |

     Goals over `FieldLimits.maxGoals` count as "without numbers".
   - Zero `tr.match` rows → `.structureChanged`; rows but none ours → `.sourceProblem(.noFixturesOfOurs)`.
5. **`downloadLogos(_:)`** exactly as documented on `FixtureSource`: one download per distinct
   `clubID`, at most 3 at a time; `tuttocampoLogoURL(clubID:)` first, then the request's `fallbackURL` once
   (only if https and on the allowlist); a download fails on a non-200 status, a content type that is
   not `image/png`, `image/jpeg` or `image/webp`, more than 5 MB, or `LogoStore` rejecting the bytes.
   Stored with `logos.importLogo(data:fileName: tuttocampoLogoFileName(clubID:)!, replacing: nil)`. No
   `clubID` → `.logoNotRecognised` without any request. Never throws.
6. Nothing in `SSImport` imports SwiftUI, WebKit or AppKit, and nothing writes outside the logos folder.

**Acceptance**

- [ ] Parser tests on every file in `Tests/Fixtures/tuttocampo/` with the full expected `FixtureFetch`:
      home played 8–4 (round 10, `isHome`, score from our side); away scheduled (round 11, time 14:30);
      postponed-live (our row: status `.postponed`, statusText "Partita rinviata"; the live, finished and
      scheduled rows of other clubs are ignored); no-Sergnanese → `.noFixturesOfOurs`; empty → `.notYetAvailable`.
- [ ] Parser tests on strings derived from the fixtures: unknown title → `status == nil`; missing table →
      `.structureChanged`; match row before a date row → `.structureChanged`; "Sab. 3 gennaio" with season
      2026/27 → 2027-01-03; "Dom. 30 febbraio" → `.structureChanged`; relative `img src` resolved against
      `<base href>`; a name "A.S.D. Sergnanese" counts as ours; a row with both sides ours is ignored.
- [ ] HTTP tests with the `URLProtocol` stub: 200; 404 → `.httpStatus(404)`; timeout → `.timeout`;
      offline → `.network`; redirect to another host → `.notAllowed` and the redirect target is never
      requested; a 2 MB page → `.responseTooLarge`; `http://` refused; no `Cookie` header sent after a
      `Set-Cookie`; the `User-Agent` is set; two page fetches are `minimumInterval` apart.
- [ ] Logo tests: `Teams/200` is requested first; its 404 → fallback stored with `.logoFallback`; both
      fail → `.logoFailed`; HTML served as a logo → failure; two requests with one `clubID` → one
      download, both results named `"<ClubId>.png"`; no `clubID` → `.logoNotRecognised` and no request;
      cancellation → remaining results `nil`/`nil`. Stored through `FakeLogoStore`.
- [ ] **No live network in any test**: every test session uses the stub, and the stub fails the test on
      an unexpected URL.
- [ ] `Scripts/check.sh` passes.

---

## T4.2b — Data: widget id column and named logo import

| | |
|---|---|
| **Agent / model** | `core-dev` · sonnet · effort medium |
| **Depends on** | T4.2 Step 3 |
| **Size** | S |

**Features**

1. A new migration (never edit an existing one): `ALTER TABLE teams ADD COLUMN tuttocampo_widget_id TEXT`
   (nullable) and
   `CREATE UNIQUE INDEX teams_tuttocampo_widget_id ON teams(tuttocampo_widget_id COLLATE NOCASE) WHERE tuttocampo_widget_id IS NOT NULL`.
2. `Team(row:prefix:)` reads the column; `create` and `update` write `draft.tuttocampoWidgetID` (already
   normalised by `validated()`).
3. The widget-id rule of `TeamRepository`: before writing, if another team has the same id ignoring case,
   throw `AppError.widgetIDInUse(by: <that team's name>)`. The unique index is only the safety net.
4. `LogoFileStore.importLogo(data:fileName:replacing:)` implemented directly (not the protocol default):
   `isValidImportedLogoFileName(fileName)` or `AppError.validation(field: .logo, …)` with a `DataStrings`
   message; the 5 MB check and the PNG conversion of `importLogo(data:replacing:)`; write to `<fileName>`
   with `.atomic` (replaces an existing file in one step); then remove `replacing` when it differs from
   `fileName`. Returns `fileName`.

**Acceptance**

- [ ] Migration test: a database file created by the previous schema opens, keeps its teams and matches,
      and every team has `tuttocampoWidgetID == nil`; opening again changes nothing.
- [ ] Repository tests: create with an id, update to another id, clear it (`""` → `nil`), a pasted widget
      address is stored as the bare id, a duplicate id (other case) on create and on update throws
      `AppError.widgetIDInUse(by:)` naming the other team, a team may save its own id again, an invalid
      id throws `.validation(field: .tuttocampoWidgetID, …)`.
- [ ] `LogoFileStore` tests: a 3000 px JPEG stored as `917410.png` is a PNG ≤ 1024 px; storing the same
      name again replaces it (one file); `replacing` is removed; `../x.png`, `917410.jpg`, `abc.png` are
      refused and nothing is written.
- [ ] `Matches`, seed and demo-data tests unchanged and green.
- [ ] `Scripts/check.sh` passes.

---

## T4.2c — UI: widget id field, import sheet, staging and report

| | |
|---|---|
| **Agent / model** | `ui-dev` · sonnet · effort medium (high on retry) |
| **Depends on** | T4.2 Step 3 |
| **Size** | L |

Built and tested against `AppServices.fake()`, whose `FakeFixtureSource.scenario` returns every case.
Standard controls, system font, semantic colours, Light and Dark Mode, Italian strings in
`Features/Import/ImportStrings.swift` (and `AppStrings` for the menu title). Messages that come from
the core (`ImportIssue.message`, `ImportCandidate.reviewMessages`, `FieldProblem.message`) are shown as
they are.

**Features**

1. **Squadre**: an "ID widget Tuttocampo" text field per team (in the team's edit UI), with a short help
   line ("Incolla l'ID o l'indirizzo del widget dei risultati"). Saved through `TeamRepository.update`;
   the problem for `.tuttocampoWidgetID` (invalid id, id already used) is shown under the field with
   `fieldProblem`.
2. **Command**: "Importa da Tuttocampo…" in the File menu after "Importa template…" (no shortcut), published
   by Partite as a focused action, and a toolbar button in Partite. Disabled, with the reason as help
   text, while no active team has a widget id.
3. **Fetch**: an `@MainActor @Observable` import model fetches every **active** team with a widget id, in
   `sortOrder`, **one at a time**, with `settings.load()`; the sheet shows a determinate progress
   ("Lettura di Juniores… 3 di 9") and **Annulla** (cancels the task; teams already read stay). Each
   outcome becomes candidates or an `ImportIssue` (`.fetchFailed`, `.sourceProblem` with
   `clubShortName`, `.notYetAvailable`).
4. **Candidates**: `ImportCandidate.make` for every fixture, with `opponents.list()`,
   `matches.list(from:to:teamID:)` covering the fixture dates and `settings.homeVenue`.
5. **Staging sheet**: the report first (errors with `exclamationmark.triangle`, information with
   `info.circle`), then candidates grouped by weekend (`weekend(containing:)`, titled with
   `formatWeekend`), sorted like `MatchDetail.scheduleOrder`. Each row: team, `formatDateShort` + time,
   Casa/Trasferta, opponent, state badge (Nuova, Modificata, Invariata, Bloccata, Da rivedere). Changed
   rows list what changes (old → new) for time, opponent, home/away, status, score, venue, round.
   - Ticks: `.new` and `.changed` rows of `nextWeekend(from: .today())` are ticked by default, other
     weekends unticked; `.unchanged` and `.locked` cannot be ticked; `.needsReview` cannot be ticked
     until resolved.
   - Opponent not found or ambiguous: **Crea avversario** (`opponents.create` with the fetched name) or
     **Collega a esistente…** (a searchable picker; saves the fetched name as an alias of the chosen
     opponent through `opponents.update`, then rebuilds the candidate with `linkedOpponentID`). After
     either, the candidate is rebuilt and its new state shown.
   - Unknown status: the row shows `reviewMessages` and cannot be imported in this version.
   - `isVenueMissing`: an inline "Campo (da completare)" field editing `draft.venue`; empty is allowed.
   - Opponents that already have a logo get a "Sostituisci il logo" toggle, off by default.
6. **Importa** (default button, disabled with nothing ticked): `matches.upsertFromImport` with the ticked
   drafts (source `.scrape`), then the summary ("N nuove, M aggiornate, K bloccate"). Then logos:
   one `LogoRequest(opponent:fixture:)` per imported opponent with `logoFile == nil` or the replace toggle
   on; `fixtureSource.downloadLogos`; for each result with a `fileName`, `opponents.update` with it and,
   when the old file differs, `logos.remove(fileName:)` of the old one. Logo issues are added to the
   report, which stays open until **Fine**.
7. No request is made except when the user starts an import; nothing runs in the background.

**Acceptance**

- [ ] Model tests on the fake scenario: the states per team are the table of `FakeFixtureSource.scenario`;
      the default ticks are the coming weekend's `.new`/`.changed`; the report has the three team issues
      (Giovanissimi U15, Giovanissimi U14 as information, Esordienti).
- [ ] Committing writes exactly the ticked drafts (`ImportSummary` checked); a locked match is never sent;
      importing again shows those rows as `.unchanged`.
- [ ] "Crea avversario" on Juniores Femminile turns its row into `.new` with the venue to complete;
      "Collega a esistente…" saves the alias and resolves the row.
- [ ] Logos: requested only for opponents without a logo (or with the toggle on); the new file name is saved
      on the opponent; Atletico Montesello's fallback and the new opponent's unrecognised address appear in
      the report.
- [ ] Annulla during the fetch stops it and shows what was read; the command is disabled with no widget id.
- [ ] Widget id field: saving a pasted address stores the id; an id used by another team shows the
      error under the field.
- [ ] Screens checked in Light and Dark Mode; standard controls only.
- [ ] `Scripts/check.sh` passes.

---

## Step 5 — Wiring and integration test

| | |
|---|---|
| **Agent / model** | `core-dev` · sonnet · effort medium |
| **Depends on** | T4.2a, T4.2b, T4.2c merged |
| **Size** | S |

**Features**

1. `Composition.makeServices` passes `fixtureSource: TuttocampoWidgetSource(logos: logos)` (the same
   `LogoFileStore`) to `AppServices`. Log each import fetch outcome under `Log.imports` (team name and
   outcome only; no HTML).
2. `01-architecture.md` §8: check that the security note matches what was built (hosts, caps, timeouts,
   cookies off, User-Agent, digits-only logo names) and correct it if not.

**Acceptance**

- [ ] Integration test in a temporary `SS_DATA_DIR`, real database and `LogoFileStore`,
      `TuttocampoWidgetSource` on a `URLProtocol` stub serving `risultati-home-played.html` for one team's
      widget and a PNG for `Teams/200`: fetch → `ImportCandidate.make` → `upsertFromImport` →
      `downloadLogos` → opponent updated. The match is in the database with source `.scrape`, the logo is
      `logos/<ClubId>.png`, and no request left the stub.
- [ ] `Scripts/run.sh` (Dev data folder): the import command is there; with no widget id it is disabled.
- [ ] `Scripts/check.sh` passes.
