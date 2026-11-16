# Sergnanese Social

Native Mac app (Swift 6, SwiftUI, Swift Package Manager, no Xcode project) that generates Instagram/Facebook images for ASD Sergnanese's weekend matches from HTML templates.

## Read first

- `docs/plan/README.md` — scope and decisions
- `docs/plan/01-architecture.md` — stack, layout, contracts, template format
- `docs/plan/03-mac-design.md` — window, sidebar, menus, shortcuts, sharing (UI work)
- `docs/plan/tasks/` — the task you were given; read only that task's section

## Rules

- Code against `Sources/SSCore/`. That folder and `Sources/SSCoreFakes/` are frozen after Wave 0: do not edit them. If a contract is wrong, stop and report.
- Touch only the paths your task owns (table in `01-architecture.md` §2 and in the task sheet).
- Do not edit `Package.swift`. List the dependency or target you need in your report.
- This Mac has the Command Line Tools, not Xcode. Do not use SwiftData, `.xcstrings`, XCUITest, `xcodebuild` or `Bundle.module` resources.
- Swift 6 strict concurrency: no `@unchecked Sendable` or `nonisolated(unsafe)` without a comment saying why it is safe.
- Tests are part of the task (Swift Testing). `Scripts/check.sh` must pass before you finish.
- Commit messages start with the task id: `T1.3: render engine`.
- User-visible text is Italian and lives in a `Strings` file, never inline in views.
- UI uses standard SwiftUI controls, the system font, semantic colours and the system accent colour. It must work in Light and Dark Mode.
- Never touch the user's real data folder (`~/Library/Application Support/Sergnanese Social/`). Debug builds use `Sergnanese Social Dev`; tests set `SS_DATA_DIR` to a temp folder.
- The repo is public. Never commit real opponent logos, personal data or secrets.
- Templates render with the network blocked. Never add an external URL to a template.

## Commands

| Command | What it does |
|---|---|
| `Scripts/check.sh` | Build with warnings as errors, format lint, all tests |
| `Scripts/run.sh` | Build, assemble a debug app and launch it (Dev data folder) |
| `Scripts/run.sh --mock` | Launch the app on in-memory fake data |
| `swift run ss-tool seed` | Load fake matches for the coming weekends into the Dev data folder |
| `swift run ss-tool demo-render` | Render every template from the fixtures to `out/demo/` |
| `swift run ss-tool preview <template-folder> <fixture.json>` | Render one template to `out/preview/` |
| `swift run ss-tool screenshots` | Save a PNG of every screen, Light and Dark, to `out/screens/` |
| `Scripts/package_app.sh release` | Build the signed `.app` and the `.dmg` in `build/` |

## Agents

Defined in `.claude/agents/`. Models and roles: `docs/plan/02-agents-and-models.md`.
