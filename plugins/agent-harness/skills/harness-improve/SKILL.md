---
name: harness-improve
description: Strengthen an existing harness from evidence. Measures the gaps (level, TODO and [verify] markers, not-yet-enforced invariants, skeletal sections, missing module guides, team rollout settings, stale scripts), mines git history and the code for concrete suggestions (footguns, invariants, ADRs, glossary terms, context-loading rows, sensors), then interviews one area at a time and applies only what the developer accepts. Use after harness-init or harness-audit, or when the harness is "set up but thin".
---

# Harness Improve

Evidence, then questions, then edits. `${CLAUDE_PLUGIN_ROOT}` is this plugin's folder (two levels above this file). Commands for every check and mining step: `references/improve.md`.

**While this skill runs, it is the process.** Do not start planning, test-first, review or interview skills from other plugins.

## Ground rules

- **Never invent.** Every suggestion cites its evidence: a commit (`<sha> <subject>`), a `file:line`, a lint or CI failure. No evidence → no suggestion. Generic advice is not a suggestion.
- **One owner per fact** (`harness-init/references/layout.md`): a rule goes to `INVARIANTS.md`, a trap to `AGENTS.md` Footguns, a term to `GLOSSARY.md`, a decision to `docs/adr/` + `docs/DECISIONS.md`, module rules to `<module>/AGENTS.md`. Never the same fact in two files.
- **Up the ladder.** A rule a machine can check is not left as prose: route it to the `sensor-smith` agent (`agent-harness:sensor-smith`; no subagents → follow `${CLAUDE_PLUGIN_ROOT}/agents/sensor-smith.md` yourself), which proves it on a planted fixture before it is wired. Until then the invariant says `Enforced by: not yet enforced`.
- Stay within the `target` level; for work beyond it, say what the next level needs in one line.

## 1. Status first (measure, no edits)

Run the status block in `references/improve.md` and show one table:

```text
Level: <measured> · target: <t> · blockers: <next_level_blockers>
Gap                                 Where                         Count
TODO / [verify] markers             AGENTS.md:12, docs/SETUP.md…  7
Invariants not yet enforced         INVARIANTS.md                 3
Skeletal sections                   Agent Authorization, Footguns 2
risk_paths without module AGENTS.md src/payments/, db/migrations/ 2
Team rollout settings missing       .claude/settings.json         1
Stale plugin scripts / last audit   assets.py · AUDIT-LOG.md      0 · 41 days
```

**Team rollout settings missing** is a gap whenever `.claude/settings.json` lacks `extraKnownMarketplaces.agent-harness` or `enabledPlugins["agent-harness@agent-harness"]`: without them teammates' Claude Code sessions get no hooks, skills or reviewer agents. Stale scripts → hand to `/agent-harness:harness-upgrade` first.

## 2. Mine evidence (no edits)

For each area in `references/improve.md` → Areas, run its mining commands and keep only findings with evidence. Rank areas by: blockers to the target first, then Critical gaps, then most evidence. Skip an area with nothing found.

## 3. Interview: one area per round

Every round has exactly this shape. Show one, wait, apply, then the next:

```text
## Footguns — traps an agent walks into
Area:    things that broke before and will break again; AGENTS.md → Footguns
Found → Suggest
  a3f1c2 "fix: revert flyway V12 rename" + 4 more fixes in db/migrations/ → footgun "never rename an applied migration"
  src/payments/ in risk_paths, no AGENTS.md → module guide with the 2 payment invariants
1. Add footgun "never rename an applied migration"?   a) yes ➡️  b) reword  c) skip
2. Enforce it with a sensor (filename check on db/migrations)?   a) yes, via sensor-smith ➡️  b) invariant only, not yet enforced  c) skip
3. Create src/payments/AGENTS.md?   a) yes, from the 2 invariants ➡️  b) later
Reply with numbers and letters ("1a 2b"), or "defaults" to accept every ➡️.
```

- At most 5 numbered questions, each with 2–4 options and exactly one `➡️` default. "defaults" accepts every ➡️ of the round.
- Never ask what the evidence already answers; never ask about something with no evidence.
- Glossary meanings, Agent Authorization and incidents are the developer's words: suggest the term or the slot, ask for the meaning.

## 4. Apply and re-measure

1. After each round, write the accepted items to their owner files (an Edit per item, inside existing sections; keep budgets: `AGENTS.md` ≤ 100 lines, module `AGENTS.md` ≤ 80). Machine-checkable rules go to sensor-smith; invariant lines keep the format `- <rule> — Severity: <…> — Enforced by: <…>`.
2. When the rounds are done: `bash scripts/harness/lint.sh` (fix FAILs), then `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/level.py" . --json --run-checks --log`.
3. Report:

```text
Before → after: level <a> → <b> · guides <x> → <y> · sensors … · TODO markers <n> → <m> · not-yet-enforced <n> → <m>
Applied: <n> — <file · item> one line each
Sensors: <name> proved ✓ | handed to sensor-smith | declined
Skipped areas: <area — why (no evidence | declined)>
Next: <the one highest-value gap left>
```

Commit nothing; the developer reviews and commits.
