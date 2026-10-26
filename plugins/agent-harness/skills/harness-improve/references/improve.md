# harness-improve: status checks and evidence mining

All commands run from the repo root and change nothing. `P=${CLAUDE_PLUGIN_ROOT}`.

## Status block

| Gap | Command | Counts as a gap when |
|---|---|---|
| Level and blockers | `python3 "$P/scripts/level.py" . --json --run-checks` → `level`, `target`, `layers.<key>.missing`, `next_level_blockers` | any blocker to the target |
| TODO / `[verify]` per file | `grep -rnE 'TODO\|\[verify\]' AGENTS.md INVARIANTS.md GLOSSARY.md docs/ --include='*.md' \| cut -d: -f1 \| sort \| uniq -c` | count > 0 |
| Invariants not yet enforced | `grep -n 'Enforced by: not yet enforced' INVARIANTS.md` | each line (Critical first) |
| Placeholder invariants | `grep -nE '^- <rule' INVARIANTS.md` | each section still holding `<rule>` |
| Skeletal sections | the `AGENTS.md` sections Agent Authorization, Footguns, Modules and the Context loading rows still holding `<…>`; `GLOSSARY.md` with no real term | any |
| Module guides for risk paths | `python3 "$P/scripts/scan.py" .` → `risk_paths`; for each, `ls <path>/AGENTS.md` | a risk path with no `AGENTS.md` and no Context loading row |
| Team rollout settings | `python3 -c 'import json;d=json.load(open(".claude/settings.json"));print(bool(d.get("extraKnownMarketplaces",{}).get("agent-harness")), bool(d.get("enabledPlugins",{}).get("agent-harness@agent-harness")))'` | missing file, either value False, or a parse error — gap "team rollout settings missing" |
| Stale plugin scripts | `python3 "$P/scripts/assets.py" status .` and `python3 "$P/scripts/migrate.py" status .` | any `stale` line or needed migration → hand to `/agent-harness:harness-upgrade` |
| Last audit | last row of `docs/harness/AUDIT-LOG.md` | older than the Cadence line in `AGENTS.md` (default 30 days) |

**Team rollout fix** (one question, default yes): add to `.claude/settings.json` (merge, keep every existing key) `"extraKnownMarketplaces": {"agent-harness": {"source": {"source": "github", "repo": "salescode-ai/agent-harness"}}}` and `"enabledPlugins": {"agent-harness@agent-harness": true}` — the same block as `harness-init/assets/claude-settings.json`. Teammates then get the plugin's hooks, skills and agents when they trust the folder. Tools other than Claude Code: `install-local.sh` copies the skills to `.agents/skills/` (no agent hooks there; enforcement comes from the git hooks and CI).

## Areas (mine in this order; skip an area with no evidence)

| Area | Mining | Suggestion | Owner |
|---|---|---|---|
| Footguns | `git log --since=180.days --format='%h %s' \| grep -iE '^[0-9a-f]+ (fix\|revert\|hotfix)'`, then cluster by path: `git show --stat --format= <sha>`; ≥ 2 fixes in one folder or one recurring cause = a candidate | one footgun line (what goes wrong · what to do instead · evidence sha) | `AGENTS.md` Footguns |
| Invariants | the same clusters, where the cause is a rule ("never X", "always Y"), plus incidents named in commit bodies (`git log --grep -iE 'incident\|outage\|postmortem'`) | `- <rule> — Severity: <…> — Enforced by: not yet enforced` | `INVARIANTS.md` |
| Sensors | each not-yet-enforced invariant and new rule, matched against `harness-init/references/sensor-catalog.md` and the repo's existing linters (`scan.json` tooling) | wire via sensor-smith (proved on a fixture), or keep as not yet enforced | `scripts/harness/sensors/` + registry |
| Module guides | `risk_paths` without `AGENTS.md`; folders with their own build file (`package.json`, `pom.xml`, `go.mod`) or ≥ 3 fix commits | `<path>/AGENTS.md` (≤ 80 lines) with the invariants that apply there | `<module>/AGENTS.md` + a Context loading row |
| Context loading | top-level modules (`scan.json` `modules`) with no row in `AGENTS.md` Context loading | one row: task → files to read first | `AGENTS.md` |
| Decisions (ADR) | `git log --since=365.days --format='%h %s' \| grep -iE 'migrate to\|replace\|switch to\|drop\|deprecate\|move to'` and dependency swaps (`git log -p -- package.json pom.xml build.gradle go.mod requirements*.txt pyproject.toml \| grep -E '^[-+] '` where one library leaves and another arrives) | one ADR draft per change of direction, `Source: <sha>`; the why is asked, never guessed | `docs/adr/NNNN-<slug>.md` + `docs/DECISIONS.md` |
| Glossary | domain nouns in type/function names of the last 200 commits (`git log -p -n 200 --since=60.days`) that are not in `GLOSSARY.md`; top 10 by frequency | the term with its `file:line`; the meaning is asked | `GLOSSARY.md` |
| Review / CI failures | repeated lint or test failures: `docs/harness/AUDIT-LOG.md` trends, CI logs if the developer points at them, `.harness/evidence/*.md` FAIL entries (local only) | a sensor, a footgun or a TESTING.md note, whichever owns it | per row above |
| Agent Authorization | still `<e.g. …>` placeholders | the developer's own list; suggest the two slots, ask | `AGENTS.md` |
| Team rollout | the status gap above | the settings block | `.claude/settings.json` |

## Round rules

- One area per round; the round opens with one line saying what the area is for, then `Found → Suggest` lines, each with its evidence.
- ≤ 5 numbered questions, 2–4 options each, exactly one `➡️` default; "defaults" accepts all defaults of the round.
- Defaults: add a footgun or module guide with evidence → yes; new invariant severity → the lowest that matches the evidence (an incident → Critical); a sensor → "yes, via sensor-smith" only when the catalog or an existing linter has a matching rule, else "not yet enforced".
- Apply after every round; keep a before/after count for the final report.
