# PDF fixtures (synthetic)

Federation calendar PDFs for the T4.3 parser tests. **Everything is invented**: club names (`ESEMPIO UNO`, ...), grounds, addresses, club numbers. The club name `SERGNANESE` is kept because the parser looks for it. The real sample the layout was measured on is not in the repo and must never be added.

The geometry (column positions, line spacing, font sizes, drawing order, name forms) copies the real file; see `docs/plan/notes/t4.3-pdf-spike.md`. The PDFs are made with CoreGraphics and CoreText, so the text is real (selectable) text, as in the real file.

| File | Content |
|---|---|
| `calendar-sample.pdf` | 2 pages. Page 1: 9 matchdays in a 3 x 3 grid, 4 matches plus one `Riposo` line each, 9 clubs, every pair once. Page 2: the club table (club, number, ground, address, time, day), sorted by long name. One club plays on Sunday. |
| `calendar-missing-club.pdf` | Same page 1. Page 2 has no row for `ESEMPIO SEI` (8 rows), so that club has no ground, time or day. |
| `not-a-calendar.pdf` | One page of invented invoice text. Not a federation calendar: the parser must refuse it. |
| `calendar-sample.expected.json` | Ground truth for `calendar-sample.pdf`: matchdays (number, ISO date of the matchday, matches home/away, resting club) and the club table with short and long names. |
| `calendar-missing-club.expected.json` | Same, with `null` ground, address, time and day for `ESEMPIO SEI`. |
| `generate.swift` | Regenerates all of the above: `swift Tests/Fixtures/pdf/generate.swift [output-folder]` from the repo root. |

Notes for tests:

- The `date` in the expected JSON is the date printed in the matchday header (a Saturday). A club whose `day` is `Domenica` plays that matchday one day later; this is the spike's inference from the real file and is not encoded in the JSON.
- The short names on page 1 differ from the long names on page 2 on purpose (legal suffixes, `S.` for `SAN`, `Sq.B` against `sq.B`).
- PDF files carry a creation date, so regenerating changes the bytes. Commit regenerated files only when the layout changed.
