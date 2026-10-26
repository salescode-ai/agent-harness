---
name: harness-garden
description: Garbage-collect the harness — find and fix drift between the harness files and the code (stale paths and commands, dead links, duplicated rules, ADR index gaps, over-budget AGENTS.md, unrouted skills, finished plans left active). Use weekly, after big refactors or dependency upgrades, or when agents start making mistakes the harness should prevent.
---

# Harness Garden

Code changes every day; the harness rots unless someone weeds it. This skill audits, then fixes the safe things and proposes the rest.

## 1. Audit

1. `make harness-lint` — note every FAIL and warn.
2. Dispatch the `harness-auditor` agent (`agent-harness:harness-auditor` when installed as a plugin) (no subagents: follow its procedure yourself).
3. Plans: list `docs/plans/active/*.md` whose Status is done or whose last Progress log line is older than 30 days.
4. Glossary: grep the last 200 commits' diffs for nouns used in new type/function names that are not in `GLOSSARY.md` (`git log -p -n 200 --since=60.days`). List the top 10 candidates only.
5. Plugins: look for files written where `AGENTS.md` Work Artifacts doesn't allow (a plugin's default folder), and for instructions written into `CLAUDE.md`. Fix the path in `AGENTS.md`, not the plugin.

## 2. Fix — safe without asking

- Dead links and renamed paths, where the new path is unambiguous
- `docs/DECISIONS.md` rows missing for existing ADRs (status and date as `TODO` if unknown)
- Finished plans → `docs/plans/done/`
- Duplicated rules → keep the owner's copy, replace others with a link
- Commands in docs that changed name in the Makefile

## 3. Propose — needs a human

- Removing or rewording any rule in `INVARIANTS.md` or Agent Authorization
- Deleting footguns (the trap may still exist)
- New glossary terms (definitions come from people)
- Trimming AGENTS.md to fit the budget: say what moves where

## 4. Close

Run `make harness-lint` and `make check`. Report:

```
Harness health: <before> → <after>
Fixed: <n> — <one line each>
Needs a decision: <n> — <one line each>
Next garden: <date, 7 days out>
```

Open a single PR titled `chore(harness): garden <YYYY-MM-DD>` if Agent Authorization allows; otherwise leave the branch for review.
