# SSCore — shared contracts (FROZEN)

Every task codes against this folder: models, validation, repository and service protocols, the render
context, the template manifest, paths and the pure text/date functions. `Sources/SSCoreFakes/` holds an
in-memory implementation of every protocol, and `Resources/Fixtures/` the data behind it.

## The freeze rule

After Wave 0, **nobody edits `Sources/SSCore/`, `Sources/SSCoreFakes/` or `Resources/Fixtures/`**
except the `foundation-architect` agent. Six agents build on these files in parallel; a change here
can break all of them at once.

If a contract is wrong or missing something:

1. Stop. Do not work around it with a copy of the type, a cast or an extension that changes behaviour.
2. In your report, write what you need: the type or method, the exact signature you propose, which
   task needs it and why the existing contract is not enough.
3. The orchestrator sends the request to `foundation-architect`, which makes the change (backward
   compatible where possible), updates the fakes and tests, and lists every task and file affected.

Adding an `extension` with a private helper in your own target is fine, as long as it does not change
what the contract means.

## Rules the contracts follow

- `SSCore` imports only Foundation.
- Models are `Sendable`, `Codable`, `Equatable` structs. `TemplateManifest` is the exception: it is
  only `Encodable`, and it is decoded with `TemplateManifest.decode(from:)`, which checks every field.
- Repository protocols are `Sendable`, synchronous and throwing. Their inputs are drafts; they call
  `validated()` and throw `AppError` only.
- `RenderService` is `@MainActor` (it drives `WKWebView`). `LogoStore.importLogo` and
  `DemoDataLoader.load` are `async` so an implementation can hop to the main actor.
- User-facing messages produced here are Italian and live in `CoreStrings.swift`.

## Files

| File | Holds |
|---|---|
| `Models.swift` | `DayDate`, `ClockTime`, `Weekend`, `Team`, `Opponent`, `Match`, `MatchDetail`, `ClubSettings`, `PageInfo`, `RenderRecord`, drafts |
| `Validation.swift` | `AppError`, `ValidationField`, `FieldProblem`, `Validatable`, draft and settings rules, `normalizedHexColor`, `isValidSeason` |
| `Repositories.swift` | `TeamRepository`, `OpponentRepository`, `MatchRepository`, `SettingsRepository`, `RenderRepository` |
| `Services.swift` | `LogoStore`, `TemplateStore`, `RenderService` and its request/plan/event types, `DemoDataLoader`, `AppServices` |
| `Import.swift` | T4.2: `FixtureSource`, `FetchedFixture`, `FixtureFetch`, `FixtureHealthProblem`, `FixtureFetchError`, `LogoRequest`, `LogoResult`, `ImportIssue`, `ImportCandidate`, `opponentsMatching` |
| `Tuttocampo.swift` | T4.2: widget ids, ClubIds, `Teams/200` logo URLs, imported logo file names (pure functions) |
| `CSI.swift` | T4.8: CSI page addresses and keys, CSI team ids and logo file names, `CSIPageReadError`, `PageFixtureParser`, `CSILogoRequest`, `CSILogoData`, `CSILogoResult`, `PageLogoSource`, `storeCSILogos(_:in:)` |
| `OpponentDownload.swift` | T4.9: `TeamListSource`, `SourceTeam`, `SourceTeamList`, `LeagueTeamsFetch`, `OpponentCandidate`, `OpponentImportPlan` and the merge choices |
| `Season.swift` | T4.11: `SeasonScope`, `SeasonLimits`, `SeasonLength`, `SeasonProgress`, `SeasonFetch`, `MatchdayFailure`, `MatchdayProblem`, `SeasonPage`, `readSeason(scope:readPage:onProgress:)` (the shared season loop), `SeasonEstimate` |
| `PDFCalendar.swift` | T4.3: `PDFCalendar` (matchdays, clubs, our fixtures, byes, problems), `PDFCalendarError`, `PDFCalendarParser` |
| `Warnings.swift` | `RenderWarning`, `matchWarnings(for:teamNameLimit:)` |
| `RenderContext.swift` | `SingleContext`, `ListContext` and their parts, `TemplateURLs` |
| `TemplateManifest.swift` | `TemplateManifest`, its enums and limits, `isValidTemplateID`, `compareTemplateVersions` |
| `Text.swift` | `stripLegalPrefixes`, `truncateAtWord`, `displayName`, `initials`, `slug`, search, Italian dates, weekends, output file names |
| `AppPaths.swift` | data, logos, templates, backups, output and resources folders |
| `CoreStrings.swift` | Italian messages used above |

## Deviations from `docs/plan/01-architecture.md`

These are deliberate. They were made in T0.2 and the plan text still shows the earlier shape:

- `ID` is named `EntityID`, so it never shadows `Identifiable.ID`.
- `RenderRecord.date` was added (the match date, or the first date for list images), so Archivio can
  group by weekend.
- `SideContext.halfTimeScore` was added, so the half-time story can print scores in home/away order.
- `MatchContext.hasScore` and `hasHalfTime` were added. Templates wrap score blocks in
  `{{#match.hasScore}}`, because a section on the score itself hides a 0 (Mustache treats 0 as false).
- The first-team rule (exactly one first team) is part of `TeamRepository`, with the shared errors
  `AppError.firstTeamRequired` (field `.isFirstTeam`) and `AppError.firstTeamCannotBeDeleted`.
- This README lives in `SSCore.docc/` because SwiftPM rejects a bare `README.md` inside a target folder
  and `Package.swift` declares no excludes.
- Repositories take drafts (`create(_:)`, `update(id:with:)`) rather than whole entities.
- `RenderRequest` lists the templates to render, each with its own matches (`TemplateSelection`), so the
  default "programme for everyone, post for the first team" plan can be expressed and edited.
- `TemplateStore.install` returns `TemplateInstallOutcome` so the UI can tell an id clash from a broken template.
- T4.2 contract step (Wave 4, backward compatible): `Team.tuttocampoWidgetID` and `TeamDraft.tuttocampoWidgetID`
  (validated, field `.tuttocampoWidgetID`, unique per team via `AppError.widgetIDInUse(by:)`);
  `LogoStore.importLogo(data:fileName:replacing:)` with a default implementation;
  `AppServices.fixtureSource` (defaults to a source that answers `FixtureFetchError.unavailable`); the types in
  `Import.swift` and the functions in `Tuttocampo.swift`. `FixtureSource.fetchFixtures` takes the
  `ClubSettings` (club short name and season are parser input), and `downloadLogos` was added so the UI
  can fetch logos through `AppServices`. `tuttocampoLogoURL(clubID:)` returns `URL?` (nil for a
  malformed id) instead of `URL`.
- T4.8 contract step (Wave 4, backward compatible): `Team.csiPageURL` and `TeamDraft.csiPageURL` (normalised and
  validated, field `.csiPageURL`, `FieldLimits.csiPageURL`, one page per team by `csiPageKey` via
  `AppError.csiPageURLInUse(by:)`); `FetchedFixture.venue` (used by `ImportCandidate.make` for away drafts only);
  four CSI cases of `ImportIssue` and `ImportIssue.csiPage(team:outcome:clubShortName:)`;
  `isValidImportedLogoFileName` also accepts `csi-[a-z0-9-]{1,60}.png`; `AppServices.csiPageParser` (defaults to a
  parser that answers "not a CSI girone"); the types and functions in `CSI.swift`. `FixtureSource` is unchanged.
  `PageLogoSource` is not in `AppServices`: the CSI browser window is the logo source while it is open.
- T4.3 contract step (Wave 4, backward compatible): the types in `PDFCalendar.swift`; `AppServices.pdfCalendarParser`
  (defaults to a parser that throws `PDFCalendarError.unavailable`); `FetchedFixture.opponentAliases`, `competition`
  and `scheduleUnknown` (all defaulted, and optional in JSON); `FetchedFixture.newOpponentDraft` and
  `Opponent.draftAddingImportNames(of:)` for "Crea avversario" / "Collega a esistente…";
  `ImportCandidate.make(…, source:)` (default `.scrape`), which also finds the opponent through
  `opponentAliases`, fills an empty competition, and has the review reason `.scheduleUnknown`; five PDF cases of
  `ImportIssue` and `ImportIssue.pdfNotices(for:)`. Whether the team picked for a PDF is remembered per category
  is decided "no" (no stored setting).
- Added, because Wave 1–2 tasks need them: `MatchRepository.get`, `count(source:)` and
  `deleteAll(source:)`; `OpponentRepository.matchCounts`; `DemoDataLoader.remove`;
  `AppPaths.latestBackupDate`; and the pure helpers `matchWarnings`, `formatWeekend`,
  `renderFileName` and `textMatches`.
- T4.11 contract step (Wave 4, backward compatible): `FixtureSource.fetchSeason(for:settings:scope:onProgress:)` with a
  default implementation that throws `FixtureFetchError.unavailable`, so sources written before it still compile. The
  season loop (order, byes, stop rules, cancellation, progress) is the pure `readSeason`, shared by the fake and the
  real source, instead of being written twice. Beyond the plan's shape: `SeasonProgress.pagesRead`/`pagesTotal`
  (determinate bar, per-run cap), `SeasonFetch.currentMatchday`, `notYetAvailable` and `pagesRead` (estimate,
  report, request count), `MatchdayProblem.matchday` optional (a default page without a number), and a fourth issue
  `ImportIssue.seasonMatchdayChanged` for a matchday page read but not trusted.
