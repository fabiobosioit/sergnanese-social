# 04 — Running the plan with Claude Code CLI

## Before you start

1. Clone the repo on the Mac and make sure this plan is on `main`.
2. Install Node (version in `.nvmrc` after T0.1) and Claude Code.
3. From the repo root: `claude --model sonnet`. This session is the **orchestrator**.

How parallel work happens: each task is given to a subagent defined in `.claude/agents/`. The agent's file sets its model, and `isolation: worktree` gives it a private copy of the repo, so several agents edit at once without collisions. Claude Code runs up to 20 subagents at a time by default ([Claude Code docs: subagents](https://code.claude.com/docs/en/sub-agents)); the largest wave here uses 6.

Two things to remember:

- A worktree starts from the **default branch**, not from uncommitted or unmerged work. Merge each wave into `main` before starting the next.
- Background agents ask for permissions in the main session, labelled with the agent's name. Stay near the terminal during a wave.

## Wave 0 (sequential)

Run T0.0 yourself:

```bash
mkdir -p .claude/agents
cp docs/plan/agents/*.md .claude/agents/
cp docs/plan/CLAUDE.template.md CLAUDE.md
git add .claude CLAUDE.md && git commit -m "T0.0: Claude Code agents and project instructions" && git push
```

Restart `claude` so it loads the agents, then paste:

```text
You are the orchestrator for docs/plan. Read docs/plan/README.md, 02-agents-and-models.md and tasks/wave-0-foundation.md.
Run T0.1 with @agent-backend-dev. When it reports, have @agent-qa-reviewer check it against its acceptance criteria, then merge its branch into main.
Then run T0.2 with @agent-foundation-architect, review it the same way, and merge.
Do not write feature code yourself. Stop after the Wave 0 gate and tell me the result.
```

## Wave 1 (6 in parallel)

```text
Read docs/plan/tasks/wave-1-core.md. Dispatch these six tasks in parallel, each to its own subagent in the background:
- T1.1 → @agent-backend-dev
- T1.2 → @agent-template-converter
- T1.3 → @agent-render-engineer
- T1.4 → @agent-chore-runner
- T1.5 → @agent-release-engineer
- T1.6 → @agent-ui-dev
Give each agent only its task id and the path of the task file.
As each one finishes, send its branch to @agent-qa-reviewer. If the review fails, send the findings back to the same agent once; if it fails again, rerun that task one model up.
Merge approved branches into main one at a time, running npm run check after each merge.
When all six are merged, run npm run demo:render, look at the four images, and stop at the Wave 1 gate.
```

## Wave 2 (6 in parallel)

```text
Read docs/plan/tasks/wave-2-features.md. Dispatch in parallel, in the background:
- T2.1 and T2.2 → two separate @agent-backend-dev subagents
- T2.3, T2.5, T2.6 → three separate @agent-ui-dev subagents
- T2.4 → @agent-chore-runner
Same review, retry and merge rules as Wave 1. Stop at the Wave 2 gate.
```

## Wave 3

```text
Read docs/plan/tasks/wave-3-release.md.
Run T3.1 with @agent-backend-dev, review, merge.
Then run T3.2 with @agent-qa-reviewer and T3.3 with @agent-chore-runner in parallel. Dispatch the fixes T3.2 asks for to the owner agents it names, then have T3.2 re-check.
Then T3.4 with @agent-release-engineer: draft release only. Ask me before creating the v0.1.0 tag.
Then T3.5 with @agent-qa-reviewer.
```

## Merge rules for the orchestrator

1. Merge one task branch at a time; run `npm run check` after each.
2. A task that touched a path it does not own is sent back, not merged.
3. New dependencies requested in an agent's report are added by the orchestrator on `main`, in a separate commit, before merging that task.
4. Conflicts in `src/shared/**` mean someone broke the freeze: stop and involve `foundation-architect`.
5. Push `main` at each wave gate.

## Alternative: one terminal per task

If you prefer to watch each agent, create worktrees by hand and start one Claude Code session per task:

```bash
git worktree add ../ss-T1.1 -b task/T1.1 main
cd ../ss-T1.1 && claude --agent backend-dev "Implement T1.1 from docs/plan/tasks/wave-1-core.md"
```

Repeat per task in separate terminals, then merge the `task/*` branches into `main` in any order.

## Keeping cost down

- The orchestrator stays on sonnet and delegates everything.
- Agents read only their own task section and `01-architecture.md`.
- Do not raise `effort` or the model for a whole wave; escalate single tasks only (see `02-agents-and-models.md`).
- Close the session at each gate and start a fresh one for the next wave, so the context does not carry the previous wave.

## Checking progress

Ask the orchestrator at any time:

```text
Show a table of all tasks in docs/plan/tasks with their state: not started / running / in review / merged.
```
