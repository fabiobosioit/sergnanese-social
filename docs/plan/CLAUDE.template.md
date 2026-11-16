# Sergnanese Social

Desktop app (Electron) that generates Instagram/Facebook images for ASD Sergnanese's weekend matches from HTML templates.

## Read first

- `docs/plan/README.md` — scope and decisions
- `docs/plan/01-architecture.md` — stack, layout, contracts, template format
- `docs/plan/tasks/` — the task you were given; read only that task's section

## Rules

- Code against `src/shared/`. That folder is frozen after Wave 0: do not edit it. If a contract is wrong, stop and report.
- Touch only the paths your task owns (table in `01-architecture.md` §2 and in the task sheet).
- Do not add or upgrade dependencies. List what you need in your report.
- Tests are part of the task. `npm run check` must pass before you finish.
- Commit messages start with the task id: `T1.3: render engine`.
- User-visible text is Italian and lives in strings files, never inline.
- The repo is public. Never commit real opponent logos, personal data or secrets. Runtime data lives in the app's userData folder, not in the repo.
- Templates render with the network blocked. Never add an external URL to a template.

## Commands

| Command | What it does |
|---|---|
| `npm run dev` | Start the app in development |
| `VITE_MOCK=1 npm run dev` | UI against the mock API |
| `npm run check` | Typecheck, lint, unit and Electron tests |
| `npm run seed` | Load fake matches for the coming weekends |
| `npm run demo:render` | Render every template from the shared fixtures to `out/demo/` |
| `npm run template:preview -- <id> <fixture>` | Preview one template |
| `npm run dist:mac` | Build the `.dmg` locally |

## Agents

Defined in `.claude/agents/`. Models and roles: `docs/plan/02-agents-and-models.md`.
