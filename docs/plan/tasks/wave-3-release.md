# Wave 3 — Integration and first release

Order inside the wave:

```
T3.1 wiring + e2e ──┬──> T3.2 visual QA ──┐
                    └──> T3.3 docs ───────┼──> T3.4 release v0.1.0 ──> T3.5 final review ──> user installs
```

T3.2 and T3.3 run in parallel after T3.1.

**Gate (release):** the `.dmg` from GitHub Releases installs on the user's Mac, loads demo data, and produces the weekend images.

| Task | Agent | Model |
|---|---|---|
| T3.1 Wiring + end-to-end tests | `backend-dev` | sonnet |
| T3.2 Visual QA with edge data | `qa-reviewer` | opus |
| T3.3 User docs + first-run polish | `chore-runner` | haiku |
| T3.4 Release v0.1.0 | `release-engineer` | sonnet |
| T3.5 Final review | `qa-reviewer` | opus |

---

## T3.1 — Wiring and end-to-end tests

| | |
|---|---|
| **Agent / model** | `backend-dev` · sonnet · effort medium |
| **Depends on** | all of Wave 2 |
| **Owns** | `electron/main.ts`, `electron/smoke.ts`, `tests/e2e/**` |
| **Size** | M |

**Features**

1. `electron/main.ts` final assembly: open database, run migrations and backup, install built-in templates, build the Fastify app with real repositories and services, open the window. Clear error dialog if startup fails.
2. Mocks stay available behind `VITE_MOCK=1` but are off by default and excluded from the production bundle.
3. First run: if the database is empty, the Matches page offers "Carica dati demo".
4. Extend `--smoke` to use the real engine: seed, render one built-in template, check size.
5. App menu: standard macOS menu, "Apri cartella dati", "Apri cartella immagini", version in About.
6. End-to-end tests (Playwright `_electron`, temp data dir):
   - seed → Matches shows next weekend;
   - edit a match time → value persists after restart;
   - Generate for next weekend → expected number of PNG files exist with the exact sizes;
   - weekend with 12 matches → two programme stories;
   - upload a user template zip → it appears and can render;
   - opponent with no logo → image still renders with initials.
7. Golden images for the four built-in templates from the shared fixtures, compared with a small tolerance; a documented command to update them on purpose.

**Acceptance**

- [ ] `npm run check` (now including e2e) is green locally and on CI.
- [ ] Starting from an empty data dir, the whole flow works with no mock.

---

## T3.2 — Visual QA with edge data

| | |
|---|---|
| **Agent / model** | `qa-reviewer` · opus · effort high |
| **Depends on** | T3.1 |
| **Owns** | `docs/qa/visual-report.md` (report only; fixes are dispatched) |
| **Size** | M |

Opus is used because this is judgement on images: spotting overlap, clipping, bad truncation and weak contrast.

**Features**

1. Render every built-in template with a matrix of data and **look at every image**:
   - opponent names of 6, 16, 25 and 45 characters, with and without a short name;
   - logo present, missing, very wide, very tall, transparent and white-background;
   - home and away;
   - time missing, venue missing, round missing, notes empty and three lines long;
   - programme with 1, 5, 10, 11 and 23 matches;
   - scores 0–0 and 10–12;
   - accent colour changed to a dark and to a light value.
2. Check Instagram story safe zones and that text contrast stays readable.
3. Report with one row per problem: template, data case, what is wrong, screenshot path, suggested fix, owner agent.
4. The orchestrator dispatches fixes (template issues → `template-converter`, engine issues → `render-engineer`), then this task re-checks only the failed cases.

**Acceptance**

- [ ] Report committed; zero open "blocking" rows.
- [ ] Slot `maxChars` values in the manifests are confirmed or corrected.

---

## T3.3 — User documentation and first-run polish

| | |
|---|---|
| **Agent / model** | `chore-runner` · haiku |
| **Depends on** | T3.1 |
| **Owns** | `README.md`, `docs/USER-GUIDE.md`, `docs/TEMPLATES.md` |
| **Size** | S |

**Features**

1. `README.md`: what the app is, screenshot, download link to Releases, link to `INSTALL.md`, how to run from source, licence note about third-party logos.
2. `docs/USER-GUIDE.md` (Italian): the weekly routine in six steps with screenshots taken from the running app; managing opponents and logos; backups; FAQ ("il nome è tagliato", "manca il logo", "la partita è stata spostata").
3. `docs/TEMPLATES.md`: move and extend the template-writing guide from T1.2, including how to ask Claude to design a new template that fits the format.
4. Check every instruction by doing it in the app; report anything that does not match.

**Acceptance**

- [ ] A person who has never seen the app can install it and produce images following only these files (checked by `qa-reviewer` in T3.5).

---

## T3.4 — Release v0.1.0

| | |
|---|---|
| **Agent / model** | `release-engineer` · sonnet · effort medium |
| **Depends on** | T3.1, T3.2, T3.3 |
| **Owns** | version in `package.json`, `CHANGELOG.md`, the git tag |
| **Size** | S |

**Features**

1. Set version `0.1.0`, write `CHANGELOG.md`.
2. Run `release.yml` manually first (draft release), confirm the smoke step and both `.dmg` files.
3. **Ask the user before tagging.** After approval: tag `v0.1.0`, let the workflow publish the release with notes and the install steps.
4. Post-release checklist for the user: download, first-launch approval, load demo data, generate, find the images.

**Acceptance**

- [ ] Release `v0.1.0` exists on GitHub with `.dmg` and `.zip` for arm64 and x64.
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

1. Fresh-context review of the whole repo against this plan: every task's acceptance criteria, the README decisions D1–D9, the security notes in `01-architecture.md` §8.
2. Check there is no private data, real opponent logo or secret in the public repo, including git history of this project.
3. Follow `INSTALL.md` and `USER-GUIDE.md` literally and note every mismatch.
4. List of follow-ups for Wave 4, ordered by value.

**Acceptance**

- [ ] Review committed; no blocking finding open.
