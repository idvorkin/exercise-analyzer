# Decision: an outside agent that writes to the repo works in a Herdr worktree (2026-09-26)

## Context

Codex (gpt-6-astra) ran the full code review of 2026-09-25 and made six commits. It worked in a worktree made by
Herdr and started in a pane that lives in that worktree:

```bash
herdr worktree create --cwd ~/gits/exercise-analyzer --branch codex-review --base main
# → ~/.herdr/worktrees/exercise-analyzer/codex-review, plus a pane whose shell starts there
herdr agent start codex-review --kind codex --pane <that pane> -- -s workspace-write -a on-request
```

All six commits landed on `codex-review`, none on `main`. The main checkout was untouched, and `main` took them
as a fast-forward after review (`ea6a802`).

Earlier agents did not do this: a Claude subagent with `isolation: "worktree"` gets a worktree under
`.claude/worktrees/`, but its shell `cd` does not persist between Bash calls. A later `git commit` can then run in
the main checkout and land on whatever branch is checked out there. Eleven such worktrees are still lying around
from earlier Muse and agent runs.

## Decision

- **An outside agent (Codex, Muse) that writes to the repo gets a Herdr worktree**, created with
  `herdr worktree create --branch <name> --base main`, and is started in that worktree's pane. The agent never
  `cd`s into the worktree; its process starts there.
- The agent commits on its own branch and never pushes. I review every commit diff by diff, then `main` takes the
  branch by `git merge --ff-only <name>`.
- Once merged, the worktree and its branch are removed. Nothing is left in `.claude/worktrees/`.
- A Claude subagent that must commit (the Agent tool, `isolation: "worktree"`) passes `-C <worktree>` to every
  git call, or checks `git rev-parse --show-toplevel` before committing.
- Read-only agents are unchanged: a worktree, with notes under `~/tmp/agent/notes/` (AGENTS.md).

## Why

The branch boundary is where review happens. A process that starts inside the worktree cannot commit to `main`
by accident, and a fast-forward shows that `main` gained exactly the reviewed commits.
