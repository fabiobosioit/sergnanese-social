# Templates

A template is a folder the render engine fills with data and screenshots to a PNG. The format is in
`docs/plan/01-architecture.md` §4 and the data in §5; this page is the short practical version.

```
my-template/
├── manifest.json     id, name, version, size, kind, purpose, requires, limits
├── template.html     plain Mustache, one root element of exactly width × height px
└── assets/
    ├── club-logo.png        required: the club crest, always at this path
    └── fonts/               font files + their licence (OFL.txt)
```

## Rules

- No network. No external URL, no CDN, no Google Fonts link. Fonts are files in `assets/fonts/`,
  declared with relative `@font-face` rules (`url('assets/fonts/Barlow-Bold.ttf')`).
- Plain Mustache only: `{{value}}`, `{{#section}}…{{/section}}`, `{{^inverted}}…{{/inverted}}`. There are no helpers.
  Upper-casing is CSS (`text-transform: uppercase`).
- Text is already cut to the manifest `limits` when it arrives. `limits` are the longest strings the layout holds,
  chosen by looking at a render (use the long-name fixture).
- Keep stories' important content out of the top and bottom 250 px (Instagram UI).
- A little inline `<script>` is allowed (no `src`). Set `window.__ready` to a promise if layout must finish first.
  The programme template uses one to shrink a headline that is too wide.
- Escaped output: `{{x}}` escapes HTML; use it for every user text.

## Fields

`single` templates (one match) receive `{club, match}`; `list` templates receive
`{club, title, dateLabel, rows[], page, hasPages, pageLabel}` where each row is a `match`.

| Field | Meaning |
|---|---|
| `club.name`, `club.shortName`, `club.accent`, `club.season`, `club.handle` | `ASD Sergnanese`, `Sergnanese`, `#CF3326`, `2026/27`, `@account` (may be empty) |
| `club.logo` | `assets/club-logo.png` |
| `match.category` | our team name (list rows: the short label) |
| `match.round`, `match.competition` | number / text, absent when not set |
| `match.dateLong`, `match.dateShort` | `Domenica 22 novembre`, `Dom 22 nov` |
| `match.time` | `15:30`, absent when not set |
| `match.venue` | may be empty |
| `match.isHome`, `match.isAway` | booleans |
| `match.home`, `match.away` | the two sides in fixture order |
| `match.us`, `match.opponent` | the same two sides by role |
| side: `name`, `displayName`, `initials`, `logo`, `isUs`, `score`, `halfTimeScore` | `logo` absent when the club has none |
| `match.hasScore`, `match.hasHalfTime` | both sides have that score |
| `match.halfTime`, `match.notes` | half-time score, free text (absent when empty) |
| `match.isPostponed`, `match.isCancelled` | booleans |

Opponent logos are `_logos/<file>`, the crest is `assets/club-logo.png`; both go straight into `<img src>`.

## Patterns

- Optional text: `{{#match.round}}Giornata {{match.round}}{{/match.round}}`.
- Time or a dash: `{{#match.time}}{{match.time}}{{/match.time}}{{^match.time}}—{{/match.time}}`.
- **Scores: always wrap in `match.hasScore` / `match.hasHalfTime`.** A section on the score itself hides a
  0 (Mustache treats 0 as false):
  `{{#match.hasScore}}{{score}}{{/match.hasScore}}{{^match.hasScore}}–{{/match.hasScore}}`.
- Home/away: print `match.home` on the left and `match.away` on the right (or first/second row), then use
  `{{#isUs}}…{{/isUs}}` inside the side to style our side:
  `{{#match.home}}…{{displayName}}…{{/match.home}}`.
- Logo or initials circle: `{{#logo}}<img src="{{logo}}" alt="">{{/logo}}{{^logo}}<div class="circle">{{initials}}</div>{{/logo}}`.
- Home/away marker in a list row: `{{#isHome}}(C){{/isHome}}{{^isHome}}(T){{/isHome}}`.
- Repeated rows: `{{#rows}}…{{/rows}}`; inside, fields are the row's own (`{{category}}`, `{{opponent.displayName}}`).
- Page number only when there are several pages: `{{#hasPages}}{{pageLabel}}{{/hasPages}}`.

## Check it

```bash
swift run ss-tool preview Resources/Templates/<id> Resources/Fixtures/single.context.json
```

The PNG goes to `out/preview/`. Look at it with: `single`, `single-long-name`, `single-no-logo`,
`single-away`, `single-goalless` (zeros must show), `single-no-time`; list templates use `list` and
`list-23`. The preview tool validates `manifest.json` with SSCore and refuses a bad one; it is a crude checker,
not the production renderer.
