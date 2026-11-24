# T4.9 — Download all opponents at once: task sheets (Step 2 and Step 3)

Full sheets for the work after the T4.9 contract step. The decisions (where the button is, what is read, the
review sheet, the duplicate rule, the merge rules) are in `wave-4-later.md` § T4.9 and decision D11 in
`docs/plan/README.md`. Read both before starting; this sheet does not repeat them.

**Blocked on:** T4.2 and T4.8 merged (done), and the Step 1 contract below merged. No live network in any test.

**Contract (Step 1, merged first).** Code against these; do not edit `Sources/SSCore/` or `Sources/SSCoreFakes/`.
If one is wrong, stop and report. The flow comment at the top of `Sources/SSCore/OpponentDownload.swift` is the
end-to-end recipe.

| Contract | Where | Used by |
|---|---|---|
| `TeamListSource` (`.tuttocampo`, `.csi`), `SourceTeam` (source, our `teamID`, `name`, `logoID` = tuttocampo ClubId or CSI 8-digit id, `logoURL`, `hasLogo`), `SourceTeamList` (team, source, `readAt`, teams; its init stamps team and source on every element) | `OpponentDownload.swift` | a, b, c, 3 |
| `FixtureSource.fetchLeagueTeams(for:settings:) -> LeagueTeamsFetch` (`.teams([SourceTeam])` / `.structureChanged`; throws `FixtureFetchError`). Its doc comment is the Classifica parser's contract. Default implementation (protocol extension, so `UnavailableFixtureSource` too): throws `.unavailable` | `Import.swift` | a, c, 3 |
| `PageFixtureParser.teams(html:pageURL:for:settings:) -> [SourceTeam]` (pure; doc comment = contract). Default: `[]` | `CSI.swift` | a, c, 3 |
| `SourceTeamListRepository` (`save(teamID:source:teams:readAt:)` replaces the list of that team and source; `latest(teamID:source:)`; `AppError.notFound` for an unknown team), `AppServices.sourceTeamLists` (default: keeps nothing, finds nothing); `TeamRepository.delete` also deletes the team's lists | `Repositories.swift`, `Services.swift` | b, c, 3 |
| `OpponentCandidate` (`.new` / `.missingLogo` / `.present` / `.possibleDuplicate`; `id` = `importNameKey(name)`; `sightings`; `existing`; `logo`; `isTickedByDefault`), `OpponentCandidate.make(found:existing:clubShortName:)`, `OpponentCandidate.possibleDuplicatePairs(in:existing:)`, `OpponentDuplicatePair` (`id`, `firstName`, `secondName`, `second`: another row or an existing opponent) | `OpponentDownload.swift` | c, 3 |
| `OpponentMergeChoice` (`.useFirst` "Usa «A»", `.useSecond` "Usa «B»", `.keepSeparate` "Tieni separati"), `OpponentImportPlan.make(candidates:ticked:pairs:choices:)` (pure; throws `OpponentPlanError` `.choicesMissing` / `.conflictingChoices`, each with an Italian `message`), `OpponentImportPlan.Item` (`action`, `logo`, `candidateIDs`), `OpponentImportPlan.Action.draft(current:)` | `OpponentDownload.swift` | b, c, 3 |
| `OpponentRepository.applyImport(_ plan:) -> [Opponent]`: one transaction, one opponent per item. Default implementation (protocol extension): throws `AppError.io`, writes nothing | `Repositories.swift` | b, c, 3 |
| `LogoRequest(opponent:sourceTeam:)` (tuttocampo), `CSILogoRequest(opponent:sourceTeam:)` (CSI; `nil` for no logo or the placeholder) | `OpponentDownload.swift` | c, 3 |
| `ImportIssue.standingsReadFailed(team:reason:)`, `.standingsChanged(team:)` (errors, "Tuttocampo: impossibile leggere la classifica di …"), `.csiTeamListMissing(team:)` (information, "CSI: nessuna lettura per …, usa prima Importa da CSI…"); logo lines reuse `.logoNotRecognised`, `.logoFallback`, `.logoFailed`, `.csiLogoUnavailable` | `Import.swift`, `CoreStrings.swift` | c, 3 |
| Fakes: `FakeFixtureSource.leagueResponses` and the Classifica table in `FakeFixtureSource.scenario`'s doc comment; `FakePageFixtureParser.teamResponses` and `scenarioTeams(teamID:)`; `FakeSourceTeamListRepository` (`AppServices.fake()` stores Pulcini's CSI list); `FakeOpponentRepository.applyImport` (all or nothing) | `SSCoreFakes` | c |

**Package.swift:** no change. `SSApp` still does not depend on `SSImport` or `SSData`: the UI reaches everything
through `AppServices`.

| Task | Agent | Model | Owns |
|---|---|---|---|
| T4.9a Sources | `render-engineer` | sonnet · effort medium | `Sources/SSImport/**`, `Tests/SSImportTests/**`, new files in `Tests/Fixtures/tuttocampo/` and `Tests/Fixtures/csi/` (derived from the existing fixtures only) |
| T4.9b Data | `core-dev` | sonnet · effort medium | `Sources/SSData/**`, `Tests/SSDataTests/**` |
| T4.9c UI | `ui-dev` | sonnet · effort medium (high only on retry) | `Sources/SSApp/Features/Opponents/**`, `Tests/SSAppTests/Opponents/**`; for this task only: the CSI hook in `Sources/SSApp/Features/Import/ImportModel.swift` and its tests in `Tests/SSAppTests/Import/` (not `CSIBrowser/`), `Sources/SSApp/Shell/AppCommands.swift`, `Sources/SSApp/Shell/CommandActions.swift` |
| Step 3 Wiring | `core-dev` | sonnet · effort medium | `Sources/SergnaneseSocial/Composition.swift`, `Tests/IntegrationTests/OpponentDownloadTests.swift` (new), `docs/plan/01-architecture.md` §7 and §8 |

T4.9a, T4.9b and T4.9c run in parallel; Step 3 starts when all three are merged.

**Gate after Step 3:** `Scripts/check.sh` green; `qa-reviewer` (sonnet, medium) for T4.9a, T4.9b and T4.9c;
`qa-reviewer` (sonnet, high; opus if it finds data problems) for the final result: acceptance criteria, the
merge transaction, Mac design (sheet, toolbar, Light/Dark), and one live run with the user in the Dev data folder
(tuttocampo read for every team with a widget id + one stored CSI list).

---

## T4.9a — Classifica parser and CSI team list

| | |
|---|---|
| **Agent / model** | `render-engineer` · sonnet · effort medium |
| **Depends on** | T4.9 Step 1 |
| **Size** | S |

**Features**

1. `TuttocampoWidgetSource.fetchLeagueTeams(for:settings:)`, exactly as documented on `FixtureSource`:
   - one GET of `https://www.tuttocampo.it/WidgetV2/Classifica/<widget id>` through the existing T4.2 client
     (same allowlist, timeouts, size cap, no cookies, `User-Agent`, the same at-least-1-s spacing between
     requests as Risultati). `.missingWidgetID` when the team has none; the same `FixtureFetchError` mapping as
     `fetchFixtures`; `CancellationError` on cancel.
   - a pure parser in a new file (e.g. `TuttocampoClassificaParser.swift`) with SwiftSoup, no regular expressions
     on HTML: rows `table.table_ranking tbody tr`; name = text of `td.team > a`, trimmed, whitespace collapsed;
     logo = `td.team_logo > img` `src` (not `srcset`) made absolute against the page, `logoID` =
     `tuttocampoClubID(fromLogoURL:)` (may be `nil` with a `logoURL`).
   - ours left out: `tr.selected`, or the name equals `settings.clubShortName` under
     `searchKey(stripLegalPrefixes(_:))`. A table without our row is not an error.
   - a name seen twice once; `.structureChanged` for no table, no row or a row without a name.
2. `CSIPageParser.teams(html:pageURL:for:settings:)`, exactly as documented on `PageFixtureParser`: one parse;
   every side of the match list (`span.nome-squadra` with the side's `img`), deduplicated by the 8-digit id
   (`img alt`, else `csiTeamID(fromLogoURL:)`), else by name; first occurrence kept, page order. Standings: read
   them too only if the page marks their teams the same way; the sample's standings table does not, so say in
   the report what you did. Placeholder shield → `logoURL == nil` (and `logoID == nil`). Ours left out. A page
   that `parse` calls `.structureChanged` → `[]`. Share the row reading with `parse` rather than copy it.
3. Nothing in `Sources/SSImport/` imports SwiftUI, WebKit or AppKit.

**Acceptance**

- [ ] `classifica-normal.html`: 16 rows → 15 `SourceTeam` in table order, every name and ClubId checked
      (Alba Rossa → `900113`), `logoURL` the `Teams/40` address, Sergnanese (`tr.selected`) absent, every element
      `.tuttocampo` with the asking team's id.
- [ ] Variants built from the fixture as strings: no table → `.structureChanged`; `tbody` empty →
      `.structureChanged`; a row whose `td.team` has no name → `.structureChanged`; a row without `img` →
      `logoID == nil`, `logoURL == nil`; an unrecognised logo address → `logoID == nil` with the `logoURL`; our row
      without `selected` still left out by name ("ASD Sergnanese" too); our row missing → 16 teams; a name twice
      → once.
- [ ] Fetch on a `URLProtocol` stub (the T4.2 test helper): the Classifica URL is the one requested, a 404 →
      `.httpStatus(404)`, a redirect off the allowlist → `.notAllowed`; the stub fails the test on any other URL.
- [ ] `girone-sample.html`: exactly the three other teams once each (the 3× repetition deduplicated), in page
      order, the placeholder team with no logo, the other two with `logoID` `9000000x` and their logo address;
      `girone-no-table.html` → `[]`; `girone-no-ours.html` → every team of the page.
- [ ] Existing T4.2 and T4.8 parser tests unchanged and green; `Scripts/check.sh` passes.

---

## T4.9b — Data: stored team lists and the merge transaction

| | |
|---|---|
| **Agent / model** | `core-dev` · sonnet · effort medium |
| **Depends on** | T4.9 Step 1 |
| **Size** | M |

**Features**

1. A new migration (never edit an existing one): table `source_team_lists` (`team_id TEXT NOT NULL REFERENCES
   teams(id) ON DELETE CASCADE`, `source TEXT NOT NULL` (`TeamListSource` raw value), `read_at` (same date
   storage as the other tables), `teams TEXT NOT NULL` (JSON of `[SourceTeam]`), primary key
   `(team_id, source)`). Foreign keys are already on.
2. A `SourceTeamListRepository` on the database queue: `save` upserts the row of that team and source (one write
   transaction, `AppError.notFound` for an unknown team), `latest` returns it as `SourceTeamList` or `nil`.
   A row whose JSON cannot be decoded reads as `nil` (never a crash) and is overwritten by the next save.
   Deleting a team removes its rows (the cascade; `TeamRepository.delete` keeps refusing a team with matches).
3. `applyImport(_:)` on the opponent repository, exactly as documented on `OpponentRepository`: one
   `write` transaction; for each item, `.create` → `action.draft(current: nil)` validated and inserted;
   `.update` → read the current row, `action.draft(current:)`, `validated()`, update name and aliases only (short
   name and logo untouched). Any error rolls the whole transaction back and is rethrown as `AppError`. Returns
   the stored opponents in item order. Opponent ids, matches and logo files never change.

**Acceptance**

- [ ] Migration test: a database file created by the previous schema opens, keeps its teams, opponents and
      matches; the new table is empty; opening again changes nothing.
- [ ] Team lists: save then latest round-trips every field (names with accents and apostrophes, `nil` logos, URLs
      with queries); a second save for the same team and source replaces the first; tuttocampo and CSI lists of
      one team are separate; unknown team → `notFound` on both methods; deleting a team without matches deletes
      its lists; a corrupt JSON row reads as `nil`.
- [ ] `applyImport`: a create with aliases; a logo-only update leaves the row unchanged and is returned; a rename
      keeps id, short name, logo file and the matches' `opponent_id`, and the old name becomes an alias; aliases
      equal to the name or to each other (case, accents) are dropped.
- [ ] Rollback: a plan whose second item updates an unknown id → `AppError.notFound` and the first item's
      opponent is not in the database; a plan whose second item adds an 81-character alias → `.validation`, nothing
      written; a plan that renames to an 81-character name → nothing written.
- [ ] Existing repository, migration and seed tests unchanged and green; `Scripts/check.sh` passes.

---

## T4.9c — UI: "Scarica tutti gli avversari…", review sheet, report

| | |
|---|---|
| **Agent / model** | `ui-dev` · sonnet · effort medium (high only on retry) |
| **Depends on** | T4.9 Step 1 |
| **Size** | M |

Built and tested against `AppServices.fake()`: `FakeFixtureSource.scenario` answers the Classifica of every
team (table in its doc comment) and Pulcini's CSI list is stored. Italian strings in `OpponentsStrings`
(`AppStrings` only for the menu item); core messages (`ImportIssue.message`, `OpponentPlanError.message`) are
shown as they are. Standard controls, system font, semantic colours, Light and Dark Mode.

**Features**

1. **Command:** a toolbar button "Scarica tutti gli avversari…" in Avversari and the same item in the File menu
   after "Importa da CSI…" (no shortcut), published by Avversari as a focused action. Disabled, with the reason as
   help text, while no active team has a widget id or a CSI page.
2. **Reading:** a sheet with a determinate progress ("Lettura di <squadra>…", n of m) and Annulla, which cancels
   the task. For each active team in `sortOrder`: with a widget id, `services.fixtureSource.fetchLeagueTeams`
   (`.structureChanged` → `.standingsChanged`; `FixtureFetchError` → `.standingsReadFailed`); with a CSI page,
   `services.sourceTeamLists.latest(teamID:source: .csi)` (`nil` → `.csiTeamListMissing`). No other request.
   One failing team never stops the others.
3. **Review sheet** (same staging style as T4.2c, not a copy of its code): rows from
   `OpponentCandidate.make(found:existing: opponents.list(), clubShortName: settings.clubShortName)`:
   - columns: tick, name, state ("Nuovo", "Già presente, senza logo", "Già presente", "Possibile duplicato"),
     where it was seen (one line per sighting: "Tuttocampo · <squadra>", "CSI · <squadra>, letto il <data>" with
     the `readAt` of the stored list), logo;
   - ticks start at `isTickedByDefault`; `.present` rows are greyed and cannot be ticked;
   - logo column: the existing opponent's local logo when it has one; otherwise a symbol for "logo disponibile"
     (the row has `logo`) or "nessun logo". **No image is downloaded before "Salva"** (see "Ambiguity resolved");
   - pairs from `OpponentCandidate.possibleDuplicatePairs(in:existing:)`, shown under the rows they belong to (or
     in a "Possibili duplicati" section), each with three choices "Usa «firstName»" / "Usa «secondName»" / "Tieni
     separati" and no default. A pair whose new row(s) are unticked needs no choice;
   - "Salva" is enabled only when `OpponentImportPlan.make(candidates:ticked:pairs:choices:)` succeeds and has at
     least one item; otherwise the `OpponentPlanError.message` is shown above the buttons;
   - the report lines of the reading (step 2) are shown at the top of the sheet.
4. **Save:** `services.opponents.applyImport(plan)` (on error: an alert with the `AppError` message, nothing else
   happens), then logos, for each `(item, opponent)` with `item.logo != nil` and `opponent.logoFile == nil`:
   - tuttocampo: `LogoRequest(opponent:sourceTeam:)` → `services.fixtureSource.downloadLogos`;
   - CSI: `CSILogoRequest(opponent:sourceTeam:)` (`nil` → `.csiLogoUnavailable`) → the T4.8c
     `CSILogoDownloader` (reuse it from `Features/Import/CSIBrowser/`, do not edit it) only when
     `CSIBrowserController.allowsDirectLogoDownload` is on, else `.csiLogoUnavailable` → `storeCSILogos(_:in:)`;
   - for each stored file name, `opponents.update` with the logo (re-read the opponent first; if it got a logo
     meanwhile, leave it and remove the downloaded file unless another opponent uses it).
5. **Report:** opponents created, renamed, aliases added, logos stored; then every `ImportIssue` (reading and
   logos) with `message`, errors first. Closing the report reloads the Avversari list.
6. **CSI hook** in `ImportModel.readCSIPage()`: when `parse` gives a non-empty `.fixtures`, also call
   `services.csiPageParser.teams(html:pageURL:for:settings:)` off the main actor on the same HTML and, when the
   result is not empty, `services.sourceTeamLists.save(teamID:source: .csi, teams:readAt: Date())`. A failure is
   logged (`Log.imports`, team name only) and never changes the match import.

**Acceptance**

- [ ] View-model tests on `AppServices.fake()`: the rows and states of the scenario (Aurora Pianengo seen twice;
      Borgo Lucente and Atletico Montesello "senza logo"; "Real Fontanile"/"Real Fontanile B" and "Valdorso 2016"/F.C.
      Valdorso pairs); the report lines for Giovanissimi U15 (`.standingsChanged`) and Esordienti (network);
      a CSI team without a stored list gives `.csiTeamListMissing` (empty `FakeSourceTeamListRepository`).
- [ ] "Salva" disabled until both pairs have a choice and with a conflicting set of choices; enabled once resolved;
      unticking "Real Fontanile B" removes the need for that pair's choice.
- [ ] Saving with "Usa «Real Fontanile»" and "Usa «F.C. Valdorso»": four opponents created, Real Fontanile with
      alias "Real Fontanile B", F.C. Valdorso gains alias "Valdorso 2016"; logos stored for Pol. Borgo Lucente
      (`900301.png`), Real Fontanile (`900302.png`), Aurora Pianengo, Atletico Montesello (`csi-90000104.png`, with a
      stub downloader), Polisportiva Fontanella; Atletico Nuovo Borgo reported "non riconosciuto"; no logo already
      present is replaced.
- [ ] Cancelling during the reading writes nothing; nothing is written before "Salva".
- [ ] CSI hook: after "Importa questa pagina" on Pulcini's fake page, `sourceTeamLists.latest` holds
      `FakePageFixtureParser.scenarioTeams`; a page that is "not a CSI girone" stores nothing.
- [ ] Screens checked in Light and Dark Mode; standard controls only; the command is disabled without sources.
- [ ] `Scripts/check.sh` passes.

---

## Step 3 — Wiring and integration test

| | |
|---|---|
| **Agent / model** | `core-dev` · sonnet · effort medium |
| **Depends on** | T4.9a, T4.9b, T4.9c merged |
| **Size** | S |

**Features**

1. `Composition.makeServices` passes `sourceTeamLists:` the SSData repository (the fixture source and the CSI
   parser are already wired). Log each download outcome under `Log.imports` (counts and team names only).
2. `Tests/IntegrationTests/OpponentDownloadTests.swift` in a temporary `SS_DATA_DIR` with the real database,
   `LogoFileStore`, `TuttocampoWidgetSource` on a `URLProtocol` stub and `CSIPageParser`:
   `classifica-normal.html` served for the Classifica URL, a PNG for `Teams/200/<ClubId>.png`;
   `CSIPageParser.teams` on `girone-sample.html` saved with `sourceTeamLists.save`; then `fetchLeagueTeams` +
   `latest` → `OpponentCandidate.make` → `possibleDuplicatePairs` → choices → `OpponentImportPlan.make` →
   `applyImport` → `downloadLogos` → `opponents.update`. Assert the opponents and aliases in the database, the
   logo files in `logos/`, an existing opponent's logo untouched, and that the stub saw no request to a CSI host.
3. `01-architecture.md`: §7 lists `SourceTeamListRepository` and the new methods; §8 notes that the download
   makes only the tuttocampo Classifica and logo requests and none to CSI.

**Acceptance**

- [ ] The integration test passes without network; `Scripts/check.sh` passes.
- [ ] A Dev build (`Scripts/run.sh`) shows the command enabled with the real sources (checked in the live run).

---

## Ambiguity resolved in Step 1 (tell the user)

- **Thumbnails:** the plan asks for "a logo thumbnail when the source has one", but also "requests: one per
  tuttocampo team, then the logos actually missing; no CSI request at all". A remote thumbnail would add one
  request per row (and CSI-host requests), so the review sheet shows a "logo disponibile" symbol instead and
  downloads nothing before "Salva". Change it here if the user prefers remote thumbnails.
- **Merge choices** are resolved as groups: each "Usa «X»" joins both names, the name not chosen is set aside;
  a group must end with exactly one name never set aside, at most one existing opponent, and no "Tieni separati"
  pair inside it. Otherwise "Salva" stays disabled with `OpponentPlanError.conflictingChoices`.
- **Several opponents match one name** (shared alias): the row is "Già presente" and nothing is written for it.
- **A name longer than 80 characters** is cut with `truncateAtWord` before it becomes a row, so the transaction
  never fails on length; the row id is the key of the cut name.
