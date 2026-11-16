# Wave 4 — After v0.1.0

These tasks are independent of each other and can run in parallel in any combination. They are specified more briefly than Waves 0–3 on purpose: each one gets a full task sheet (same format as Wave 1) written by `foundation-architect` just before it starts, using what was learned from real use.

Contract changes needed by a task are done first, by `foundation-architect`, in a short sequential step.

From here on the user has real data on this Mac. Every task keeps working in the Dev data folder; nothing may open the release data folder.

| Task | Agent | Model | Blocked on |
|---|---|---|---|
| T4.1 CSV/Excel import | `core-dev` + `ui-dev` | sonnet | sample file from the user |
| T4.2 Website import + logo download | `render-engineer` (scraper) + `ui-dev` | opus + sonnet | tuttocampo page addresses, terms-of-use check |
| T4.3 PDF import | `render-engineer` | opus | sample PDFs |
| T4.4 Shortcuts support | `ui-dev` | sonnet | — |
| T4.5 Results workflow | `ui-dev` | sonnet | — |
| T4.6 Captions | `ui-dev` | sonnet | — |
| T4.7 Developer-ID signing and in-app updates | `release-engineer` | sonnet | paid Apple Developer account |

---

## T4.1 — CSV/Excel import with review

- Open or drop a `.csv` or `.xlsx`; column mapping screen (date, time, team, opponent, home/away, venue) with the mapping remembered per file layout.
- Rows land in a **staging list**, never straight in the database. Each row is marked new / changed / unchanged / conflict with a locked match.
- Opponent matching by name and aliases with a similarity score; unmatched names offer "create" or "link to existing", and the choice is saved as an alias.
- Commit selected rows; an exportable template file with the expected columns.
- Model: sonnet. The logic is ordinary; the staging design is fixed by the contract step. `.xlsx` reading needs a library, chosen in the contract step.

## T4.2 — Website import and logo download

Decision D4: logos come from tuttocampo.it, which the user indicated as the source behind the club site's results page.

- Before any code: confirm the site's terms of use allow automated reading, and keep request rates very low (a few requests per week). If not allowed, this task stops and T4.1 remains the import path.
- Adapter protocol `FixtureSource { listTeams(), fetchFixtures(team, range) }` so the source can be replaced when the site changes.
- When checked on 2026-11-16, the club's page (`sergnanese.com/classifiche-e-risultati`) showed only a heading and no match tables in its static content, and appeared to be a Google Sites page. The match data is probably embedded and loaded after the page opens. First step of this task: find the embedded source address in a browser and read that directly.
- Fetch through an off-screen `WKWebView` if the data needs JavaScript to appear; otherwise `URLSession` + HTML parsing.
- Results go to the same staging list as T4.1.
- Logo download: for each opponent without a logo, fetch the crest once, store it through `LogoStore`, never in the repo.
- A health check: zero fixtures found → show "la sorgente potrebbe essere cambiata" instead of silently importing nothing.
- This is the first feature that uses the network; the security notes in `01-architecture.md` §8 are updated with it.
- Model: opus for the adapter (unknown page structure, fragile parsing), sonnet for the UI.

## T4.3 — PDF import

- Text extraction from federation-style fixture PDFs with PDFKit, table detection, mapping to staging rows.
- Always through the staging review. Rows the parser is unsure about are flagged.
- Model: opus; PDF layouts vary and parsing needs careful heuristics. Reassess after seeing the user's sample files: if they are regular, sonnet is enough.

## T4.4 — Shortcuts support

- App Intents for "Genera le immagini del weekend" and "Mostra le partite del weekend", so the weekly job can be started from Shortcuts or Spotlight.
- Needs a check that App Intents metadata can be produced without Xcode; if not, this task waits for T4.7's toolchain decision.
- Model: sonnet.

## T4.5 — Results workflow

- Quick form per match: half-time score, final score, scorers → one click to generate the half-time or full-time story and open the share picker.
- Weekly results recap template (new built-in, `kind: list`).
- Model: sonnet. The recap template itself goes to `template-converter`.

## T4.6 — Captions

- For each generated image, a ready caption (Italian) with date, opponent, venue, club hashtags; copied with the image or on its own; editable caption patterns in Settings.
- Model: sonnet. Small, but it touches the gallery component and Settings.

## T4.7 — Developer-ID signing, notarization and in-app updates

- Only if the first-launch approval step proves to be a real obstacle for other volunteers.
- Needs a paid Apple Developer account and certificates stored as GitHub Actions secrets.
- With proper signing, add in-app updates (Sparkle) so "Scarica aggiornamenti…" installs the new version itself.
- Model: sonnet.
