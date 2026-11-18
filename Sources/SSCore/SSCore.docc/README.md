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
- Added, because Wave 1–2 tasks need them: `MatchRepository.get`, `count(source:)` and
  `deleteAll(source:)`; `OpponentRepository.matchCounts`; `DemoDataLoader.remove`;
  `AppPaths.latestBackupDate`; and the pure helpers `matchWarnings`, `formatWeekend`,
  `renderFileName` and `textMatches`.
