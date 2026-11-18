# 01 — Architecture

This file is the technical reference for every task. Wave 0 turns the contracts below into real code in `Sources/SSCore/`. After Wave 0 that folder is **frozen**: no task may change it without going back through the `foundation-architect` agent.

How the app looks and behaves (window, menus, shortcuts) is in `03-mac-design.md`.

## 1. Stack

| Layer | Choice | Notes |
|---|---|---|
| Language | Swift 6 language mode (strict concurrency) | `swift-tools-version: 6.0`, so the package also builds on a GitHub runner with an older toolchain than the user's Mac. |
| Build | Swift Package Manager only | No Xcode project. The Mac has the Command Line Tools, not Xcode. |
| UI | SwiftUI, with AppKit where SwiftUI has no API (sharing picker, drag promises, Quick Look panel) | `@Observable` view models. No third-party UI library. |
| Database | SQLite through **GRDB** | SwiftData needs Xcode's macro plugin and does not build here. |
| Templating | **swift-mustache** (logic-less Mustache) | Safe for user-supplied templates. No helpers: every value a template shows is computed by the app. |
| Zip | **ZIPFoundation** | For template import, with per-entry checks. |
| Rendering | Off-screen `WKWebView` + `takeSnapshot`, redrawn into an sRGB bitmap of exactly width×height pixels | The system web engine; nothing to bundle. |
| Fonts | Barlow and Barlow Condensed files (SIL Open Font License) inside each template's `assets/fonts/` | No Google Fonts request at render time. The app UI uses the system font. |
| Tests | Swift Testing, run by `swift test` | UI is tested through view models. There are no XCUITest tests (they need Xcode). |
| Packaging | `Scripts/package_app.sh` → `.app` → ad-hoc `codesign` → `.dmg` with `hdiutil` | Built by GitHub Actions on a macOS runner, published to GitHub Releases. Apple silicon only. |

Deployment target: macOS 15. Dependencies are pinned to exact versions in `Package.swift` by T0.1 and never bumped inside a feature task.

Concurrency rules, so six agents write compatible code:

- Models are `Sendable`, `Codable`, `Equatable` structs.
- Repository protocols are `Sendable` with **synchronous throwing** methods. The data is tiny and GRDB's queue is thread-safe.
- Anything that touches `WKWebView` or views is `@MainActor`. View models are `@MainActor @Observable final class`.
- No `@unchecked Sendable`, no `nonisolated(unsafe)`, without a comment explaining why it is safe.

## 2. Repository layout and ownership

Ownership means: only the listed task may create or edit files there during its wave. This is what makes parallel work safe.

```
.
├── CLAUDE.md                          T0.0
├── .claude/agents/                    T0.0 (copied from docs/plan/agents)
├── .claude/skills/, .agents/, skills-lock.json   T0.0 (commits the three macOS skills so worktree agents get them)
├── Package.swift, Package.resolved    T0.1 defines every target and dependency for v0.1.0; later only the orchestrator edits it
├── version.env                        T0.1 (APP_NAME, BUNDLE_ID, VERSION, BUILD); T3.4 bumps the version
├── .swift-format                      T0.1
├── Scripts/
│   ├── check.sh                       T0.1  build with warnings as errors + format lint + tests
│   ├── run.sh                         T0.1  build, assemble a debug .app, launch it (arguments passed through)
│   └── package_app.sh                 T0.1 (debug bundle), T1.5 (release, signing, dmg)
├── Packaging/                         T0.1 (Info.plist template), T1.5 (icon, dmg layout)
├── .github/workflows/                 T1.5
├── Sources/
│   ├── SSCore/                        T0.2 — FROZEN after Wave 0
│   │   ├── Models.swift               entities
│   │   ├── Validation.swift           input validation, one error type
│   │   ├── Repositories.swift         repository protocols
│   │   ├── Services.swift             TemplateStore, RenderService, LogoStore, DemoDataLoader, AppServices
│   │   ├── RenderContext.swift        data handed to templates
│   │   ├── TemplateManifest.swift     manifest schema
│   │   ├── Text.swift                 truncate / prefix-strip / slug / initials / dates (pure functions)
│   │   ├── AppPaths.swift             data, logos, templates, output, resources folders
│   │   ├── Warnings.swift, CoreStrings.swift   RenderWarning + matchWarnings; Italian messages
│   │   └── SSCore.docc/README.md      freeze rule, how to request a change, deviations from this file
│   │                                  (inside a DocC catalog: SwiftPM rejects a bare README.md in a target)
│   ├── SSCoreFakes/                   T0.2 — FROZEN. In-memory repositories, fake render service, fixture loader
│   ├── SSData/                        T1.1 (GRDB)
│   ├── SSTemplates/                   T1.3 (template store, zip install, validation)
│   ├── SSRender/                      T1.3 (context building, planning, WKWebView renderer)
│   ├── SSSeed/                        T1.4
│   ├── SSApp/                         all SwiftUI code (library target)
│   │   ├── Shell/                     T1.6 (App, scenes, sidebar, menus, navigation state)
│   │   ├── Components/                T1.6
│   │   ├── Strings/                   T1.6 (shared Italian strings)
│   │   └── Features/
│   │       ├── Matches/               T1.6 placeholder → T2.1
│   │       ├── Opponents/             T1.6 placeholder → T2.2
│   │       ├── Teams/                 T1.6 placeholder → T2.2
│   │       ├── Settings/              T1.6 placeholder → T2.3
│   │       ├── Templates/             T1.6 placeholder → T2.4
│   │       ├── Generate/              T1.6 placeholder → T2.5
│   │       └── Archive/               T1.6 placeholder → T2.5
│   ├── SergnaneseSocial/              the app executable
│   │   ├── main.swift                 T0.1 (skeleton), T1.6 (starts the shell with fakes), T3.1 (final)
│   │   ├── Composition.swift          T0.1 (stub), T3.1 (real services)
│   │   └── Smoke.swift                T0.1 (stub), T1.5 (minimal), T3.1 (real engine)
│   └── ss-tool/                       command-line helper for agents and CI
│       ├── main.swift                 T0.1 (subcommand table; never edited later)
│       ├── Preview.swift              T0.1 (stub), T1.2
│       ├── DemoRender.swift           T0.1 (stub), T1.3
│       ├── Screenshots.swift          T0.1 (stub), T1.6
│       └── Seed.swift                 T0.1 (stub), T3.1
├── Resources/                         plain folders copied into the app bundle by package_app.sh
│   ├── Fixtures/                      T0.2 (sample RenderContext JSON)
│   ├── Templates/                     T1.2 (the 4 converted templates)
│   └── Seed/                          T1.4
├── Tests/
│   ├── SSCoreTests/                   T0.2
│   ├── SSDataTests/                   T1.1
│   ├── SSTemplatesTests/, SSRenderTests/   T1.3
│   ├── SSSeedTests/                   T1.4
│   ├── SSAppTests/<Feature>/          the task that owns the feature; Shell/ and Components/ are T1.6
│   └── IntegrationTests/              T3.1
├── README.md                          T3.3
└── docs/                              plan (this folder), INSTALL.md (T1.5), USER-GUIDE.md + TEMPLATES.md (T3.3), qa/ (qa-reviewer)
```

Stub files: T0.1 creates each file marked "(stub)" with a function that prints `not implemented yet (Txx)`. The later task replaces its own file. Nobody edits a shared entry point to register their work.

**Resources are not loaded with `Bundle.module`.** SwiftPM's generated accessor falls back to an absolute path inside `.build`, which works on the build machine and fails on every other Mac. `AppPaths.resources` resolves, in order: the `SS_RESOURCES_DIR` environment variable, `Bundle.main.resourceURL` (packaged app), the repo's `Resources/` folder (when run by `swift run` or `swift test`).

Runtime data lives **outside the repo**:

```
~/Library/Application Support/Sergnanese Social/         release builds
~/Library/Application Support/Sergnanese Social Dev/     debug builds and scripts (never the user's real data)
    db.sqlite            database
    backups/             automatic database backups
    logos/               opponent logos (never committed: other clubs' trademarks, public repo)
    templates/           installed templates (built-ins are copied here on first run)
```

`SS_DATA_DIR` overrides the folder; every test uses a temporary one.

Generated images go to `~/Pictures/Sergnanese Social/<YYYY-MM-DD>/` by default; the folder is a setting, chosen with the system folder picker.

## 3. Data model

```swift
typealias EntityID = String              // UUID string; not `ID`, which would shadow Identifiable.ID
// The code in SSCore is the reference: Sources/SSCore/SSCore.docc/README.md lists where it differs from
// the sketch below (drafts, RenderRecord.date, SideContext.halfTimeScore, MatchContext.hasScore, …).

struct DayDate   { let value: String }   // "YYYY-MM-DD", validated; Comparable. No time zone involved.
struct ClockTime { let value: String }   // "15:30", validated; Comparable

struct Team {                            // one of OUR teams
  var id: EntityID; var name: String           // "Prima Squadra", "Juniores", "Under 15"
  var shortLabel: String                 // label used in programme rows
  var sortOrder: Int; var isFirstTeam: Bool; var isActive: Bool
}

struct Opponent {
  var id: EntityID; var name: String           // full official name
  var shortName: String?                 // manual override for display
  var aliases: [String]                  // name variants (used by imports in Wave 4)
  var logoFile: String?                  // file name inside the logos folder
}

enum MatchStatus: String { case scheduled, postponed, cancelled, played }
enum MatchSource: String { case manual, seed, csv, scrape, pdf }
struct Score { var us: Int; var them: Int }

struct Match {
  var id: EntityID; var teamID: EntityID; var opponentID: EntityID
  var date: DayDate; var time: ClockTime?
  var isHome: Bool; var venue: String
  var competition: String?; var round: Int?        // "Giornata N"
  var status: MatchStatus
  var score: Score?; var halfTime: Score?
  var notes: String?                               // scorers / free text
  var source: MatchSource; var isLocked: Bool      // locked rows are never overwritten by imports
  var createdAt: Date; var updatedAt: Date
}

struct MatchDetail { var match: Match; var team: Team; var opponent: Opponent }   // what lists show

struct ClubSettings {
  var clubName: String; var clubShortName: String  // "ASD Sergnanese", "Sergnanese"
  var season: String                               // "2026/27"
  var accentColor: String                          // "#CF3326" — used by templates, not by the app's own UI
  var socialHandle: String; var homeVenue: String
  var outputFolder: String?                        // nil = default Pictures folder
}

struct RenderRecord {
  var id: EntityID; var templateID: String; var templateVersion: String
  var matchIDs: [EntityID]; var page: PageInfo?          // PageInfo { index, total }
  var file: String; var width: Int; var height: Int
  var warnings: [String]; var createdAt: Date
}
```

SQLite tables mirror these: `teams`, `opponents`, `matches`, `settings` (key/value), `renders`. Arrays and small structs are stored as JSON text. Foreign keys are on. Deleting a team or opponent that has matches is refused with a typed error.

## 4. Template format

A template is a folder (imported as a folder or a `.zip`):

```
post-prematch/
├── manifest.json
├── template.html        Mustache; one root element of exactly width×height px
└── assets/              images, fonts, css, js
```

```jsonc
// manifest.json
{
  "id": "post-prematch",
  "name": "Post · Pre-partita",
  "version": "1.0.0",
  "format": "post",                 // "post" | "story"
  "width": 1080, "height": 1350,
  "kind": "single",                 // "single" = one match per image, "list" = many matches per image
  "purpose": "prematch",            // "prematch" | "programme" | "halftime" | "fulltime" | "other"
  "pageSize": null,                 // list only: rows per image (programme = 10)
  "requires": ["time", "venue"],    // match fields that must be present, else a warning
  "limits": {                       // longest text the layout can hold, in characters
    "teamName": 16,
    "venue": 14,
    "category": 22
  }
}
```

Rules:

- **Network is blocked during render.** Everything a template needs is inside its folder and referenced with relative paths (`assets/...`). This makes output identical on every Mac.
- **Mustache has no helpers.** The app applies the manifest's `limits` while it builds the context, so the template only prints values: `{{opponent.displayName}}` is already truncated. Upper-casing stays in CSS (`text-transform`), as in the design exports. Conditionals use sections: `{{#opponent.logo}}…{{/opponent.logo}}` and `{{^opponent.logo}}…{{/opponent.logo}}`.
- Template JavaScript may run; the renderer waits for fonts, images and an optional `window.__ready` promise.
- Imports are validated: manifest schema, root size, no path traversal or symlinks in the zip, size limit 20 MB, at most 200 files, allowed file types only.

### Converting the four demo templates

`template-demo/*.zip` are design exports: an `<x-dc>` block with inline styles, `[Bracket]` placeholders, an `{{accent}}` variable, a React runtime (`support.js`, `vendor/`) and a Google Fonts link. Conversion (T1.2) keeps the markup and styles and:

- drops the runtime scripts and the `<x-dc>`/`<helmet>` wrappers;
- replaces Google Fonts with `@font-face` rules for Barlow files in `assets/fonts/`;
- replaces `[Bracket]` text with Mustache fields from the RenderContext;
- turns the ten copy-pasted programme rows into one `{{#rows}}` block;
- replaces the dashed "LOGO" circle with the opponent logo, falling back to an initials circle;
- makes left/right follow home/away instead of always putting Sergnanese on the left.

## 5. RenderContext — the data a template receives

```swift
struct ClubContext { name, shortName, logo, accent, season, handle: String }

struct SideContext {
  name: String; displayName: String      // displayName is already cut to limits.teamName
  logo: String?; initials: String        // logo = relative URL the template can use in <img src>
  isUs: Bool; score: Int?
}

struct MatchContext {
  category: String                       // our team's name, cut to limits.category
  round: Int?; competition: String?
  dateLong: String                       // "Domenica 22 novembre"
  dateShort: String                      // "Dom 22 nov"
  time: String?; venue: String           // venue is cut to limits.venue
  isHome: Bool; isAway: Bool
  home: SideContext; away: SideContext   // in fixture order
  us: SideContext; opponent: SideContext // the same two, by role
  halfTime: Score?; notes: String?
  isPostponed: Bool; isCancelled: Bool
}

struct SingleContext { club: ClubContext; match: MatchContext }

struct ListContext {
  club: ClubContext
  title: String                          // "Oggi in campo" / "Weekend in campo"
  dateLabel: String                      // one day or a range
  rows: [MatchContext]                   // already sliced to pageSize
  page: PageInfo; hasPages: Bool         // hasPages = total > 1
  pageLabel: String                      // "1/3"
}
```

Contexts are `Encodable`; the renderer turns them into the dictionary Mustache needs. Optional values that are `nil` are simply absent, so `{{#time}}`/`{{^time}}` sections work.

### Name display rule (decision D5)

`displayName` is computed once, in `SSCore/Text.swift`:

1. If the opponent has a `shortName`, use it.
2. Otherwise strip common legal prefixes (`A.S.D.`, `ASD`, `U.S.`, `U.S.D.`, `G.S.`, `F.C.`, `A.C.`, `S.S.D.`, `Pol.`, `Polisportiva`). Words that identify the club, such as `Oratorio`, are kept.
3. Cut to the template's `limits.teamName` at a word boundary and append `…`.
4. Every cut produces a warning shown in the Generate screen, with a button to set a short name.

## 6. Render pipeline

```
select matches + template
  → build RenderContext(s)            (list templates: sort by date/time, paginate by pageSize; apply limits)
  → render template.html with Mustache
  → off-screen WKWebView, light appearance forced, non-persistent data store
      · page and assets served by a custom URL scheme limited to the template folder and the logos folder
      · a content rule list blocks every http/https/ws request
  → wait: document.fonts.ready, all <img> decoded, window.__ready if present (10 s timeout)
  → takeSnapshot of the root rect
  → redraw into an sRGB bitmap of exactly width × height pixels → PNG
  → check the PNG's pixel size; save file; insert RenderRecord; return warnings
```

The web view lives in a borderless window placed off screen; the app never shows it and it never takes focus.

Output file names:

```
<outputFolder>/<match date>/<date>_<template id>_<team slug>_vs_<opponent slug>.png      single
<outputFolder>/<first date>/<date>_<template id>_<page>of<total>.png                     list
```

Hard requirements:

- Every PNG is **exactly** `width × height` pixels, whatever the display scale.
- Colours are sRGB: a block filled with `#CF3326` reads back as `#CF3326`.
- The Mac's Dark Mode, accent colour and Increase Contrast settings do not change the image.

## 7. Services (the contract between UI and engine)

There is no HTTP API. The UI calls Swift protocols defined in `SSCore/Services.swift`; `AppServices` is the one container handed to the UI.

```swift
struct AppServices {
  var teams: any TeamRepository
  var opponents: any OpponentRepository
  var matches: any MatchRepository
  var settings: any SettingsRepository
  var renders: any RenderRepository
  var logos: any LogoStore
  var templates: any TemplateStore
  var renderer: any RenderService
  var demoData: any DemoDataLoader
  var paths: AppPaths
}
```

| Protocol | Methods | Implemented by |
|---|---|---|
| `TeamRepository`, `OpponentRepository` | `list`, `get`, `create`, `update`, `delete` (refused when matches exist), `reorder` (teams), `search` (opponents) | T1.1 |
| `MatchRepository` | `list(from:to:teamID:)` → `[MatchDetail]`, `create`, `update`, `delete`, `duplicate(id:to:)`, `upsertFromImport` | T1.1 |
| `SettingsRepository` | `load`, `save` | T1.1 |
| `RenderRepository` | `list(from:to:)`, `insert`, `delete` | T1.1 |
| `LogoStore` | `importLogo(from: URL or image data)` → file name, `remove`, `url(for:)` | T1.1 |
| `TemplateStore` | `installBuiltins`, `list`, `get`, `install(from: URL, replace:)` → problems, `remove`, `restoreBuiltin` | T1.3 |
| `RenderService` (`@MainActor`) | `plan(request)` → `RenderPlan`, `render(request)` → `AsyncThrowingStream<RenderEvent>`, `preview(templateID:matchIDs:)` → temp PNG URL | T1.3 |
| `DemoDataLoader` | `load(today:)`, `hasDemoData` | T1.4 |

`SSCoreFakes` has an in-memory implementation of every protocol, filled from the fixtures. `AppServices.fake()` is what the UI runs on in Wave 1 and Wave 2 (`Scripts/run.sh --mock`) and in view-model tests.

Errors: one `AppError` enum (`validation(field, message)`, `conflict(message)`, `notFound`, `template(problems)`, `render(message)`, `io(message)`), with Italian messages for the user.

## 8. Security notes

- No network listener of any kind. The app makes no network request in v0.1.0 except opening the Releases page in the browser when the user asks.
- Template web views: custom scheme limited to two folders, all remote requests blocked, non-persistent store, no script message handlers (template JavaScript cannot call into the app).
- Template imports: reject absolute paths, `..` and symlinks; cap size and file count.
- Logos: SVG files are rasterised to PNG on import, so no script-bearing SVG is ever stored.
- The app is not sandboxed (it is not for the App Store) and asks for no privacy permission. If the user picks Desktop, Documents or an iCloud folder for output, macOS asks once for access; with ad-hoc signing it may ask again after an update.
- No secrets are needed by the app. Nothing private goes in the public repo.
