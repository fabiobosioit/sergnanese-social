# Wave 0 — Foundation (sequential)

Nothing in this wave runs in parallel: each task needs the one before it. The wave is small on purpose. Its output is what lets eleven later tasks run side by side.

**Gate to Wave 1:** T0.0–T0.2 merged into `main`, `Scripts/check.sh` green, `Scripts/run.sh` opens an empty app window with an Italian menu bar.

---

## T0.0 — Bootstrap Claude Code project files

| | |
|---|---|
| **Agent** | none — main session |
| **Model** | any (sonnet is fine; this is one command) |
| **Depends on** | plan merged into `main` |
| **Owns** | `CLAUDE.md`, `.claude/**`, `.agents/**`, `skills-lock.json`, first lines of `.gitignore` |
| **Size** | XS |

**Do**

```bash
mkdir -p .claude/agents
cp docs/plan/agents/*.md .claude/agents/
cp docs/plan/CLAUDE.template.md CLAUDE.md
printf '.DS_Store\n.build/\nbuild/\nout/\n*.sqlite\n' >> .gitignore
git add .gitignore .claude .agents skills-lock.json CLAUDE.md
git commit -m "T0.0: Claude Code agents, skills and project instructions"
```

`.claude/skills/` holds links into `.agents/skills/`. Both are committed together; committing only `.claude` would leave broken links in every worktree.

**Acceptance**

- [ ] The eight agents are listed by Claude Code (ask: "which subagents are available?").
- [ ] `CLAUDE.md` is at the repo root.
- [ ] In a fresh clone, `ls .claude/skills/macos-design-guidelines/SKILL.md` finds the file.
- [ ] `git status` no longer shows `.DS_Store`.

---

## T0.1 — Project scaffold and tooling

| | |
|---|---|
| **Agent** | `core-dev` |
| **Model** | sonnet · effort medium |
| **Depends on** | T0.0 |
| **Owns** | `Package.swift`, `Package.resolved`, `version.env`, `.swift-format`, `.gitignore`, `Scripts/**`, `Packaging/Info.plist`, `Sources/SergnaneseSocial/**`, `Sources/ss-tool/**`, a placeholder file in every other target folder, `Tests/SSCoreTests/ScaffoldTests.swift` |
| **Size** | M |

Start from the templates in the `macos-spm-app-packaging` skill (`assets/templates/bootstrap/`, `package_app.sh`, `compile_and_run.sh`) and adapt them.

**Features**

1. `Package.swift`, `swift-tools-version: 6.0`, platform macOS 15, Swift 6 language mode, **every target for v0.1.0 declared now** so no later task edits it:

   | Target | Kind | Depends on |
   |---|---|---|
   | `SSCore` | library | — |
   | `SSCoreFakes` | library | SSCore |
   | `SSData` | library | SSCore, GRDB |
   | `SSTemplates` | library | SSCore, ZIPFoundation |
   | `SSRender` | library | SSCore, SSTemplates, Mustache |
   | `SSSeed` | library | SSCore |
   | `SSApp` | library | SSCore, SSCoreFakes |
   | `SergnaneseSocial` | executable | all of the above |
   | `ss-tool` | executable | all of the above |
   | one test target per library, plus `IntegrationTests` | test | its library, SSCoreFakes |

2. Dependencies pinned with `exact:` — GRDB.swift 7.12.0, swift-mustache 2.1.1, ZIPFoundation 0.9.20 (the versions verified on this Mac). `Package.resolved` committed.
3. `version.env`: `APP_NAME="Sergnanese Social"`, `BUNDLE_ID=com.sergnanese.social`, `VERSION=0.0.1`, `BUILD=1`.
4. `Packaging/Info.plist` template with the keys listed in `05-macos-packaging.md`.
5. `Sources/SergnaneseSocial/main.swift`: a minimal SwiftUI app with one empty `Window` ("Sergnanese Social") and the default menus. With `--smoke` it calls `runSmoke()` from `Smoke.swift` and exits with its result. `Composition.swift` and `Smoke.swift` are stubs.
6. `Sources/ss-tool/main.swift`: a subcommand table (`preview`, `demo-render`, `screenshots`, `seed`) dispatching to one function per file. Each file is a stub that prints `not implemented yet (Txx)` and exits 0. Later tasks replace their own file and never edit `main.swift`.
7. `Scripts/check.sh`: `swift build -Xswiftc -warnings-as-errors`, `swift format lint --strict --recursive Sources Tests`, `swift test`. Exits non-zero on any failure.
8. `Scripts/package_app.sh [debug|release]`: builds, assembles `build/Sergnanese Social.app` (binary, `Info.plist` filled from `version.env`, `Resources/` folders copied, an `it.lproj` folder so macOS treats the app as Italian), ad-hoc signs it. The `release` extras (icon, dmg) are added by T1.5.
9. `Scripts/run.sh [args]`: `package_app.sh debug`, then launches the bundle, passing arguments through (`--mock`, `--smoke`).
10. `.swift-format` with the project style (2-space indent, 120 columns).
11. `.gitignore` additions: `.build/`, `build/`, `out/`, `*.sqlite`, `.swiftpm/`.
12. One trivial Swift Testing test so `Scripts/check.sh` is meaningful.

**Acceptance**

- [ ] `Scripts/check.sh` passes on a clean clone with only the Command Line Tools installed.
- [ ] `Scripts/run.sh` opens a window; the menu bar shows the app name and the standard menus **in Italian** ("Modifica", "Finestra").
- [ ] `swift run ss-tool preview` prints the "not implemented yet (T1.2)" line and exits 0.
- [ ] `codesign -dv "build/Sergnanese Social.app"` reports an ad-hoc signature and the bundle id `com.sergnanese.social`.
- [ ] Exact dependency versions are in `Package.swift` and `Package.resolved`.

---

## T0.2 — Shared contracts

| | |
|---|---|
| **Agent** | `foundation-architect` |
| **Model** | opus · effort high |
| **Depends on** | T0.1 |
| **Owns** | `Sources/SSCore/**`, `Sources/SSCoreFakes/**`, `Resources/Fixtures/**`, `Tests/SSCoreTests/**` |
| **Size** | M–L |

Opus is used here because every other task codes against these files. A gap found in Wave 2 would stall five agents at once.

**Features**

1. `Models.swift`: the entities of `01-architecture.md` §3 as `Sendable`, `Codable`, `Equatable`, `Identifiable` structs, with `DayDate` and `ClockTime` as validated value types, plus draft types for create/update (`MatchDraft`, `OpponentDraft`, `TeamDraft`).
2. `Validation.swift`: `validate()` on each draft returning field-level problems in Italian; the single `AppError` enum of §7.
3. `Repositories.swift`: the repository protocols of §7 with their exact method signatures, including `matches.list(from:to:teamID:)` and the "has matches" delete guard.
4. `Services.swift`: `TemplateStore`, `RenderService` (with `RenderRequest`, `RenderPlan`, `PlannedImage`, `RenderWarning`, `RenderEvent`), `LogoStore`, `DemoDataLoader`, and the `AppServices` container.
5. `RenderContext.swift`: `SingleContext`, `ListContext` and their parts (§5), `Encodable`.
6. `TemplateManifest.swift`: the manifest of §4, decoded from JSON with a readable Italian problem for each invalid field.
7. `AppPaths.swift`: data folder (release / Dev / `SS_DATA_DIR`), `db.sqlite`, `backups/`, `logos/`, `templates/`, default output folder in Pictures, and the resources lookup order of §2. Creates folders on first use.
8. `Text.swift`, implemented and unit-tested here because three tasks need it:
   - `stripLegalPrefixes(_:)`, `truncateAtWord(_:max:)` → text + whether it was cut,
   - `displayName(for:limit:)`, `initials(_:)`, `slug(_:)`,
   - `formatDateLong/Short(_:)` in Italian, `weekend(containing:)` → Saturday…Sunday, `nextWeekend(from:)`.
9. `SSCoreFakes`: an in-memory implementation of every protocol; a fake `RenderService` that "renders" by writing a flat-colour PNG of the right size after a short delay and reports progress; `AppServices.fake()` pre-filled from the fixtures.
10. `Resources/Fixtures/`: `single.context.json`, `list.context.json` (10 rows), `list-23.context.json` (23 rows, for pagination), a `matches.json` data set behind the fakes. One opponent has a 45-character name, one has no logo, one match is away, one has no time.
11. `README.md` in `Sources/SSCore/` explaining the freeze rule and how to request a change.

**Acceptance**

- [ ] Every entity in §3 and every protocol in §7 exists with the documented shape.
- [ ] Fixtures decode into the context and model types (test).
- [ ] `Text.swift` has tests for: prefixes, word-boundary truncation, names shorter than the limit, accented characters, empty input, weekend maths across a month and a year boundary.
- [ ] `SSCore` imports only Foundation. No third-party dependency.
- [ ] The whole package compiles under Swift 6 strict concurrency with no warnings.
- [ ] `Scripts/check.sh` passes.
- [ ] `qa-reviewer` confirms the contracts cover every Wave 1 and Wave 2 task (it reads the task files and looks for anything a task needs that the contracts lack).
