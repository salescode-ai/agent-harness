---
name: harness-learn
description: Turn an agent mistake, a review comment, an incident or a human correction into a durable harness change, choosing the strongest enforcement that fits — lint rule or test, then hook, then INVARIANTS.md, then a footgun, ADR or glossary entry. Use after a repeated failure, a "don't do that again" from a human, or a post-incident review.
---

# Harness Learn

Every time an agent struggles, the harness is missing something. Fix the harness, not just the code, so the next agent does not repeat it. This is how the harness grows: by ratchet, one real failure at a time.

## 1. Capture

Write in four lines:
- **What happened:** the wrong action, with file:line or command.
- **What should have happened:**
- **Why the agent did it:** missing information · ambiguous instruction · wrong default from a skill · no check caught it.
- **Has it happened before?** Search: `git log --grep`, `AGENTS.md`, `INVARIANTS.md`, `docs/adr/`.

## 2. Choose the strongest fix that fits

Prefer the top of this ladder. A rule a machine checks beats a rule an agent must remember.

| Rung | Use when | Where | Example |
|---|---|---|---|
| 1. Sensor (lint rule / structural test) | The bad pattern is detectable in code | dispatch `sensor-smith`: existing linter, arch test, repo test or `scripts/harness/sensors/` | ban importing `db` from `handlers/` |
| 2. Hook | It is an action, not code (a command, a file write) | `.claude/settings.json` hooks, or the plugin guard | block `git push --force` |
| 3. Check step / CI step | A check exists but is not run | `harness.mk` (or `.agents/harness.json`), CI workflow | add migration dry-run to `check` |
| 4. Invariant | A hard rule a machine can't check yet | `INVARIANTS.md`: `- <rule> — Severity: <Critical\|Important\|Nice-to-have> — Enforced by: not yet enforced` | "no PII in logs" |
| 5. Footgun | A trap with a known safe path | root or module `AGENTS.md` (one line + ADR link) | "dates are IST in the DB" |
| 6. Routing / artifact line | A skill used the wrong default | `AGENTS.md` Skills and plugins or Work Artifacts | plans go in `docs/plans/active/` |
| 7. ADR | The *why* behind a choice was missing | `docs/adr/NNNN-*.md` + index row | why we keep the legacy API |
| 8. Glossary | Wrong or inconsistent domain word | `GLOSSARY.md` | "outlet", not "store" |

Write rules as instructions with the reason, not just prohibitions: *"Use `Money` for amounts — floats lost paise in the 2026-03 billing incident."*

## 3. Apply

1. Make the smallest change on the chosen rung. Rung 1: dispatch the `sensor-smith` agent (`agent-harness:sensor-smith`) with the invariant line and `.harness/scan.json`; it is wired in only after `bash scripts/harness/sensor-proof.sh <name>` passes. Rungs 2–3: write a failing example first and show the check catching it.
   Every new invariant carries a severity (Critical fails `check`; Important goes to a human in `harness-verify`; Nice-to-have shows in the audit) — ask the developer which.
2. Check you did not duplicate an existing rule (one owner per fact). Update instead of adding.
3. Changes to `INVARIANTS.md` or Agent Authorization need a human yes — propose, don't write.
4. Run `bash scripts/harness/lint.sh` and the check command: `eval "$(bash scripts/harness/cmd.sh . check)"` (default `make check`).

## 4. Prune

While you are there: is any rule now redundant (a lint rule now covers it, the code it warned about is gone)? Propose removing it. A harness that only grows becomes noise.

## Report

```
Learned: <one line>
Fix: rung <n> — <file> — <change>
Caught by: <check that now fails on the bad pattern> | human review
Pruned: <rule removed, or none>
```
