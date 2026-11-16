# Wave 4 — After v0.1.0

These tasks are independent of each other and can run in parallel in any combination. They are specified more briefly than Waves 0–3 on purpose: each one gets a full task sheet (same format as Wave 1) written by `foundation-architect` just before it starts, using what was learned from real use.

Contract changes needed by a task are done first, by `foundation-architect`, in a short sequential step.

| Task | Agent | Model | Blocked on |
|---|---|---|---|
| T4.1 CSV/Excel import | `backend-dev` + `ui-dev` | sonnet | sample file from the user |
| T4.2 Website import + logo download | `render-engineer` (scraper) + `ui-dev` | opus + sonnet | tuttocampo page addresses, terms-of-use check |
| T4.3 PDF import | `render-engineer` | opus | sample PDFs |
| T4.4 iPhone access over Wi-Fi | `backend-dev` + `ui-dev` | sonnet | — |
| T4.5 Results workflow | `ui-dev` | sonnet | — |
| T4.6 Captions | `chore-runner` | haiku | — |
| T4.7 Developer-ID signing | `release-engineer` | sonnet | paid Apple Developer account |

---

## T4.1 — CSV/Excel import with review

- Upload `.csv` or `.xlsx`; column mapping screen (date, time, team, opponent, home/away, venue) with the mapping remembered per file layout.
- Rows land in a **staging list**, never straight in the database. Each row is marked new / changed / unchanged / conflict with a locked match.
- Opponent matching by name and aliases with a similarity score; unmatched names offer "create" or "link to existing", and the choice is saved as an alias.
- Commit selected rows; a downloadable template file with the expected columns.
- Model: sonnet. The logic is ordinary; the staging design is fixed by the contract step.

## T4.2 — Website import and logo download

Decision D4: logos come from tuttocampo.it, which the user indicated as the source behind the club site's results page.

- Before any code: confirm the site's terms of use allow automated reading, and keep request rates very low (a few requests per week). If not allowed, this task stops and T4.1 remains the import path.
- Adapter interface `FixtureSource { listTeams(), fetchFixtures(team, range) }` so the source can be replaced when the site changes.
- When checked on 2026-11-16, the club's page (`sergnanese.com/classifiche-e-risultati`) showed only a heading and no match tables in its static content, and appeared to be a Google Sites page. The match data is probably embedded and loaded after the page opens. First step of this task: find the embedded source address in a browser and read that directly.
- Fetch through a hidden Electron window if the data needs JavaScript to appear; otherwise plain HTTP + HTML parsing.
- Results go to the same staging list as T4.1.
- Logo download: for each opponent without a logo, fetch the crest once, store it in `userData/logos/`, never in the repo.
- A health check: zero fixtures found → show "la sorgente potrebbe essere cambiata" instead of silently importing nothing.
- Model: opus for the adapter (unknown page structure, fragile parsing), sonnet for the UI.

## T4.3 — PDF import

- Text extraction from federation-style fixture PDFs, table detection, mapping to staging rows.
- Always through the staging review. Rows the parser is unsure about are flagged.
- Model: opus; PDF layouts vary and parsing needs careful heuristics. Reassess after seeing the user's sample files: if they are regular, sonnet is enough.

## T4.4 — iPhone access over the home Wi-Fi

- Setting "Accesso da telefono": bind the API to the LAN, show the address and a QR code.
- Access protected by a PIN, exchanged for a session cookie; rate-limited.
- Responsive pass on Matches, Generate and Archive; "salva immagine" uses the iOS share sheet so pictures go straight to Photos/Instagram.
- The Mac must be on and the app open. This is documented in the guide.
- Model: sonnet.

## T4.5 — Results workflow

- Quick form per match: half-time score, final score, scorers → one tap to generate the half-time or full-time story.
- Weekly results recap template (new built-in, `kind: list`).
- Model: sonnet. The recap template itself goes to `template-converter`.

## T4.6 — Captions

- For each generated image, a ready caption (Italian) with date, opponent, venue, club hashtags; copy button; editable caption templates in Settings.
- Model: haiku. String templating over existing data.

## T4.7 — Developer-ID signing and notarization

- Only if the first-launch approval step proves to be a real obstacle for other volunteers.
- Needs a paid Apple Developer account and certificates stored as GitHub Actions secrets.
- Model: sonnet.
