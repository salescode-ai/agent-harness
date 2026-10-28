---
name: harness-upgrade
description: Bring a repo's (or workspace's) harness up to the installed plugin version. Refreshes unmodified plugin scripts, runs the versioned structural migrations (safe ones automatically, repo-owned edits as one diff for a single yes), verifies, records the version and logs an audit row. Use after updating the plugin, when the session says "harness scripts are older than the plugin", or when harness-init is re-run on a finished harness. Argument: `[<workspace member>]`.
disable-model-invocation: true
---

# Harness Upgrade

Upgrade, don't re-init. `${CLAUDE_PLUGIN_ROOT}` is this plugin's folder (two levels above this file). The migration registry and what each entry does: `references/migrations.md`.

**Never overwrite human content.** Plugin-owned copies are refreshed only when unmodified; repo-owned files (Makefile, AGENTS.md, INVARIANTS.md, plans, DECISIONS.md, `.claude/settings.json`, `.agents/harness.json`) change only through the one approved diff.

## 0. Where

- **Workspace** (`harness-workspace.json` here, not a git repo). With a first argument naming a member (its `name` or `path`), work **inside that member**: every path below is relative to it. Without one, upgrade the **workspace files only** (`ws.sh`, `scripts/harness/`, `plans/`, workspace `AGENTS.md`) and never write into a member: `migrate.py status` lists each member that is behind as `member <name>: … — run /agent-harness:harness-upgrade <name>`; print those commands exactly.
- No `AGENTS.md` and no `harness-workspace.json`: there is nothing to upgrade. Say "run `/agent-harness:harness-init`" and stop.
- `.harness/init-state.json` lists fewer layers than its target needs: setup is unfinished. Do steps 1–3 here, then say "resume with `/agent-harness:harness-init`".

## 1. Versions and plugin scripts

1. `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/migrate.py" status .` — first line: `plugin: recorded <x> · running <y>`. The recorded version is `"plugin"` in `scripts/harness/assets.json` (`unknown (before 2.0.2)` when absent).
2. `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/assets.py" status .`, then `… assets.py install .`: it refreshes `stale` (unmodified) plugin copies, copies **missing** plugin scripts (new files, e.g. `plan-check.sh`) and never overwrites a `modified` one. List each `modified` line with its printed `diff` command under "Needs you". Refresh `harness.mk` and `lint.sh` together: a newer lint with an older `harness.mk` silently skips check 13.

## 2. Migrations

Run `… migrate.py status .` again (after the refresh). Each line is `<kind> <id> (<since>, <layer>) <file> — <what>`:

1. **auto** — `… migrate.py apply .`: new files, unedited plugin templates, local `.harness/` state. List each under Applied automatically.
2. **propose** — `… migrate.py diff .` prints ONE unified diff for every repo-owned edit. Show it whole, then ask once: "Apply these edits? yes / no / skip <id,…>". Only on yes: `… migrate.py accept .` (with `--skip <ids>` if asked). On no, nothing is written; list them under Still open.
   - `plan-ticket` lines that propose `none (no ticket recorded before 2.0.4)` need a real answer: lint accepts any `none (<reason>)`, so it will **not** flag this fallback later. Ask for the key (or a true reason) per plan before the diff is accepted; a kept fallback goes under Still open.
3. **manual** — each needs a decision or a run; do them with the developer, one short question each (options + ➡️ default), following `references/migrations.md`. `gate-wired` and `gate-red` are done by step 3.

Re-run `… migrate.py status .`: a second run must show nothing but manual items the developer declined. That is the idempotence check; report anything else as a bug.

## 3. Verify

1. `bash scripts/harness/lint.sh` — FAILs are fixed or listed with the file and the fix.
2. Gate in two steps: `R=scripts/harness/cmd.sh; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT}/scripts/harness-cmd.sh"`; `c="$(bash "$R" . check-fast)" || { echo "check-fast not wired (exit $?)"; exit 1; }; eval "$c"`. When it resolved **and** passed, set `"gate_wired": true` in `.harness/init-state.json` (keep every other key); otherwise save `"gate_reason": "<one line>"`. Then prove the gate can fail: `bash scripts/harness/gate-proof.sh` plants one failing test in a scratch worktree; `make test T=<it>`, `make test T=<no such test>` and check-fast must each exit non-zero. It records `"gate_red_proven"` (and `"gate_red_reason"`) in `.harness/init-state.json`. `NOT proven` means a test command swallows its exit code (`; :`) or passes on 0 tests: fix the wiring (layout.md, **Test commands keep their exit code**) and rerun; list a remaining failure under Still open.
3. `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/level.py" . --json --run-checks --log` — measures the level and logs one audit row (workspace: measures each member too).
4. `… assets.py refresh .` once more, so `scripts/harness/assets.json` records `"plugin": "<running version>"`. Commit nothing; the developer reviews and commits.

## 4. Report

```text
Upgrade: <recorded> → <running> · level <before> → <after> (target <t>)
Applied automatically: <n> — <one line each: file · migration id>
Accepted edits: <n files> (one diff) · declined: <ids>
Needs you: <modified plugin copies with their diff command> · <manual migrations left>
Members behind (workspace): /agent-harness:harness-upgrade <name> — one line each
Next: commit the upgrade · /agent-harness:harness-improve to strengthen <top 3 gaps from level.py blockers>
```

In an interactive session, end by asking whether to start `/agent-harness:harness-improve` now.
