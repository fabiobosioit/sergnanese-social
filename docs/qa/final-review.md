# T3.5 Final review

- Commit reviewed: `main` at `eea5754` (tag `v0.1.0`), 2026-11-20.
- Reviewer: `qa-reviewer`, fresh context. This file is a report. It fixes nothing; each finding names an owner.
- Verdict: **approve. No blocking finding is open.** The v0.1.0 release exists and its `.dmg` is sound. Five things stay open before the release gate in `wave-3-release.md` can close. Four are non-blocking (F1–F4 below). The fifth is the user's by-hand checks: Gatekeeper, AirDrop, drag and drop, VoiceOver, Full Keyboard Access.

## What I ran

| Check | Result |
|---|---|
| `Scripts/check.sh` on `eea5754` (this Mac, macOS 27, CLT only) | **Pass** (`OK: all checks passed.`): build with warnings as errors, format lint, every test target including `IntegrationTests` |
| CI on `eea5754` (run 44830770668) | **Fail**: one timing flake, `WebRendererTests.neverReadyFailsWithAClearTimeout` (F2) |
| Release workflow on tag `v0.1.0` (run 44831164858) | **Pass**: tag matches `version.env`; `check.sh` green; package; smoke from a copied app with `.build` deleted printed `SMOKE OK`; release published |
| `gh release view v0.1.0` | Published, not a draft. One asset, `Sergnanese-Social-0.1.0.dmg` (7.4 MB, sha256 `71ac0caa…6053`). The notes contain only GitHub's generated text (F1) |
| Downloaded `.dmg`, mounted read-only | Holds `Sergnanese Social.app` and an `Applications` link. `codesign`: `Signature=adhoc`, `Identifier=com.sergnanese.social`, arm64 only. `codesign --verify --deep --strict` OK. `spctl`: rejected (expected for P6). Info.plist: version 0.1.0 (1), `LSMinimumSystemVersion 15.0`, `CFBundleDevelopmentRegion it`. Resources hold `Templates`, `Seed`, `Fixtures`, `it.lproj` and `AppIcon.icns`. No `.sqlite` or `.DS_Store` inside |
| Release binary `--smoke` on this Mac (copied from the `.dmg`) | `SMOKE OK`: seed 48 matches, 1080×1350, accent pixel `#CF3326` |
| `swift run ss-tool seed` (`SS_DATA_DIR` = temp) | 10 teams, 20 opponents, 48 matches |
| `swift run ss-tool demo-render` | Four PNGs at the exact sizes. I opened all four: home side left / first, safe zones kept (story content between y≈250 and y≈1645), no clipping. The `(C)`/`(T)` marker wraps under `CAMPO COMUNALE` in the programme, already accepted in `visual-report.md` (limits table) |
| `swift run ss-tool screenshots` | 18 PNGs. I opened Partite (Light and Dark), Genera (Dark), Archivio (Dark), Template (Light), Impostazioni (Dark), Avversari (Light), Squadre (Dark). Semantic colours and the system font in both modes. The T3.2 fixes show: badge 4, "Casa/Fuori" in full, "Luogo", "orario da definire" |
| User's data folders | `~/Library/Application Support/Sergnanese Social*` and `~/Pictures/Sergnanese Social*` do not exist before or after any of the runs above |

I did not run `ss-tool seed` against the release folder: the permission system refused, which is right. `WorkflowTests.seedRefusesTheReleaseFolderBeforeCreatingAnything` covers it through `SS_RELEASE_DATA_DIR`.

## Findings (most severe first; none blocking)

| ID | Where | What is wrong | Concrete case | Owner |
|---|---|---|---|---|
| F1 | `.github/workflows/release.yml:74` (`--generate-notes`) | The published release has no install steps and no change list. T3.4 feature 3 asks for "notes and the install steps". The body only lists PR #1 "Add v0.1.0 implementation plan" and "New Contributors". A volunteer who opens the Releases page is not told that the first launch needs "Apri comunque". | `gh release view v0.1.0 --json body` | `release-engineer`: run `gh release edit v0.1.0 --notes-file …` now (CHANGELOG 0.1.0 plus the "Primo avvio" section of `INSTALL.md`), and switch the workflow to `--notes-file` built from `CHANGELOG.md` for the next tag |
| F2 | `Tests/SSRenderTests/WebRendererTests.swift:177-191` | Timing flake. The test gives the renderer 1 s and expects the timeout to name `window.__ready`. On a loaded runner the page has not even loaded after 1 s, so the error names "la risposta del motore di rendering" instead. The tagged commit is red on CI, although the same commit was green in the Release run. T3.1's "green locally and on CI" is therefore not reliable. The product is not affected: the real timeout is 10 s and counts only time the renderer could run. | CI run 44830770668: `Caught error: render(message: "Il template non è pronto dopo 1 secondi. In attesa di: la risposta del motore di rendering.")` | `render-engineer`: wait for the navigation to finish before starting the 1 s budget, or accept either pending reason. Then re-run CI on `main` |
| F3 | `docs/INSTALL.md:3-4` | The file still says the Gatekeeper steps have not been checked on macOS 27. That banner ships with v0.1.0, so the first thing a new user reads is that the instructions may be wrong. T1.5 acceptance (correct the file after the user's check) is still open. | Open `INSTALL.md` from the README link | User installs from the browser, then `release-engineer` corrects the steps and removes the banner |
| F4 | `docs/qa/mac-review.md:222` "User findings" | U1–U5 are empty, so T3.2 acceptance ("the user has done the by-hand list") is not met. M1 (Return in Genera), M5 (a possible duplicate "Elimina"/"Trova"), M11 (multi-image drag) and every AirDrop/VoiceOver check depend on it. | Table rows U1–U5 blank | User, then `qa-reviewer` records the results |
| F5 | `docs/images/partite.png`, `docs/images/genera.png` (used by `README.md` and `USER-GUIDE.md`) | The screenshots predate the T3.2 UI fixes. They show the sidebar badge 7 (the app shows 4), the header "Casa/…", the column "Campo" (now "Luogo"), "—" for a missing time (now "orario da definire"), and the false name warning for "U.S. Castelverde Calcio" that M2 removed. | Compare with `out/screens/matches-light.png` and `generate-light.png` from `ss-tool screenshots` | `chore-runner`: regenerate and copy the screenshots |
| F6 | `docs/USER-GUIDE.md:92`, `:98`, `:79` | Three statements do not match the app. (a) "Condividi… (dal pulsante della barra …)": no toolbar button shares a *selection*. Genera's toolbar has "Condividi tutte" (all results), and Archivio has none (M6). (b) "Condividi tutte, nella sezione Risultato": the button is in the toolbar, not in the Risultato section. (c) Quick Look opens "a schermo intero": it opens the Quick Look panel. "Invio" also opens Quick Look only if M1 holds (U3). | Follow step 6 in Genera after a run | `chore-runner` |
| F7 | `.DS_Store` at the repository root | Tracked since `ce98e4f` ("2nd plan revision"), although `.gitignore` lists it. The content is harmless (Finder window bounds only). | `git ls-files \| grep DS_Store` | `chore-runner`: `git rm --cached .DS_Store` |
| F8 | `docs/plan/01-architecture.md:344` (§8) | It says the only network action is opening the Releases page. The app also opens the user guide and the template guide on github.com in the browser (`Sources/SSApp/Strings/AppStrings.swift:123`, `Sources/SSApp/Features/Templates/TemplatesStrings.swift:21`). The behaviour is fine (the browser does it, the app makes no request). Only the doc is out of date. | — | `foundation-architect` (plan text) |
| F9 | `docs/INSTALL.md` (Italian part) | Accents are written as apostrophes ("non e' notarizzata", "piu' recente"). It reads as careless to Italian users. | — | `release-engineer` |

Informational, no action needed:

- `Sources/SSCoreFakes/FakeRenderService.swift` changed after the freeze in `a2537ef` ("T0.2 fix"). The change is additive and for tests only (`beforeEachImage`, `waitUntilIdle`), and it is labelled as the owner's fix. No `SSCore` contract changed. `Package.swift` was never edited after T0.1.
- CI on `main` was red for most of 2026-11-18 while merges continued. The run before the tag (44828938841) was green.

## Decisions D1–D9 and P1–P8

| # | Status | Evidence |
|---|---|---|
| D1 no server | Pass | No `URLSession`, `NWListener` or `Network` import in `Sources/` |
| D2 manual entry, fake seed | Pass | Matches screen, `ss-tool seed`, "Carica dati demo" |
| D3 no import in v0.1.0 | Pass | No import code |
| D4 logos by hand, generated placeholders | Pass | `LogoWell`; `Resources/Seed/logos/crest-*.png` are initials on simple shapes (opened) |
| D5 truncation and short name | Pass | `Text.swift` `displayName`; warnings in Partite/Genera; tests `emptyAndTinyLimits`, `countsAccentedCharactersAsOne` |
| D6 downloadable from GitHub | Pass | Release `v0.1.0` with one `.dmg` |
| D7 review before render | Pass | Partite table plus inspector; warnings feed Genera |
| D8 Mac only, AirDrop/Share | Pass (source); **user** for AirDrop | `NSSharingServicePicker`, `ShareLink`; U2 |
| D9 Claude Code agents | Pass | `.claude/agents/` holds the 8 agents |
| P1 Swift/SwiftUI/SPM, no Xcode | Pass | `Package.swift` tools 6.0, Swift 6 mode; built with CLT only |
| P2 WKWebView off-screen | Pass | `Sources/SSRender/WebRenderer.swift` |
| P3 SQLite/GRDB in Application Support | Pass | `AppDatabase`; no GRDB import outside `SSData` |
| P4 template folders | Pass | `Resources/Templates/*/{manifest.json,template.html,assets}` |
| P5 Italian UI | Pass | Strings files, `it.lproj`, `CFBundleDevelopmentRegion it` |
| P6 ad-hoc, not notarized | Pass | `Signature=adhoc`; `spctl` rejects; first launch documented (F3) |
| P7 Apple silicon, macOS 15+ | Pass | `lipo`: arm64; `LSMinimumSystemVersion 15.0` |
| P8 `com.sergnanese.social` | Pass | Info.plist and `codesign` |

## Security notes (`01-architecture.md` §8)

| Note | Status | Evidence |
|---|---|---|
| No listener, no network request | Pass | See D1. See F8 for the doc wording |
| Template web view: scheme limited to two folders | Pass | `TemplateSchemeHandler.swift`: `resolve` refuses another host, `..`, hidden components and backslashes; `containedFile` resolves symlinks and checks the prefix. Test `filesOutsideTheTemplateFolderAreNotServed` |
| Remote requests blocked | Pass | `WKContentRuleList` "block-remote-v1" plus a CSP header; navigation policy refuses anything but the scheme and `about:`. Tests `remoteRequestsAreBlockedAndReported`, `navigationAwayIsRefused` |
| Non-persistent store, no script message handlers | Pass | `websiteDataStore = .nonPersistent()`; no `add(_:name:)` handler; the renderer's own scripts run in an isolated `WKContentWorld` |
| Import: no absolute paths, `..` or symlinks; size and count caps | Pass | `SafeUnzip.swift`, `TemplateInspector.swift` (20 MB, 200 files, allowed extensions). Tests `rejectsPathTraversalInZip`, `rejectsSymlinkInFolderAndZip`, `rejectsOversizeFolderAndZip` |
| SVG logos rasterised | Pass | `LogoFileStore.svgPNG`; test `svgBecomesPNGUnder1024` |
| Not sandboxed, no privacy permission, no secrets | Pass | Info.plist has no usage keys; workflows use only `GITHUB_TOKEN` (`contents: write` only on the release job); actions pinned to commits |

## Public repo audit (working tree and the whole git history, all refs)

| Check | Result |
|---|---|
| Every image ever committed (49 paths) | Only: the club's own crest (`Packaging/crest-source.png`, `club-logo.png` × 4, `AppIcon.icns`); generated fake crests (`Resources/Seed/logos/`, `Resources/Fixtures/logos/`, opened samples: initials on plain shapes); goldens and docs screenshots made from fixture or fake data. **No real opponent logo.** |
| `template-demo/*.zip` | Each holds the club crest, the design `.dc.html`, `support.js`, `vendor/react*.js` and a README. No personal data |
| Secrets (private keys, GitHub, AWS and Slack token patterns, `password=`, `api_key=`) | None. The only `apiKey` hits are placeholder sample code (`"dev-key"`) in the vendored skill docs under `.agents/skills/` |
| Email addresses in content | Only `example.com` placeholders. Commit metadata carries the repository owner's address and noreply addresses, as on any public repo. If the owner prefers, future commits can use the GitHub noreply address |
| Phone numbers | None (the hits were commit hashes) |
| Club and person names in seed/fixtures | Invented (`Olmo Verde`, `Castelverde`, `Valdorso`, …). Generic surnames "Rossi", "Bianchi" in fixture notes. Handle `@sergnanese.demo` |
| Database files, `.env` | None ever committed; `.gitignore` covers `*.sqlite*` and `.env*` |
| Untracked `.vscode/launch.json` in the working copy | Not committed and not ignored; leave it out of commits |

## Acceptance criteria, task by task

"Tests" means I read the test name in the passing run. "User" means an agent cannot check it.

| Task | Criterion | Status | Evidence |
|---|---|---|---|
| T0.0 | 8 agents, `CLAUDE.md`, skills links resolve, `.DS_Store` not in status | Pass, with F7 | `.claude/agents/` (8), `.claude/skills/*` symlinks (mode 120000) resolve to `SKILL.md`. `.DS_Store` is ignored but still tracked |
| T0.1 | `check.sh` on CLT; Italian menus; codesign ad-hoc and bundle id; exact deps | Pass / user for menus | `check.sh` green; `codesign` on the release app; `Package.swift` `exact:` GRDB 7.12.0, swift-mustache 2.1.1, ZIPFoundation 0.9.20 |
| T0.2 | Entities and protocols; fixtures decode; `Text` tests; SSCore imports only Foundation; no warnings | Pass | `grep ^import Sources/SSCore`: Foundation only; tests `acrossAMonthBoundary`, `acrossAYearBoundary`, `countsAccentedCharactersAsOne`, `decodesTheDocumentedExample` |
| T1.1 | Repository tests incl. guards and ranges; schema idempotent; no GRDB outside SSData; logo SVG/JPEG → PNG ≤ 1024 | Pass | `openingAnEmptyFileCreatesTheSchemaAndReopeningChangesNothing`, `deleteGuardAndMatchCounts`, `svgBecomesPNGUnder1024`, `largeJPEGBecomesPNGUnder1024`, `backupIsWrittenWhenMissingOrOldAndPruned` |
| T1.2 | No googleapis/x-dc/support.js/vendor; manifests decode; previews; Barlow loaded | Pass | grep empty; four demo renders opened ("MATCH DAY" on one line); `OFL.txt` in each template |
| T1.3 | Exact size; `#CF3326`; Dark Mode identical; remote blocked; `../` refused; 23 → 3 pages; import tests; identical pixels; no window | Pass | `rendersExactSizeAndAccentColour`, `darkModeDoesNotChangeTheImage`, `remoteRequestsAreBlockedAndReported`, `filesOutsideTheTemplateFolderAreNotServed`, `listPagination23RowsGivesThreeImages`, `sameContextTwiceGivesIdenticalPixels`, `noWindowAppearsAndFocusDoesNotChange`. F2 is a flake in this suite |
| T1.4 | No real names; imports Foundation and SSCore only | Pass | Seed JSON read; `grep ^import Sources/SSSeed` |
| T1.5 | Trial run green; CI green; local packaging; Gatekeeper checked by the user | Partial | Release and trial runs green (`SMOKE OK`). CI on `main` is red at the tag (F2). Gatekeeper not yet checked (F3) |
| T1.6 | Shell, menus, Quick Look/drag/AirDrop, state restore, screenshots, Strings rule, check.sh | Pass (source, screenshots, tests) / user | Menus in `Shell/AppCommands.swift` match §4. Only inline literals are in the dev-only `ScreenshotSupport.swift`. Restore and AirDrop: U1, U2 |
| T2.1 | CRUD and lock; warnings for the 45-character name and missing logo; keyboard; VoiceOver | Pass (tests) / user | `warningsFlagTheLongNameAndTheMissingLogoAndTime`, `emptyDatabaseOffersDemoData`; keyboard U5; VoiceOver U4 |
| T2.2 | CRUD, reorder persists; logo drop/paste | Pass (tests) / user | `reorderPersistsSortOrder`, `deleteGuardForATeamWithMatchesAndDeleteOfAnEmptyOne`; drops U2 |
| T2.3 | Settings persist; standard look in Dark | Pass | `roundTripAcrossReopen`, `lightAccentWarnsAboutWhiteText`; `settings-dark.png` |
| T2.4 | List, import, problems, preview, delete/restore; folder and zip drop | Pass (tests) / user | `importingAZipInstallsAndSelects`, `templateStoreRules`; drop U2 |
| T2.5 | Full flow incl. two pages; AirDrop and two-file drag; cancel keeps images | Pass (tests) / user | `twoProgrammePagesNextWeekend`, `cancellingKeepsTheImagesAlreadyMade`; AirDrop and drag U2 (M11) |
| T3.1 | check.sh green locally and on CI; `run.sh` flow with an empty Dev folder; real folder untouched | Partial | Local green; CI flaky (F2). The `run.sh` flow needs the user (the Dev folder does not exist on this Mac, so nobody has run it here recently). The real folder was untouched by every run in this review |
| T3.2 | Reports committed with no blocking row; limits confirmed; user by-hand list done | Partial | Reports committed, no blocking row, limits table present. By-hand list empty (F4) |
| T3.3 | A new person can install and produce images from these files | Pass with mismatches | Walk-through below; F3, F5, F6 |
| T3.4 | Release with one Apple silicon `.dmg`; user confirms it runs | Pass / user | Release published (F1 for its notes); smoke of the release binary passes on this Mac; the user's own launch is still to come |

## `INSTALL.md` and `USER-GUIDE.md`, followed literally

`INSTALL.md`: the asset name `Sergnanese-Social-<versione>.dmg` matches. The `.dmg` has the Applications link for the drag. Requirements match the Info.plist. "Aiuto > Scarica aggiornamenti…" exists. The data path matches `AppPaths`. The first-launch steps (Privacy e sicurezza → Apri comunque) need the user's eyes on macOS 27 (F3).

`USER-GUIDE.md`, checked against the Strings files, `AppCommands.swift` and the screenshots:

- Match: Impostazioni ⌘,; the switcher (‹ ›, ⌘[ ⌘], "Questo weekend" ⌘T); "Aggiungi" (+) and ⌘N; the form fields Squadra, Avversario, Data, Orario, Campo, Luogo, Giornata; "Tutte"/"Nessuna"; "3 immagini da generare"; the disabled-button reasons; "Immagine 4 di 12"; "Annulla"; the "Risultato" section; "Rigenera"; Immagini › Copia immagine and Mostra nel Finder ⇧⌘R; Avversari labels (Nome breve, Alias, Scegli…, Rimuovi, Come apparirà, "Il nome viene accorciato", "Il nome entra per intero"); Squadre labels (Aggiungi squadra, Attiva, Sposta su/giù, Imposta come prima squadra); the Template labels and the "integrato" badge; the whole shortcut table; Aiuto › Apri cartella dati; the Settings tabs Società, Immagini, Dati; backup names `db-yyyyMMdd-HHmmss.sqlite`, 7 days, 5 kept; "Rimuovi dati demo"; Rinvia; "Duplica alla settimana dopo"; "Rimuovi dall'archivio"; "file mancante".
- Mismatch: F5 (screenshots), F6 (sharing and Quick Look wording). Trivial: the guide writes "Elimina…", the button says "Elimina".

## For the user (cannot be done by an agent)

1. Download the `.dmg` from the Releases page with Safari, install, and do the first-launch approval. Report the exact dialogs so `INSTALL.md` can be corrected (F3).
2. Carica dati demo → Genera → AirDrop one image to the phone (the release gate).
3. The by-hand list U1–U5 in `docs/qa/mac-review.md`: menus (M5), drag out and multi-drag (M11), Return in Genera (M1), VoiceOver over Partite, Full Keyboard Access through Genera.
4. Settings › Dati › Rimuovi dati demo before entering real matches.

## Wave 4 follow-ups, by value

1. **Close v0.1.0 properly** (small, before any Wave 4 task): F1 release notes, F2 flaky test, F3 after the user installs, F4 by-hand results, F5 and F6 docs, F7. Cheap, and they keep CI and the Releases page trustworthy.
2. **Backup and restore in Settings › Dati** (small, `core-dev` + `ui-dev`). From now on the user has real data, and the guide's restore steps are manual and unverified. A "Backup ora" button and a "Ripristina…" picker cover the main risk of the app.
3. **T4.5 Results workflow** (`ui-dev`). The half-time and full-time templates already exist. A quick score form with one-click generate and share turns match-day posting from minutes into seconds, every weekend.
4. **T4.1 CSV/Excel import with staging** (`core-dev` + `ui-dev`; blocked on a sample file). It removes the weekly typing of 8–12 matches.
5. **T4.6 Captions** (`ui-dev`). Small, used for every image.
6. **Open UI rows from T3.2**: M5 (if U1 shows duplicates), M11 multi-image drag (if U2 shows it is needed), M6 search and Condividi in the Archivio and Template toolbars. Also a warning when notes are clamped at 4 lines (V4 note).
7. **T4.2 Website import and logo download** (`render-engineer` + `ui-dev`). High value but blocked on the terms-of-use check and the source address. It is the first network feature, so §8 must be revised with it.
8. **T4.3 PDF import**: only if federation PDFs turn out to be the real source after T4.1.
9. **T4.4 Shortcuts / App Intents**: nice to have; it first needs proof that App Intents metadata builds without Xcode.
10. **T4.7 Developer ID, notarization and Sparkle**: only if the first-launch approval proves a real obstacle for other volunteers (to be learnt from item 1 of the user list).
