# T3.2 Part A: visual QA of the rendered images

- First run: `main` at `6a27429` (after T3.1 and T3.3), 2026-11-18.
- Re-check: `main` at `b0ce149` (after the T3.2 fixes for V1–V9), 2026-11-18. See [Re-check](#re-check-after-the-fixes).
- Reviewer: `qa-reviewer`. This file is a report. It does not fix anything; fixes go to the owner shown in each row.
- Verdict after the re-check: **no row is open.** V1 (blocking) is fixed, V2–V9 are fixed. One non-blocking row (V10) came out of the V3 fix and is now fixed.

## Re-check after the fixes

How the images were made: the same harness as the first run (`ContextBuilder` → `TemplateHTML` → `WebRenderer`, the code
`TemplateRenderService.renderImage` runs), synced to `b0ce149`, with `SS_DATA_DIR` set to a temp folder. 40 single cases × 3
templates + 15 programme pages (135 images, 0 failures, `blocked=[]` on every image) and the 20-image limits experiment. Eight
single cases and one programme case were added for the re-check: `s33-cancelled`, `s34-postponed-longheader`,
`s35-no-venue-away`, `s36-no-venue-notime-longhandle`, `s37-venue-spaces` (venue `"   "`), `s38-notes-8lines`,
`s39-longhandle-venue14`, `s40-logo-whitebg-away`, `L05-novenue`. I opened every contact sheet and the key images at full size.
`Scripts/check.sh` passes on `b0ce149` (321 tests). Neither `~/Library/Application Support/Sergnanese Social` nor `… Dev` exists
after the run.

| ID | Status | Evidence (re-check images under `out/qa/` in the re-check worktree) |
|---|---|---|
| V1 | **Fixed** | `TemplateHTML.plain` drops blank strings (`Sources/SSRender/TemplateHTML.swift:65-83`). Post: `CAMPO` shows `—` (`single/post-prematch/s19-no-venue.png`, `s35-no-venue-away.png`, `s37-venue-spaces.png`). Fulltime footer starts at `DOM 22 NOV`, no `·` (`single/story-fulltime/s19-no-venue.png`, `s35`, `s36`, `s37`). Halftime footer shows only `14:30`, or nothing on the left with no time (`single/story-halftime/s35-no-venue-away.png`, `s36`, `s37`). Programme rows show `— (C)` / `— (T)` (`list/story-programme/L05-novenue_p1of1.png`, `L10-worst_p1of1.png` rows 3, 6, 7). Home/away order correct in every case. Render test `Tests/SSRenderTests/EmptyVenueTests.swift` covers the four templates, home and away. `ss-tool preview` truthiness now matches (`Preview.swift:310-314`). |
| V2 | **Fixed** (source) | `SettingsModel.accentContrastWarning` (`SettingsModel.swift:57`), shown under the colour field (`SettingsView.swift:83`), text in `SettingsStrings.accentTooLight`. Test `lightAccentWarnsAboutWhiteText` checks `#FFE066` and `#F2F2F2` warn, `#CF3326` (5.0:1) and `#14213D` do not. The Immagini tab is not in `ss-tool screenshots`, so the user sees it in U1. |
| V3 | **Fixed**, see V10 | The date no longer splits: `DOM 22 NOV` and `14:30` stay on one line with a 32-character handle and a 24-character venue (`limits/sheet_2.png`, `sheet_3.png`). The venue is cut with `…` when space runs out (`limits/story-fulltime__b-real-16-20.png`: `COMUNALE NU… · DOM 22 NOV`). |
| V4 | **Fixed** | Notes clamp at 4 lines with `…` (`single/story-fulltime/s38-notes-8lines.png`, `limits/story-fulltime__f-notes-8-lines.png`, halftime same). `FINALE` / `INTERVALLO` stay well below the header. Note for the user: lines 5 and later are dropped without a warning in the app. |
| V5 | **Fixed** | Stories: the long word wraps to two lines inside the name box, the score `12` keeps its place (`limits/story-fulltime__a-stress-team-W16-venue-M14.png`, halftime same). Post: name and venue wrap inside their columns (`limits/post-prematch__a-stress-team-W16-venue-M14.png`). Programme: the 150-px time cell no longer shrinks (`limits/story-programme__current.png`). Stress strings only: in the programme a 22-letter `WMWM…` name wraps to a third line that the 86-px row clips. Real names are cut at a word boundary and stay on one line (`L10-worst`), so this is not a new row. |
| V6 | **Fixed** | Opponent logos sit on a white rounded plate on the red card (`single/story-fulltime/s17-logo-whitebg.png`, `s40-logo-whitebg-away.png`). The plate also looks right for transparent and circular logos (`s16`, `s01`). |
| V7 | **Fixed** | `RINVIATA` / `ANNULLATA` badge in the post next to the category and top-right in both stories (`sheets/post-prematch_6.png`, `sheets/story-fulltime_6.png`, `sheets/story-halftime_6.png`: `s31`, `s33`, `s34`). With a 22-character category and round 30 the header and badge still fit (`s34`). |
| V8 | **Fixed** | Programme opponent line is 28 px, the `(C)`/`(T)` marker 22 px (`story-programme/template.html:39,41`). Rows stay inside the 86-px height with real data (`list/story-programme/L10-worst_p1of1.png`, `L23-oneday_p1of3.png`). |
| V9 | **Fixed** | `docs/TEMPLATES.md:68` says `match.venue` is absent when empty, `:84-89` explains blank strings and the real reason for `hasScore`. `Resources/Templates/README.md` now points to `docs/TEMPLATES.md`. Left as is: `Resources/Fixtures/README.md:13` still says "Mustache treats 0 as false" (frozen, T0.2), and `docs/TEMPLATES.md:62` still says `club.handle` "può essere vuoto" (the general rule at `:84` covers it). |
| V10 | **Fixed** | See the Problems table. |

## How the images were made (first run)

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
| Logo | Present, none (initials), file missing (initials + warning), 1200×240, 240×1200, transparent, white square background | Pass. V6 fixed |
| Home / away | Both, for each name length and for 10–12 | Pass. Home is on the left / first row in every template |
| Missing data | Time, venue, round + competition, handle, notes empty, no score | Pass after V1. `—` for time and venue, the round block is hidden, `–` when there is no score |
| Notes | Empty, 3 explicit lines, a long line that wraps, 8 lines | Pass. 8 lines are clamped to 4 (V4) |
| Programme | 1, 5, 10, 11 (2 pages), 23 in one day (3 pages: 10/10/3), 23 over two days, 10 worst-case rows, 5 with no venue | Pass. The page label `1/3` appears only when there are several pages |
| Scores | 0–0 (zeros shown), 10–12 away (12 on top for the home side) | Pass |
| Accent | `#CF3326` (default), `#14213D` (dark), `#FFE066` (light), `#F2F2F2` (near white) | Dark passes. Light and near-white are unreadable in the image; Settings now warns (V2) |
| Long fields | Venue `Centro Sportivo Comunale`, category `Juniores Regionali Under 19`, 22-character category, a 32-character handle | Pass (handle cap removed, V10) |
| Status | Postponed and cancelled ticked explicitly | Pass. Badge shown (V7) |

## Problems

| ID | Where | What is wrong | Screenshot | Suggested fix | Owner | Blocking | Status (re-check `b0ce149`) |
|---|---|---|---|---|---|---|---|
| V1 | `Sources/SSRender/TemplateHTML.swift:50-73` (`mustacheValue` / `plain`); seen in all four templates | **An empty venue is treated as present.** `MatchContext.venue` is `""` when the match has no venue. `plain` keeps empty strings, and swift-mustache treats every `String` as true, including `""` (`.build/checkouts/swift-mustache/Sources/Mustache/Template+Render.swift:141-176`). Results: `post-prematch` shows the `CAMPO` label with nothing under it (the template means to show `—`). `story-fulltime` footer reads `· DOM 22 NOV`. `story-halftime` footer reads `· 14:30`. `story-programme` rows show a bare `(C)`. This happens from the first day: `ClubSettings.defaults.homeVenue` is `""`, and a new match takes its venue from it (`MatchFormState.swift:32`). `ss-tool preview` hides the bug, because its own Mustache treats `""` as false (`Preview.swift`, `isTruthy`). | `out/qa/single/post-prematch/s19-no-venue.png`, `out/qa/single/story-fulltime/s19-no-venue.png`, `out/qa/single/story-halftime/s19-no-venue.png`, `out/qa/list/story-programme/L10-worst_p1of1.png` (rows 3, 6, 7) | In `TemplateHTML.plain`, drop `String` values that are empty after trimming, so they are absent (this is what the doc comment already promises for `nil`). Add a render test with `venue: ""` for each built-in template that asserts the `—` / no leading `·`. Optionally make the preview tool's truthiness match swift-mustache. | `render-engineer` | **Yes** | **Fixed** |
| V2 | All four templates; Settings › Immagini › Colore dei modelli | A light accent makes text unreadable. The templates put white text on the accent (bands, cards, the whole halftime background, programme time cells) and accent text on white (`MATCH DAY`, `FINALE`, `GIORNATA`, `VS`). Contrast with white: `#FFE066` = 1.3:1, `#F2F2F2` = 1.1:1. For comparison, the default `#CF3326` = 5.0:1 and `#14213D` = 16:1. Settings accepts any colour without a word of warning. | `out/qa/single/*/s27-accent-light.png`, `out/qa/single/*/s28-accent-white.png`, `out/qa/list/story-programme/L10-light_p1of1.png` | In Settings, show an inline `ProblemText` when contrast(accent, `#FFFFFF`) < 3:1 (WCAG AA, large text), for example "Colore troppo chiaro: il testo bianco non si legge". The text goes in `SettingsStrings`. | `ui-dev` | No | **Fixed** (source + unit test) |
| V3 | `story-fulltime`, `story-halftime` footer | With a longer social handle (30 characters), the left part of the footer wraps and the date splits across lines (`DOM 22` / `NOV`). | `out/qa/limits/story-fulltime__b-real-16-20.png`, `out/qa/limits/story-halftime__c-venue18-proposal.png` | Put `white-space: nowrap` on the date/time. Give the venue part `min-width: 0; overflow: hidden; text-overflow: ellipsis`. Or move the handle to its own line. | `template-converter` | No | **Fixed** (side effect V10, also fixed) |
| V4 | `story-fulltime`, `story-halftime` notes | Notes have no length limit. Eight lines push `FINALE` / `INTERVALLO` up towards the header, and about twelve would overlap it. | `out/qa/limits/story-fulltime__f-notes-8-lines.png`, `out/qa/limits/story-halftime__f-notes-8-lines.png` | Clamp the notes block in the template (`display: -webkit-box; -webkit-line-clamp: 4; overflow: hidden`). | `template-converter` | No | **Fixed** |
| V5 | All templates (stress strings only) | A single long word does not wrap. In stories it runs under the score (`WMWM…` + `12`). In the post, the name and venue are clipped at the right edge. In the programme, the 150-px time cell shrinks. Real names are cut at a word boundary well before this, but one long compound word plus a two-digit score is possible. | `out/qa/limits/story-fulltime__a-stress-team-W16-venue-M14.png`, `out/qa/limits/post-prematch__a-stress-team-W16-venue-M14.png`, `out/qa/limits/story-programme__team32-proposal.png` | Add `overflow-wrap: anywhere` (or `overflow: hidden; text-overflow: ellipsis`) on the name and venue boxes. Add `flex-shrink: 0` on the programme time cell and on the score cells. | `template-converter` | No | **Fixed** |
| V6 | `story-fulltime` score card | A logo with a white square background shows as a hard white box on the red card. It looks fine on white backgrounds. | `out/qa/single/story-fulltime/s17-logo-whitebg.png` | Put opponent logos on a white rounded plate in this template (as the initials circle already does), or accept. | `template-converter` | No | **Fixed** |
| V7 | All single templates | A postponed or cancelled match renders as a normal "MATCH DAY" if the user ticks it by hand. The default plan skips it (`RenderPlanner.swift:92`) and a warning is shown. | `out/qa/single/post-prematch/s31-postponed.png` | Add a `{{#match.isPostponed}}RINVIATA{{/match.isPostponed}}` / `isCancelled` badge, or leave it to the warning. | `template-converter` | No | **Fixed** |
| V8 | `story-programme` rows | The secondary text is small for a phone: the opponent line is 24 px and `(C)`/`(T)` is 20 px, roughly 8–9 pt on a 390-pt-wide screen. It is readable but tight. | `out/qa/list/story-programme/L10-worst_p1of1.png` | Optional: 26–28 px for the opponent line, 22 px for the marker. | `template-converter` | No | **Fixed** |
| V9 | `Resources/Templates/README.md:41,57`, `docs/TEMPLATES.md:65` | The guide says "Mustache treats 0 as false" and "`match.venue` may be empty". The production renderer (swift-mustache) treats every number and every string as true, including `0` and `""`. The advice to use `hasScore` is still right, but the reason given is wrong, and the guide does not warn template authors that `{{^match.venue}}` never fires. After V1 is fixed, empty strings are absent and the guide becomes true for venue. | n/a | After V1, state that empty strings are absent, and correct the reason in the 0 note. `Resources/Fixtures/README.md:13` has the same sentence but is frozen (T0.2). | `template-converter` (README), `chore-runner` (TEMPLATES.md) | No | **Fixed** (frozen fixtures README left as is) |
| V10 | `Resources/Templates/story-fulltime/template.html:53`, `story-halftime/template.html:53` (footer handle) | **New, from the V3 fix.** The handle box has `max-width: 50%` with an ellipsis, so any handle longer than about 25 characters is cut to `…` even when the left side of the footer is empty. Settings has no length limit or warning on "Account social", and nothing in the app says the handle was cut. Failing case: handle `@asd.sergnanese.calcio.ufficiale`, no venue, no time: the footer shows `DOM 22 NOV` on the left, about 300 px of free space, then `@ASD.SERGNANESE.CALCIO.UF…`. The same handle also forces `Campo Comunale` (14 characters, within the limit, so no warning) down to `CAMPO COMUN…`. Instagram allows 30-character usernames, so a real handle can hit this. The demo handle and short handles are not affected. | `out/qa/single/story-fulltime/s36-no-venue-notime-longhandle.png`, `out/qa/single/story-fulltime/s39-longhandle-venue14.png`, `out/qa/single/story-halftime/s36-no-venue-notime-longhandle.png` | Drop `max-width: 50%` from the handle (keep `flex-shrink: 0; white-space: nowrap`), so the handle stays whole and the venue span, which already has `min-width: 0` and an ellipsis, gives up the space. Check with a 31-character handle plus a 14-character venue. | `template-converter` | No | **Fixed** (T3.2-fix V10: handle has no max-width, venue gives up the space) |

Not a problem, for the record: a programme page that covers two days ("Weekend in campo") has no day on each row. The planner always makes one set of pages per day (`RenderPlanner.items`), so the app never produces such a page. It appears only in the `list-23` fixture.

## `limits` in the manifests

Every value is **confirmed**. Each was checked with the widest realistic text and a stress string at the limit. The optional raises are improvements, not fixes. None of them is needed for v0.1.0. The re-check on `b0ce149` gives the same result.

| Template | Field | Value | Verdict | Evidence |
|---|---|---|---|---|
| `post-prematch` | `teamName` | 16 | Confirmed. One line in the 340-px column (`CAMPOFELICE ALTA`, `PRATOFIORITOCAS…`). At 24 the name wraps to two lines and the logos stop lining up. | `out/qa/sheets/post-prematch_1.png`, `_2.png`, `out/qa/limits/post-prematch__e-team22-proposal.png` |
| `post-prematch` | `venue` | 14 | Confirmed. Two lines (`CAMPO` / `COMUNALE`). Optional: 18 also fits on two lines (`CENTRO` / `SPORTIVO…`, `ORATORIO` / `SAN LUIGI`). | `out/qa/limits/post-prematch__c-venue18-proposal.png`, `__d-venue18-proposal-b.png` |
| `post-prematch` | `category` | 22 | Confirmed. `GIOVANISSIMI REGIONALI` and 22 × `W` fit on one line. | `out/qa/sheets/post-prematch_5.png`, `out/qa/limits/sheet_1.png` |
| `story-fulltime`, `story-halftime` | `teamName` | 20 | Confirmed. One line next to a two-digit score (`CAMPOFELICE ALTA 12`, `PRATOFIORITOCASTELN…`). Optional: 24 wraps cleanly to two lines. | `out/qa/sheets/story-fulltime_2.png`, `_5.png`, `out/qa/limits/story-fulltime__e-team22-proposal.png` |
| `story-fulltime`, `story-halftime` | `venue` | 14 | Confirmed. The footer stays on one line with a normal handle. Longer venues are now cut with `…` instead of wrapping. | `out/qa/limits/story-fulltime__c-venue18-proposal.png` |
| `story-fulltime`, `story-halftime` | `category` | 22 | Confirmed (`GIOVANISSIMI REGIONALI · GIORNATA 12` in the header). | `out/qa/sheets/story-fulltime_5.png` |
| `story-programme` | `teamName` | 22 | Confirmed (one line, about half the column used). Optional: up to about 28 fits real names (`vs Oratorio San Gerolamo Emiliani…`); the time cell no longer shrinks since V5. | `out/qa/limits/story-programme__current.png`, `__team32-proposal.png` |
| `story-programme` | `venue` | 14 | Confirmed (`CAMPO COMUNALE (C)` stays inside the row; the marker drops to a second line). | `out/qa/list/story-programme/L10_p1of1.png` |
| `story-programme` | `category` | 16 | Confirmed (16 × `W` fits). | `out/qa/limits/story-programme__current.png` |

## Instagram safe zones and contrast

- **Story safe zones:** in every story render, all text and logos sit between y = 250 and y = 1670. The header starts at 250. The fulltime and halftime footers end at 1660. The last programme row ends at about 1645. Only decorative shapes and colour fields enter the top and bottom 250 px. This holds with 3-line notes, clamped 8-line notes, the status badge, 10 programme rows and long handles (re-checked on `b0ce149`).
- **Post:** the 60-px side margins survive Instagram's 3:4 profile-grid crop (about 34 px each side).
- **Contrast with the default accent:** white on `#CF3326` and `#CF3326` on white are 5.0:1, which meets AA for normal text. `#5A4A4C` on `#FFF3F1` (programme opponent line) is 7.7:1. `#1F1214` on white (halftime card) is about 18:1. The initials `#5A4A4C` on white are 8.4:1. A dark accent (`#14213D`) is 16:1. A light accent fails in the image; Settings now warns (V2).

## Re-check list for this task after fixes

- V1: done on `b0ce149`, fixed.
- V2: done from source and unit test. The user should type `#FFE066` in Settings › Immagini once and see the warning (part of U1 in `mac-review.md`).
- V3–V9: done on `b0ce149`, fixed.
- V10: done. s36 and s39 re-rendered by hand in both stories: whole handle, venue cut with an ellipsis.

## User findings

To be filled in by the user after looking at real generated images on the phone (optional for Part A).

| Date | What was checked | Finding |
|---|---|---|
| | | |
