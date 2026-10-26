---
name: harness-verify
description: Verification gate before claiming work is done, fixed or passing, and before any commit or PR. Runs the repo's check gate, then independent verifier, invariants-reviewer and scope-guard agents in parallel, and reports evidence. Use whenever you are about to say "done", "fixed", "tests pass" or "ready for review".
---

# Harness Verify

Evidence before claims. You do not get to say a change works; the gate and the reviewers do.

## 1. Frame the check (one message, no tools)

Write down, in three lines:
- **Request:** what was asked, in one sentence.
- **Acceptance criteria:** from the active plan in `docs/plans/active/`, the ticket, or the spec. If none exist, derive 1–5 checkable criteria from the request and label them "derived".
- **Scope:** uncommitted changes, or `<base>...HEAD`.

## 2. Computational gate (deterministic, cheap first)

**Resolver** (`$R` below): `R=scripts/harness/cmd.sh; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT}/scripts/harness-cmd.sh"` — a v1 repo without `scripts/harness/cmd.sh` uses the plugin's copy (same contract).

Commands are resolved, not assumed: `bash "$R" . <target>` prints the repo's command (from `.agents/harness.json`, default `make <target>`); run it in two steps so an unwired target can't pass silently: `c="$(bash "$R" . check)" || { echo "check not wired (exit $?)"; exit 1; }; eval "$c"`. Exit 3 (not wired) or 4 (make missing) is **not** a pass: say so under Open, and never report the gate green.

Run in order, stop at the first failure and fix it before going on:
1. `check-fast`
2. `check`
3. `smoke` — only if the change touches a runnable surface and the target is wired

Read the real output. A command you did not run in this turn does not count.

## 3. Inferential gate (independent reviewers)

Dispatch these agents **in parallel** (installed as a plugin they are named `agent-harness:verifier`, `agent-harness:invariants-reviewer`, `agent-harness:scope-guard`), each with the request, the criteria and the scope. They did not write the change, so they are not grading their own work:

| Agent | Checks | Skip when |
|---|---|---|
| `verifier` | criteria have real evidence; tests are meaningful; no verification theatre | never |
| `invariants-reviewer` | INVARIANTS.md, module AGENTS.md footguns, ADRs, glossary terms | change is docs-only |
| `scope-guard` | every hunk traces to the request; nothing speculative or destructive | change is < 20 lines and single-file |

No subagents in your tool (Codex, Cursor, others)? Run each agent's procedure yourself, one at a time, in a fresh pass that re-reads the diff from disk. The checklists are the agent files (`agents/<name>.md` in this plugin, or `.agents/agents/<name>.md` when installed locally).

## Workspace mode (several repos)

If `harness-workspace.json` sits above the current folder and the current folder is not itself a repo, you are in a multi-repo workspace:

1. `make changed` lists the repos with changes. Steps 2–3 run **per changed repo**, from inside it: `check-fast`, then `check`, each resolved with `$R` from inside that repo; and the three reviewers get that repo's diff and read that repo's `INVARIANTS.md` and `AGENTS.md`.
2. When more than one repo changed, also dispatch `cross-repo-reviewer` (`agent-harness:cross-repo-reviewer`) with the workspace root, the request and the cross-repo plan. It checks ownership, contract consistency, backward compatibility and merge order.
3. Report one block per repo plus the cross-repo verdict. The work is done only when every repo passes and the cross-repo verdict is ALIGNED.

## 4. Decide

| Result | Action |
|---|---|
| Gate green, verifier PASS, reviewers CLEAN/TIGHT | Report done with the evidence block below |
| Any FAIL / VIOLATIONS / TRIM | Fix, then rerun from step 2. Max 3 rounds, then stop and report to the human |
| NEEDS-HUMAN, an Authorization escalation, or a hit on an invariant with `Severity: Important` | Stop. Report it as NEEDS-HUMAN with the rule and file:line |
| SPLIT | Move the out-of-scope hunks to a separate branch or note; re-verify |

If the same kind of failure appears twice, run the **harness-learn** skill after you finish so the harness catches it next time.

## 5. Report (paste into the reply or PR description)

```
Verified: <request>
Gate: check ✓ `<resolved command>` (<n> tests) · smoke ✓|n/a
Criteria: <k>/<n> with evidence — <criterion → test/command>, …
Reviewers: verifier PASS · invariants CLEAN · scope TIGHT
Open: <anything not verified, and why>
Plan: <docs/plans/active/<plan>.md> · Evidence: <.harness/evidence/<plan file name>> (local)
```

Never write "should work", "looks good" or "tests should pass". If you could not verify something, say so under Open.

## 6. Persist the evidence

Every run that reaches a verdict **appends** this block to the local evidence file `.harness/evidence/<active plan file name>` (no active plan: `.harness/evidence/<branch slug>.md`; create the folder; never edit earlier entries): `### <YYYY-MM-DD> · <commit> · <PASS | FAIL | NEEDS-HUMAN>`, where `<commit>` is `uncommitted` only when `git status --porcelain -- . ':!docs/plans' ':!plans' ':!.harness'` lists files, else `git rev-parse --short HEAD`, then the Gate, Criteria, Reviewers and Open lines above. `.harness/` is gitignored: evidence is **never committed** and never written into the plan. No active plan → say so and suggest creating one from `docs/plans/TEMPLATE.md`; never invent a plan. Workspace mode: `<workspace>/.harness/evidence/<cross-repo plan file name>`, one block per repo (`### <date> · <repo> · <commit> · <verdict>`).

The PR description and the tracker comment reuse this same block with the plan path and the local evidence path; they are where others see it. On "done" with a ticketed plan, offer the tracker comment exactly as harness-session Close step 4 says: show the draft (evidence block + plan path + next step, and a proposed transition when the plan is done), post only after the developer says yes via an available connector or CLI, never store tokens, else print it for copy-paste.
