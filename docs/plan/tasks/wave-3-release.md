# Wave 3 — Integration and first release

Order inside the wave:

```
T3.1 wiring + tests ──┬──> T3.2 visual + Mac QA ──┐
                      └──> T3.3 docs ─────────────┼──> T3.4 release v0.1.0 ──> T3.5 final review ──> user installs
```

T3.2 and T3.3 run in parallel after T3.1.

**Gate (release):** the `.dmg` from GitHub Releases installs on the user's Mac, loads demo data, produces the weekend images, and one of them arrives on the phone by AirDrop.

| Task | Agent | Model |
|---|---|---|
| T3.1 Wiring + integration tests | `core-dev` | sonnet |
| T3.2 Visual and Mac QA | `qa-reviewer` | opus |
| T3.3 User docs | `chore-runner` | haiku |
| T3.4 Release v0.1.0 | `release-engineer` | sonnet |
| T3.5 Final review | `qa-reviewer` | opus |

---

## T3.1 — Wiring and integration tests

| | |
|---|---|
| **Agent / model** | `core-dev` · sonnet · effort medium |
| **Depends on** | all of Wave 2 |
| **Owns** | `Sources/SergnaneseSocial/**`, `Sources/ss-tool/Seed.swift`, `Tests/IntegrationTests/**` |
| **Size** | M |

**Features**

1. `Composition.makeServices()`: resolve `AppPaths`, open the database (migrations, backup), install built-in templates, build the real repositories, `LogoStore`, `TemplateStore`, `RenderService` and `SeedLoader` into `AppServices`. If startup fails, show a standard alert with the reason and a "Mostra cartella dati" button, then quit.
2. Fakes stay available behind `--mock`; the "dati demo" toolbar badge from T1.6 now appears only in mock mode.
3. First run: with an empty database, Partite offers "Carica dati demo".
4. `ss-tool seed`: loads the fake data into the **Dev** data folder (or `SS_DATA_DIR`). It refuses to run against the release data folder.
5. `--smoke` switched to the real engine: temp data folder, load seed, render one built-in template, check the PNG size and one accent pixel.
6. About panel shows version and build from `version.env`. Logging through `os.Logger` (subsystem = the bundle id) for startup, imports and renders.
7. Integration tests (real services, temp data folder, no UI):
   - seed → the matches list shows next weekend;
   - edit a match time → the value is there after closing and reopening the database;
   - render next weekend with the default plan → the expected number of PNG files exist with the exact sizes;
   - weekend with 12 matches → two programme stories;
   - import a user template zip → it is listed and renders;
   - opponent with no logo → the image still renders, with initials.
8. Golden images for the four built-in templates from the fixtures, compared with a small tolerance. They are produced and compared **on macOS only** (the only platform there is); a documented command updates them on purpose. If the CI runner's rendering differs from the local Mac beyond the tolerance, keep one golden set per environment and say so in the report.

**Acceptance**

- [ ] `Scripts/check.sh` (now including integration tests) is green locally and on CI.
- [ ] `Scripts/run.sh` with an empty Dev data folder: the whole flow works with no mock.
- [ ] Nothing in the run touched `~/Library/Application Support/Sergnanese Social/`.

---

## T3.2 — Visual QA of images and Mac QA of the app

| | |
|---|---|
| **Agent / model** | `qa-reviewer` · opus · effort high |
| **Depends on** | T3.1 |
| **Owns** | `docs/qa/visual-report.md`, `docs/qa/mac-review.md` (reports only; fixes are dispatched) |
| **Size** | M–L |

Opus is used because this is judgement: spotting overlap, clipping, bad truncation and weak contrast in images, and things that feel wrong for a Mac app.

**Part A — rendered images**

1. Render every built-in template with a matrix of data and **look at every image**:
   - opponent names of 6, 16, 25 and 45 characters, with and without a short name;
   - logo present, missing, very wide, very tall, transparent and white-background;
   - home and away;
   - time missing, venue missing, round missing, notes empty and three lines long;
   - programme with 1, 5, 10, 11 and 23 matches;
   - scores 0–0 and 10–12;
   - accent colour changed to a dark and to a light value.
2. Check Instagram story safe zones and that text contrast stays readable.

**Part B — the app as a Mac app**

3. Go through `03-mac-design.md` section by section and the evaluation checklist of the `macos-design-guidelines` skill, using `ss-tool screenshots` (Light and Dark), the source, and the running app where a command line can drive it. For each item: pass, fail, or "needs the user's eyes".
4. Specific checks: every menu item of §4 exists with its shortcut and is disabled when it should be; every icon-only button has an accessibility label; no fixed colours on surfaces or text; every list has empty and error states; destructive actions confirm; no alert after a successful action.
5. A short list for the user to try by hand, because an agent cannot: AirDrop an image to the phone, drag an image into a browser upload field, VoiceOver over the matches table, Full Keyboard Access through the Generate screen.

**Both parts**

6. Reports with one row per problem: where, what is wrong, screenshot path, suggested fix, owner agent, blocking or not.
7. The orchestrator dispatches fixes (template issues → `template-converter`, engine issues → `render-engineer`, UI issues → `ui-dev`), then this task re-checks only the failed cases.

**Acceptance**

- [ ] Both reports committed; zero open "blocking" rows.
- [ ] `limits` values in the manifests are confirmed or corrected.
- [ ] The user has done the by-hand list and their findings are in `mac-review.md`.

---

## T3.3 — User documentation

| | |
|---|---|
| **Agent / model** | `chore-runner` · haiku |
| **Depends on** | T3.1 |
| **Owns** | `README.md`, `docs/USER-GUIDE.md`, `docs/TEMPLATES.md` |
| **Size** | S |

**Features**

1. `README.md`: what the app is, screenshot, download link to Releases, link to `INSTALL.md`, how to build from source (`Scripts/run.sh`, Command Line Tools only), licence note about third-party logos and the Barlow font licence.
2. `docs/USER-GUIDE.md` (Italian): the weekly routine in six steps with screenshots from `ss-tool screenshots`; sending images to the phone with AirDrop; managing opponents and logos; the keyboard shortcuts table; backups; FAQ ("il nome è tagliato", "manca il logo", "la partita è stata spostata").
3. `docs/TEMPLATES.md`: move and extend the template-writing guide from T1.2, including how to ask Claude to design a new template that fits the format.
4. Check every instruction against the running app's menus and labels; report anything that does not match.

**Acceptance**

- [ ] A person who has never seen the app can install it and produce images following only these files (checked by `qa-reviewer` in T3.5).

---

## T3.4 — Release v0.1.0

| | |
|---|---|
| **Agent / model** | `release-engineer` · sonnet · effort medium |
| **Depends on** | T3.1, T3.2, T3.3 |
| **Owns** | `version.env`, `CHANGELOG.md`, the git tag |
| **Size** | S |

**Features**

1. Set `VERSION=0.1.0` in `version.env`, write `CHANGELOG.md`.
2. Run `release.yml` manually first (draft release), confirm the smoke step and the `.dmg`.
3. **Ask the user before tagging.** After approval: tag `v0.1.0`, let the workflow publish the release with notes and the install steps.
4. Post-release checklist for the user: download with the browser, first-launch approval, load demo data, generate, AirDrop one image to the phone.

**Acceptance**

- [ ] Release `v0.1.0` exists on GitHub with one `.dmg` (Apple silicon).
- [ ] The user confirms the app runs on their Mac.

---

## T3.5 — Final review

| | |
|---|---|
| **Agent / model** | `qa-reviewer` · opus · effort high |
| **Depends on** | T3.4 (draft release available) |
| **Owns** | `docs/qa/final-review.md` |
| **Size** | S–M |

**Features**

1. Fresh-context review of the whole repo against this plan: every task's acceptance criteria, the README decisions D1–D9 and P1–P8, the security notes in `01-architecture.md` §8.
2. Check there is no private data, real opponent logo or secret in the public repo, including the git history of this project.
3. Follow `INSTALL.md` and `USER-GUIDE.md` literally and note every mismatch.
4. List of follow-ups for Wave 4, ordered by value.

**Acceptance**

- [ ] Review committed; no blocking finding open.
