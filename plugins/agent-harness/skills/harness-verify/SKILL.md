---
name: harness-verify
description: Verification gate before claiming work is done, fixed or passing, and before any commit or PR. Runs the repo's make gate, then independent verifier, invariants-reviewer and scope-guard agents in parallel, and reports evidence. Use whenever you are about to say "done", "fixed", "tests pass" or "ready for review".
---

# Harness Verify

Evidence before claims. You do not get to say a change works; the gate and the reviewers do.

## 1. Frame the check (one message, no tools)

Write down, in three lines:
- **Request:** what was asked, in one sentence.
- **Acceptance criteria:** from the active plan in `docs/plans/active/`, the ticket, or the spec. If none exist, derive 1–5 checkable criteria from the request and label them "derived".
- **Scope:** uncommitted changes, or `<base>...HEAD`.

## 2. Computational gate (deterministic, cheap first)

Run in order, stop at the first failure and fix it before going on:
1. `make check-fast`
2. `make check`
3. `make smoke` — only if the change touches a runnable surface and the target exists

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

1. `make changed` lists the repos with changes. Steps 2–3 run **per changed repo**: `make -C <repo> check-fast`, then `make -C <repo> check`, and the three reviewers get that repo's diff and read that repo's `INVARIANTS.md` and `AGENTS.md`.
2. When more than one repo changed, also dispatch `cross-repo-reviewer` (`agent-harness:cross-repo-reviewer`) with the workspace root, the request and the cross-repo plan. It checks ownership, contract consistency, backward compatibility and merge order.
3. Report one block per repo plus the cross-repo verdict. The work is done only when every repo passes and the cross-repo verdict is ALIGNED.

## 4. Decide

| Result | Action |
|---|---|
| Gate green, verifier PASS, reviewers CLEAN/TIGHT | Report done with the evidence block below |
| Any FAIL / VIOLATIONS / TRIM | Fix, then rerun from step 2. Max 3 rounds, then stop and report to the human |
| NEEDS-HUMAN or an Authorization escalation | Stop. Report what needs a decision |
| SPLIT | Move the out-of-scope hunks to a separate branch or note; re-verify |

If the same kind of failure appears twice, run the **harness-learn** skill after you finish so the harness catches it next time.

## 5. Report (paste into the reply or PR description)

```
Verified: <request>
Gate: make check ✓ (<n> tests) · make smoke ✓|n/a
Criteria: <k>/<n> with evidence — <criterion → test/command>, …
Reviewers: verifier PASS · invariants CLEAN · scope TIGHT
Open: <anything not verified, and why>
```

Never write "should work", "looks good" or "tests should pass". If you could not verify something, say so under Open.
