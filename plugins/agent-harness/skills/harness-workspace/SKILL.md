---
name: harness-workspace
description: Set up or refresh a multi-repo workspace — a plain (non-git) folder holding checkouts of several harnessed repos (e.g. backend API, portal UI, mobile app). Writes the workspace map, ownership routing, cross-repo rules, a manifest and make targets that run each changed repo's own gate. Use when one feature spans several repos.
disable-model-invocation: true
---

# Harness Workspace

A workspace is a folder that is **not** a git repo and contains several repos side by side. Each repo keeps its own harness
(`AGENTS.md`, `INVARIANTS.md`, a `check` command). The workspace adds only what spans repos: which repo owns which change, the
contract-first rules, one gate that runs every changed repo's own gate, and cross-repo plans.

## Steps

1. **Find the repos.** List immediate subfolders that are git repos (`git -C <dir> rev-parse --show-toplevel` equals the folder; a worktree's `.git` file counts). For each: remote URL, default branch, harness state (**present** = `AGENTS.md` + `INVARIANTS.md` + a `check` command resolved by `${CLAUDE_PLUGIN_ROOT}/scripts/harness-cmd.sh <repo> check`; **partial** = some; **none**). Read the first paragraph of each `AGENTS.md` to learn what it owns. A member with no remote or not checked out is a warning, never a stop.
2. **Confirm with the developer** in one table: repo · path · harness · owns (one line) · merge order. Ask what isn't clear from the repos, especially which repo owns the shared contract. Partial or none → a warning and a visibly skipped gate, never a failure.
3. **Write the workspace files** (workspace folder only; show them, one yes):
   - `harness-workspace.json` from `assets/harness-workspace.json`: repos (name, path, remote, base, `harness`, owns) and `mergeOrder`.
   - `AGENTS.md` from `assets/AGENTS.md`: routing table linking each member's `AGENTS.md`, Verification, cross-repo rules, Work Artifacts, Authorization.
   - `INVARIANTS.md` from `assets/INVARIANTS.md`: contract first, follow the merge order, no breaking API change without a version.
   - `scripts/harness/cmd.sh` ← `${CLAUDE_PLUGIN_ROOT}/scripts/harness-cmd.sh`; `ws.sh` resolves each member's commands through it.
   - `Makefile` + `ws.sh` from `assets/`: `status`, `changed`, `check`, `check-fast`, `setup`, `claude-md`, `test R= T=`, `branch B= R=`, `bootstrap`, `harness-lint`.
   - `CLAUDE.md`: run `make claude-md` (imports `@AGENTS.md`, `@INVARIANTS.md` and each present member's `@<repo>/INVARIANTS.md`; falls back to links with a warning over the token budget).
   - `plans/TEMPLATE.md`, `plans/active/`, `plans/done/` from `assets/plans/`.
   - `.claude/settings.json` from `assets/claude/settings.json`. Claude Code may refuse this write; then show the content for the developer to add.
4. **Local wiring (`.env.workspace`).** Read the backend's local port from `<backend>/.env.local` (written by its `make setup`; if missing, say "run `make setup` first" and leave a `TODO`). Write `.env.workspace` in the workspace folder only, e.g. `API_BASE_URL=http://localhost:<port>`, one line per frontend or app member. For each, name the member env var that consumes it (found in that member's `.env.example` or config with `file:line`, else `[verify]`) and tell the developer to copy it there. Never write into a member's `.env` or `.env.local`.
5. **Cross-repo sensors (optional).** Offer read-only checks such as "backend OpenAPI spec matches the frontend client types", wired into workspace `check`. They read members, never write them.
6. **Validate.** `make harness-lint` and `make status`. Fix every FAIL in workspace files; member gaps stay warnings.
7. **Tell the developer** how to start work: open the agent in the workspace folder, `make setup` (each present member's setup, in merge order), `make branch B=<name> R="<repos>"`, and a cross-repo plan in `plans/active/` when a feature touches more than one repo.

**Never write inside a member repo** unless the developer names it ("create harness for portal"). Then run `harness-init` inside that repo, with its own interview.

## How it works at run time

- The session hook shows each repo's branch, uncommitted count and harness status.
- The stop gate runs `check-fast` (resolved through `scripts/harness/cmd.sh`) in **each changed repo** with that repo's own wiring, and blocks with the repo name on failure. Repos without a harness are skipped, visibly.
- `harness-verify` (workspace mode) gates per repo and adds the `cross-repo-reviewer` agent for contract consistency.
- Guards apply everywhere: force-push, hook bypass and pushes to a repo's main branch are caught even via `cd <repo> && git …` or `git -C <repo> …`.

## Notes

- The workspace folder can stay unversioned. If the team wants to share one, keep these files in a small git repo whose `.gitignore` lists every member path, and clone members into it with `make bootstrap`.
- Settings from a member repo's `.claude/settings.json` do not apply when Claude Code starts in the workspace folder; the workspace's own `.claude/settings.json` does. Keep both pinned to the harness plugin.
