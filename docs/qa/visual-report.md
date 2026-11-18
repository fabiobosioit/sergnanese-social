# T3.2 Part A: visual QA of the rendered images

- Tested: `main` at `6a27429` (after T3.1 and T3.3), 2026-11-18.
- Reviewer: `qa-reviewer`. This file is a report. It does not fix anything; fixes go to the owner shown in each row.
- Verdict: **changes needed**. There is **1 blocking row** (V1).

## How the images were made

| Source | What | Count |
|---|---|---|
| QA matrix (production path) | `ContextBuilder` → `TemplateHTML` (swift-mustache) → `WebRenderer`. This is the same code `TemplateRenderService` runs. Settings, matches and logos were built in memory. The harness lives outside the repo (a scratch copy with one extra executable target), so no file in the repo was changed. | 96 single images (32 cases × 3 single templates) + 14 programme pages (9 cases) |
| Limits experiment (same path) | Stress strings at the current limits, plus a few proposed limits | 20 |
| `swift run ss-tool demo-render --all` | Every fixture variant for every template | 20 |
| `swift run ss-tool preview` | `post-prematch` with `single-no-time` | 1 |
| `swift run ss-tool seed` | Into a temp `SS_DATA_DIR`: 10 teams, 20 opponents, 48 matches | n/a |

I opened every image, one by one or through contact sheets (3 × 2 per sheet; stories carry dashed lines at y = 250 and y = 1670). I opened some at full size to check details.

- Contact sheets: `out/qa/sheets/*.png`, `out/qa/limits/sheet_*.png`, `out/qa/demo-sheets/*.png`
- Single images: `out/qa/single/<template>/<case>.png`
- Programme pages: `out/qa/list/story-programme/<case>_p<i>of<n>.png`
- Run log with the warnings of each image: `out/qa/report.txt`

`out/` is gitignored, and these paths exist in the T3.2 worktree. To re-check a case through the app, enter the data described in the row and press Genera.

Mechanical results:

- Every PNG has exactly the manifest size (1080×1350 or 1080×1920). `report.txt` lists `size` for each one.
- No render asked for a remote URL (`blocked=[]` everywhere).
- No template contains `http`, `//fonts` or `<script src`.

## Data matrix covered

| Dimension | Cases (all four templates unless noted) | Result |
|---|---|---|
| Opponent name length | 6 (`Valdor`), 16 (`Campofelice Alta`), 25 (`Oratorio Santa Eufrasia B`), 45 (`Oratorio San Gerolamo Emiliani di Castelverde`), one 25-letter word | Pass. Names are cut at a word boundary with `…`, and every cut gives a warning |
| Short name | 25 and 45 with and without `shortName` | Pass. The short name is used |
| Logo | Present, none (initials), file missing (initials + warning), 1200×240, 240×1200, transparent, white square background | Pass, with the cosmetic issue in V6 |
| Home / away | Both, for each name length and for 10–12 | Pass. Home is on the left / first row in every template |
| Missing data | Time, venue, round + competition, handle, notes empty, no score | **Venue fails (V1)**. The other cases pass: `—` for time, the round block is hidden, `–` when there is no score |
| Notes | Empty, 3 explicit lines, a long line that wraps, 8 lines | Pass up to 8 lines (V4) |
| Programme | 1, 5, 10, 11 (2 pages), 23 in one day (3 pages: 10/10/3), 23 over two days, 10 worst-case rows | Pass. The page label `1/3` appears only when there are several pages |
| Scores | 0–0 (zeros shown), 10–12 away (12 on top for the home side) | Pass |
| Accent | `#CF3326` (default), `#14213D` (dark), `#FFE066` (light), `#F2F2F2` (near white) | Dark passes. **Light and near-white are unreadable (V2)** |
| Long fields | Venue `Centro Sportivo Comunale`, category `Juniores Regionali Under 19`, 22-character category, a 30-character handle | Pass. The handle wraps the story footer (V3) |
| Status | Postponed match ticked explicitly | See V7 |

## Problems

| ID | Where | What is wrong | Screenshot | Suggested fix | Owner | Blocking |
|---|---|---|---|---|---|---|
| V1 | `Sources/SSRender/TemplateHTML.swift:50-73` (`mustacheValue` / `plain`); seen in all four templates | **An empty venue is treated as present.** `MatchContext.venue` is `""` when the match has no venue. `plain` keeps empty strings, and swift-mustache treats every `String` as true, including `""` (`.build/checkouts/swift-mustache/Sources/Mustache/Template+Render.swift:141-176`). Results: `post-prematch` shows the `CAMPO` label with nothing under it (the template means to show `—`). `story-fulltime` footer reads `· DOM 22 NOV`. `story-halftime` footer reads `· 14:30`. `story-programme` rows show a bare `(C)`. This happens from the first day: `ClubSettings.defaults.homeVenue` is `""`, and a new match takes its venue from it (`MatchFormState.swift:32`). `ss-tool preview` hides the bug, because its own Mustache treats `""` as false (`Preview.swift`, `isTruthy`). | `out/qa/single/post-prematch/s19-no-venue.png`, `out/qa/single/story-fulltime/s19-no-venue.png`, `out/qa/single/story-halftime/s19-no-venue.png`, `out/qa/list/story-programme/L10-worst_p1of1.png` (rows 3, 6, 7) | In `TemplateHTML.plain`, drop `String` values that are empty after trimming, so they are absent (this is what the doc comment already promises for `nil`). Add a render test with `venue: ""` for each built-in template that asserts the `—` / no leading `·`. Optionally make the preview tool's truthiness match swift-mustache. | `render-engineer` | **Yes** |
| V2 | All four templates; Settings › Immagini › Colore dei modelli | A light accent makes text unreadable. The templates put white text on the accent (bands, cards, the whole halftime background, programme time cells) and accent text on white (`MATCH DAY`, `FINALE`, `GIORNATA`, `VS`). Contrast with white: `#FFE066` = 1.3:1, `#F2F2F2` = 1.1:1. For comparison, the default `#CF3326` = 5.0:1 and `#14213D` = 16:1. Settings accepts any colour without a word of warning. | `out/qa/single/*/s27-accent-light.png`, `out/qa/single/*/s28-accent-white.png`, `out/qa/list/story-programme/L10-light_p1of1.png` | In Settings, show an inline `ProblemText` when contrast(accent, `#FFFFFF`) < 3:1 (WCAG AA, large text), for example "Colore troppo chiaro: il testo bianco non si legge". The text goes in `SettingsStrings`. | `ui-dev` | No |
| V3 | `story-fulltime`, `story-halftime` footer | With a longer social handle (30 characters), the left part of the footer wraps and the date splits across lines (`DOM 22` / `NOV`). | `out/qa/limits/story-fulltime__b-real-16-20.png`, `out/qa/limits/story-halftime__c-venue18-proposal.png` | Put `white-space: nowrap` on the date/time. Give the venue part `min-width: 0; overflow: hidden; text-overflow: ellipsis`. Or move the handle to its own line. | `template-converter` | No |
| V4 | `story-fulltime`, `story-halftime` notes | Notes have no length limit. Eight lines push `FINALE` / `INTERVALLO` up towards the header, and about twelve would overlap it. | `out/qa/limits/story-fulltime__f-notes-8-lines.png`, `out/qa/limits/story-halftime__f-notes-8-lines.png` | Clamp the notes block in the template (`display: -webkit-box; -webkit-line-clamp: 4; overflow: hidden`). | `template-converter` | No |
| V5 | All templates (stress strings only) | A single long word does not wrap. In stories it runs under the score (`WMWM…` + `12`). In the post, the name and venue are clipped at the right edge. In the programme, the 150-px time cell shrinks. Real names are cut at a word boundary well before this, but one long compound word plus a two-digit score is possible. | `out/qa/limits/story-fulltime__a-stress-team-W16-venue-M14.png`, `out/qa/limits/post-prematch__a-stress-team-W16-venue-M14.png`, `out/qa/limits/story-programme__team32-proposal.png` | Add `overflow-wrap: anywhere` (or `overflow: hidden; text-overflow: ellipsis`) on the name and venue boxes. Add `flex-shrink: 0` on the programme time cell and on the score cells. | `template-converter` | No |
| V6 | `story-fulltime` score card | A logo with a white square background shows as a hard white box on the red card. It looks fine on white backgrounds. | `out/qa/single/story-fulltime/s17-logo-whitebg.png` | Put opponent logos on a white rounded plate in this template (as the initials circle already does), or accept. | `template-converter` | No |
| V7 | All single templates | A postponed or cancelled match renders as a normal "MATCH DAY" if the user ticks it by hand. The default plan skips it (`RenderPlanner.swift:92`) and a warning is shown. | `out/qa/single/post-prematch/s31-postponed.png` | Add a `{{#match.isPostponed}}RINVIATA{{/match.isPostponed}}` / `isCancelled` badge, or leave it to the warning. | `template-converter` | No |
| V8 | `story-programme` rows | The secondary text is small for a phone: the opponent line is 24 px and `(C)`/`(T)` is 20 px, roughly 8–9 pt on a 390-pt-wide screen. It is readable but tight. | `out/qa/list/story-programme/L10-worst_p1of1.png` | Optional: 26–28 px for the opponent line, 22 px for the marker. | `template-converter` | No |
| V9 | `Resources/Templates/README.md:41,57`, `docs/TEMPLATES.md:65` | The guide says "Mustache treats 0 as false" and "`match.venue` may be empty". The production renderer (swift-mustache) treats every number and every string as true, including `0` and `""`. The advice to use `hasScore` is still right, but the reason given is wrong, and the guide does not warn template authors that `{{^match.venue}}` never fires. After V1 is fixed, empty strings are absent and the guide becomes true for venue. | n/a | After V1, state that empty strings are absent, and correct the reason in the 0 note. `Resources/Fixtures/README.md:13` has the same sentence but is frozen (T0.2). | `template-converter` (README), `chore-runner` (TEMPLATES.md) | No |

Not a problem, for the record: a programme page that covers two days ("Weekend in campo") has no day on each row. The planner always makes one set of pages per day (`RenderPlanner.items`), so the app never produces such a page. It appears only in the `list-23` fixture.

## `limits` in the manifests

Every value is **confirmed**. Each was checked with the widest realistic text and a stress string at the limit. The optional raises are improvements, not fixes. None of them is needed for v0.1.0.

| Template | Field | Value | Verdict | Evidence |
|---|---|---|---|---|
| `post-prematch` | `teamName` | 16 | Confirmed. One line in the 340-px column (`CAMPOFELICE ALTA`, `PRATOFIORITOCAS…`). At 24 the name wraps to two lines and the logos stop lining up. | `out/qa/sheets/post-prematch_1.png`, `_2.png`, `out/qa/limits/post-prematch__e-team22-proposal.png` |
| `post-prematch` | `venue` | 14 | Confirmed. Two lines (`CAMPO` / `COMUNALE`). Optional: 18 also fits on two lines (`CENTRO` / `SPORTIVO…`, `ORATORIO` / `SAN LUIGI`). | `out/qa/limits/post-prematch__c-venue18-proposal.png`, `__d-venue18-proposal-b.png` |
| `post-prematch` | `category` | 22 | Confirmed. `GIOVANISSIMI REGIONALI` and 22 × `W` fit on one line. | `out/qa/sheets/post-prematch_5.png`, `out/qa/limits/sheet_1.png` |
| `story-fulltime`, `story-halftime` | `teamName` | 20 | Confirmed. One line next to a two-digit score (`CAMPOFELICE ALTA 12`, `PRATOFIORITOCASTELN…`). Optional: 24 wraps cleanly to two lines. | `out/qa/sheets/story-fulltime_2.png`, `_5.png`, `out/qa/limits/story-fulltime__e-team22-proposal.png` |
| `story-fulltime`, `story-halftime` | `venue` | 14 | Confirmed. The footer stays on one line with a normal handle. 24 wraps the footer. | `out/qa/limits/story-fulltime__c-venue18-proposal.png` |
| `story-fulltime`, `story-halftime` | `category` | 22 | Confirmed (`GIOVANISSIMI REGIONALI · GIORNATA 12` in the header). | `out/qa/sheets/story-fulltime_5.png` |
| `story-programme` | `teamName` | 22 | Confirmed (one line, about half the column used). Optional: up to about 28 fits real names (`vs Oratorio San Gerolamo Emiliani…`), but only after V5 (`flex-shrink: 0` on the time cell). | `out/qa/limits/story-programme__current.png`, `__team32-proposal.png` |
| `story-programme` | `venue` | 14 | Confirmed (`CAMPO COMUNALE (C)` stays inside the row; the marker drops to a second line). | `out/qa/list/story-programme/L10_p1of1.png` |
| `story-programme` | `category` | 16 | Confirmed (16 × `W` fits). | `out/qa/limits/story-programme__current.png` |

## Instagram safe zones and contrast

- **Story safe zones:** in every story render, all text and logos sit between y = 250 and y = 1670. The header starts at 250. The fulltime and halftime footers end at 1660. The last programme row ends at about 1645. Only decorative shapes and colour fields enter the top and bottom 250 px. This holds with 3-line notes, 10 programme rows and long handles. With 8 lines of notes the content grows towards the middle, not past the zones.
- **Post:** the 60-px side margins survive Instagram's 3:4 profile-grid crop (about 34 px each side).
- **Contrast with the default accent:** white on `#CF3326` and `#CF3326` on white are 5.0:1, which meets AA for normal text. `#5A4A4C` on `#FFF3F1` (programme opponent line) is 7.7:1. `#1F1214` on white (halftime card) is about 18:1. The initials `#5A4A4C` on white are 8.4:1. A dark accent (`#14213D`) is 16:1. A light accent fails (V2).

## Re-check list for this task after fixes

- V1: render each built-in template with `venue: ""`, home and away. Expect `—` in the post, no leading `·` in the story footers, and no bare `(C)` in the programme.
- V2: in Settings, type `#FFE066`. Expect a warning.
- V3–V5, if fixed: re-run the limits experiment (`out/qa/limits/`).

## User findings

To be filled in by the user after looking at real generated images on the phone (optional for Part A).

| Date | What was checked | Finding |
|---|---|---|
| | | |
