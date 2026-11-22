# Fixtures

Sample data owned by T0.2 and frozen with `Sources/SSCore/`. Everything here is invented: club names,
logos, people and the social handle are fake. Load the files with `SSCoreFakes.Fixtures`.

| File | Content |
|---|---|
| `single.context.json` | The standard `SingleContext`: Prima Squadra at home against an opponent with a logo and a short name. It has time, round, competition, score, half-time score and notes, so the pre-match, half-time and full-time templates all have data. |
| `single-long-name.context.json` | Away, against an opponent whose name is 45 characters long; `displayName` is cut to 16. |
| `single-no-logo.context.json` | An opponent without a logo: no `opponent.logo`, so the template shows the initials. |
| `single-away.context.json` | An away match (`match.away` is us). |
| `single-no-time.context.json` | A match with no time (`match.time` is absent). |
| `single-goalless.context.json` | A played match, 0–0 at half time and at full time. Templates must show the zeros: wrap score blocks in `{{#match.hasScore}}` / `{{#match.hasHalfTime}}`, never in a section on the score itself (Mustache treats 0 as false). |
| `list.context.json` | `ListContext` with 10 programme rows for one day, page 1/1. |
| `list-23.context.json` | `ListContext` with 23 rows, **not** paginated: input for pagination tests and for checking overflow. |
| `matches.json` | The `FakeDataSet` behind `AppServices.fake()`: 13 teams, 14 opponents, 26 matches over three weekends, 4 archive records. Every team but Veterani has a fake tuttocampo widget id `00000000-0000-4000-8000-0000000000NN` (NN = position + 1), the keys of `FakeFixtureSource.scenario` (T4.2). |
| `logos/` | Fake opponent crests (256×256 PNG), named as in `Opponent.logoFile`. |
| `generator/` | The scripts that produced the JSON and the logos. |

## Limits used in the contexts

Contexts are built for one template, so they are already cut to its limits. These use the documented
example limits: single contexts `teamName` 16, `venue` 14, `category` 22; list rows `teamName` 22,
`venue` 14, `category` 16 (list rows show the team's `shortLabel`). A tool rendering a template with
different limits may cut again with `truncateAtWord`.

## Image URLs

- `club.logo` is `assets/club-logo.png` (`TemplateURLs.clubLogo`): every template ships the club crest
  at that path inside its own folder.
- An opponent logo is `_logos/<file>` (`TemplateURLs.logosPrefix`). The render engine serves the logos
  folder under that prefix. **A tool that renders these fixtures must serve `Resources/Fixtures/logos/`
  as `_logos/`.**

## Dates

`matches.json` is built around the weekend of Saturday `referenceSaturday` (2026-11-21):

- previous weekend: 4 matches played, with scores, half-time scores and notes;
- reference weekend ("Questo weekend"): 10 matches, including an away match, a match with no time,
  an opponent with no logo, the 45-character opponent, a postponed match, and a locked manual match;
- next weekend: 12 matches, 11 of them on Sunday, so the programme needs two pages.

`FakeDataSet.shifted(toWeekendOf:)` moves every date by whole weeks so the reference weekend becomes the
current one; `AppServices.fake()` always does this.

## Regenerating

```bash
python3 Resources/Fixtures/generator/gen_fixtures.py Resources/Fixtures
swift Resources/Fixtures/generator/make_logos.swift
```

`SSCoreTests/FixtureTests` checks that the files decode and agree with SSCore's text rules.
