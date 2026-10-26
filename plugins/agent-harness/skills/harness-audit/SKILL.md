---
name: harness-audit
description: Read-only audit of the agent harness. `quick` (default, monthly) answers the 10 health questions and reports the script-measured level and per-layer scores; `full` (quarterly, after an incident or a major refactor) adds the 14-item completeness score, a content-quality pass, the simulated-task probe, the fresh-clone setup proof and a sensor recheck. Changes nothing except one line in docs/harness/AUDIT-LOG.md; fixes go to harness-garden.
disable-model-invocation: true
---

# Harness Audit

Measure, don't grade. The level and layer scores come from a script; your judgement stays in the conversation. `${CLAUDE_PLUGIN_ROOT}` is this plugin's folder (two levels above this file). Checklists: `references/checks.md`.

**Read-only.** Do not edit, create or delete any file, and do not commit. The only write is the log line (step 1 for `quick`, step 5 for `full`). Every fix is handed to `harness-garden`.

Argument: `quick` (default) or `full`.

## 1. Measure

1. If `.harness/scan.json` is missing or its `head` differs from `git rev-parse HEAD`, run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/scan.py" .` (prints only; no `--write`, keep the output in the conversation).
2. `quick`: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/level.py" . --json --run-checks --log` — one call measures and appends the log line, so the reported and the logged level are the same measurement. `full`: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/level.py" . --json --run-checks` now, and log in step 5 once the health score is known.
   Read: `level`, `target`, `layers.<key>.score` and `layers.<key>.missing` for `guides`, `tools`, `sensors`, `context`, `observability`, `next_level_blockers`, `tokens`.
3. `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/assets.py" status .` (read-only): report each `stale` or `modified` plugin script under **observability** (fix: `/agent-harness:harness-init` refreshes unmodified copies).
4. In a multi-repo workspace (a `harness-workspace.json` here), level.py also measures every member; report each member's level on one line.
5. Plans: report under **context** each plan in `docs/plans/done/` (or with `Status: done`) that has no `## Verification` entry (harness-lint warns `is done but has no ## Verification entry`), and each active plan without a valid `Ticket:` (harness-lint fails).

## 2. quick (always)

Answer the **10 health questions** in `references/checks.md`, each ✅ / ⚠️ / ❌ with evidence:
1 Integrity · 2 Constraint propagation · 3 Sensors · 4 Coverage gaps · 5 Enforcement gaps · 6 Footgun freshness · 7 Token budget · 8 File size discipline · 9 Content accuracy · 10 Claude Code integration.

Also count the `TODO` and `[verify]` markers left in harness files (`grep -rn` over `AGENTS.md`, `INVARIANTS.md`, `docs/`) — each is a gap. If more than 2 questions fail, end the report with "Recommend: /harness-audit full".

## 3. full (adds)

1. **14-item completeness score** from `references/checks.md` → 0–100 with the band.
2. **Content-quality pass** (`references/checks.md`).
3. **Simulated-task probe**: run the prompt in `${CLAUDE_PLUGIN_ROOT}/skills/harness-init/references/probe.md`, ideally in a fresh subagent with no prior context; score it against the table there.
4. **Fresh-clone setup proof**: `bash scripts/harness/setup-proof.sh` (clones to a temp folder; touches nothing here). `SKIPPED (docker not available)` is reported as skipped, not as a pass.
5. **Sensor recheck**: `bash scripts/harness/sensor-proof.sh --recheck` (copy-mode fixtures are removed again afterwards).
6. **Compare** with the last row of `docs/harness/AUDIT-LOG.md`: level and each layer score up, same or down.

## 4. Report (this order)

```text
## Layers
guides        0.80  ✓ …            blockers: …
tools         0.50  ✗ no deny rules in .claude/settings.json
sensors       …
context       …
observability …

Level: Functional · target: Robust · blocked by: <next_level_blockers, joined>

## Fixes (ranked: blockers to the target first, then Critical gaps, then cheapest)
1. <file> — <change> — closes <blocker or question #> — layer <key>
…
Health: <n>/10 questions pass   (full: completeness <score>/100 · <band> · probe <summary> · setup-proof <line> · sensors <line> · vs last: <delta>)
Next: hand the fixes to /harness-garden
```

Never recommend work beyond the `target` level; say what the next level would need in one line instead.

## 5. Log (the only write)

- `quick`: already logged in step 1.
- `full`: compute the completeness score first, then `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/level.py" . --json --run-checks --log --health <completeness score>`. If its `level` differs from step 1, report this one (it is what was logged).

This appends one script-measured line (date, level, layer scores, health, tokens) to `docs/harness/AUDIT-LOG.md`. Do not edit the log by hand or add judgements to it.
