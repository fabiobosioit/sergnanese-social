# 02 — Agents and models

## 1. Choosing the model

Claude Code accepts the aliases `haiku`, `sonnet`, `opus` and `fable` in a subagent's `model` field ([Claude Code docs: subagents](https://code.claude.com/docs/en/sub-agents)). Cost rises in that order, so the rule is: **use the cheapest model that can finish the task without rework.** Check current prices on Anthropic's pricing page before a large run.

| Model | Use it for | In this plan |
|---|---|---|
| **haiku** | Work that is fully specified and mechanical: fixtures, seed data, config files, simple CRUD screens built from existing components, docs. | T1.4, T2.4, T3.3 |
| **sonnet** | Normal feature work: database layer, API routes, React pages, CI workflow, tests. The default. | 12 tasks |
| **opus** | Tasks where a wrong decision costs every later task, or that need careful reasoning: shared contracts, the render engine, visual QA, final review. | T0.2, T1.3, T3.2, T3.5 |
| **fable** | Not assigned. Last step of escalation only. | — |

Why not opus everywhere: 12 of the 20 tasks are ordinary, well-bounded coding against frozen contracts. Paying more there buys little.

Why not haiku everywhere: the three haiku tasks have no design decisions. The rest have some, and a failed cheap run that needs a second, more expensive run costs more than doing it once on sonnet.

### Escalation ladder

1. A task fails its acceptance criteria → the same agent retries once with the reviewer's findings.
2. Fails again → rerun the task one model up (`haiku → sonnet → opus → fable`) by passing a model override when dispatching.
3. A task needs a contract change → stop; send the request to `foundation-architect` (opus). Never patch `src/shared/` inside a feature task.

### Effort

Agents set `effort` in their definition: `medium` for sonnet implementers, `high` for opus agents. Haiku agents leave it unset. Raise it for a single dispatch only when a task is stuck.

## 2. Agent roster

Definitions are in `docs/plan/agents/`. Task T0.0 copies them to `.claude/agents/`.

| Agent | Model | Isolation | Role | Tasks |
|---|---|---|---|---|
| `foundation-architect` | opus | worktree | Scaffold decisions, shared contracts, any later contract change | T0.2 (+ contract changes) |
| `backend-dev` | sonnet | worktree | Scaffold, database, API routes, wiring | T0.1, T1.1, T2.1, T2.2, T3.1 |
| `render-engineer` | opus | worktree | Template loading/validation and the HTML→PNG engine | T1.3 |
| `template-converter` | sonnet | worktree | Converts design exports into app templates, checks them visually | T1.2 |
| `ui-dev` | sonnet | worktree | UI shell and feature pages | T1.6, T2.3, T2.5, T2.6 |
| `chore-runner` | haiku | worktree | Seed data, simple CRUD pages, docs | T1.4, T2.4, T3.3 |
| `release-engineer` | sonnet | worktree | electron-builder, GitHub Actions, releases | T1.5, T3.4 |
| `qa-reviewer` | opus | none (read-only) | Reviews a finished task or wave in a fresh context; visual QA | wave gates, T3.2, T3.5 |

Every implementing agent runs with `isolation: worktree`, so six agents can edit at the same time without touching each other's files.

**Important:** a worktree is created from the repository's default branch, not from the session's current commit ([Claude Code docs: subagents](https://code.claude.com/docs/en/sub-agents)). So each wave must be merged into `main` before the next wave starts.

## 3. Rules every implementing agent follows

These are written into each agent definition:

1. Read `CLAUDE.md`, `docs/plan/01-architecture.md` and your task's section. Read nothing else unless the task needs it.
2. Touch only the paths your task owns. Never edit `src/shared/**`, `package.json` dependencies, or another task's folder. If you need a new dependency, list it in your final report; the orchestrator adds it.
3. Code against the contracts in `src/shared/`. If a contract is wrong or missing, stop and report; do not work around it.
4. Write tests with the code. Run `npm run check` (typecheck, lint, tests) before finishing. It must pass.
5. Commit on your worktree branch with a message starting with the task id, e.g. `T1.1: database layer`.
6. Final report: what was built, files changed, the commands run and their result, anything unfinished or uncertain.

## 4. The orchestrator

The orchestrator is the main Claude Code session, the one the user types into. It does not write feature code. Per wave it:

1. dispatches the wave's tasks to their agents in parallel;
2. collects reports and sends each finished task to `qa-reviewer`;
3. merges approved task branches into `main`, adds requested dependencies, runs `npm run check` on `main`;
4. stops and asks the user at each wave gate.

Run the orchestrator on **sonnet**. Switch to opus only to resolve a difficult merge.

## 5. Review gates

| Gate | Checked by | Passes when |
|---|---|---|
| Task done | `qa-reviewer` | Acceptance criteria met, only owned paths touched, `npm run check` green |
| Wave done | orchestrator + user | All tasks merged, `npm run check` green on `main`, wave demo works |
| Release | `qa-reviewer` (T3.5) + user | Installed `.dmg` works on the user's Mac |
