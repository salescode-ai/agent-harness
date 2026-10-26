---
name: harness-workspace
description: Set up or refresh a multi-repo workspace — a plain (non-git) folder holding checkouts of several harnessed repos (e.g. backend API, portal UI, mobile app). Writes the workspace map, ownership routing, cross-repo rules, a manifest and make targets that run each changed repo's own gate. Use when one feature spans several repos.
disable-model-invocation: true
---

# Harness Workspace

A workspace is a folder that is **not** a git repo and contains several repos side by side. Each repo keeps its own harness
(`AGENTS.md`, `INVARIANTS.md`, `make check`). The workspace adds only what spans repos: which repo owns which change, the
contract-first rules, one gate that runs every changed repo's own gate, and cross-repo plans.

## Steps

1. **Find the repos.** List immediate subfolders that are git repos (`git -C <dir> rev-parse --show-toplevel` equals the folder). For each: remote URL, default branch, whether it has `AGENTS.md` and a `make check` target. Read the first paragraph of each repo's `AGENTS.md` to learn what it owns.
2. **Confirm with the developer** in one table: repo · path · owns (one line) · merge order. Ask what isn't clear from the repos — especially which repo owns the shared contract. Repos with a partial or no harness get a warning and their gate is skipped, never a failure; mention `harness-init` only as an offer, and never write inside a member repo unless the developer names it.
3. **Write the workspace files** from `assets/` (show each, wait for yes):
   - `harness-workspace.json` — repos (name, path, remote, base, owns) and `mergeOrder`
   - `AGENTS.md` — the routing table, Verification, cross-repo rules, Work Artifacts, Authorization (fill from step 2)
   - `INVARIANTS.md` — cross-repo rules (contract first, merge order, no breaking change without a version)
   - `CLAUDE.md` — `@AGENTS.md` and `@INVARIANTS.md`; `make claude-md` adds each present member's `@<repo>/INVARIANTS.md` (falls back to links over the token budget)
   - `scripts/harness/cmd.sh` — copy of the plugin's `scripts/harness-cmd.sh`; `ws.sh` resolves each member's commands through it
   - `Makefile` + `ws.sh` — `status`, `changed`, `check`, `check-fast`, `setup`, `claude-md`, `test R= T=`, `branch B= R=`, `bootstrap`, `harness-lint`
   - `plans/TEMPLATE.md`, `plans/active/`, `plans/done/`
   - `.claude/settings.json` from `assets/claude/settings.json` (enables the harness plugin when Claude Code starts here)
4. **Validate.** `make harness-lint` and `make status`. Fix every FAIL.
5. **Tell the developer** how to start work: open the agent in the workspace folder, `make branch B=<name> R="<repos>"`, write a cross-repo plan if the feature touches more than one repo.

## How it works at run time

- The session hook shows each repo's branch, uncommitted count and harness status.
- The stop gate runs `make check-fast` in **each changed repo** with that repo's own wiring, and blocks with the repo name on failure.
- `harness-verify` (workspace mode) gates per repo and adds the `cross-repo-reviewer` agent for contract consistency.
- Guards apply everywhere: force-push, hook bypass and pushes to a repo's main branch are caught even via `cd <repo> && git …` or `git -C <repo> …`.

## Notes

- The workspace folder can stay unversioned. If the team wants to share one, keep these files in a small git repo whose `.gitignore` lists every member path, and clone members into it with `make bootstrap`.
- Settings from a member repo's `.claude/settings.json` do not apply when Claude Code starts in the workspace folder; the workspace's own `.claude/settings.json` does. Keep both pinned to the harness plugin.
