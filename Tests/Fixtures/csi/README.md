# CSI fixtures (sanitised)

These HTML files are **sanitised, hand-built** samples of a CSI Live "girone" page, used by the CSI parser tests.

- Derived from the *structure* of a real page that the club saved from its browser (the rendered DOM after the page scripts ran, `slick-initialized` carousel). The real page itself is not in the repo.
- Everything that identifies real people or clubs was replaced: club names (`ASD Esempio Uno`, `US Esempio Due 2016`, ...), venues, committee, trophy name, team ids (fake `9000000x`), match codes (fake `P999xx`), logo file names and the `?j=` tokens. The club name `Sergnanese` is kept, as the parser looks for it.
- Kept as in the real page: the markup of the calendar (`div.label-giornata`, `div.row-card`, `div[data-time=timegC]`, `a.btn-gara` with the `data-bs-title` venue tooltip, `span.js-gg-min`, `span.nome-squadra`, `img` with the team id in `alt`, `div.js-gg-pt` score spans, `-` when not played), the `<title>`, and unrelated page parts (navigation, standings table) the parser must skip.
- The calendar is repeated 3 times, as the real page repeats it in several views (550 `btn-gara` for 110 matches there). Parsers must dedupe by the match code in the `href`.
- No real data. Do not paste real pages here.

| File | Content |
|---|---|
| `girone-sample.html` | 8 matches (P999A1 to P999A8): ours at home played (3-1), ours away played (0-4), ours at home not played, ours away not played, plus matches without us (a draw, a forfeit-style score in red, not played). One opponent has the CSI placeholder shield instead of a logo. |
| `girone-no-ours.html` | Same structure, 4 matches, none involving Sergnanese. |
| `girone-no-table.html` | Page without any match row (calendar empty message). |
