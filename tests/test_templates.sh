A="$PLUGIN/skills/harness-init/assets"

t_template_repo_lints_clean() {
  local d out; d="$(mk_template_repo)"
  out="$(cd "$d" && bash scripts/harness/lint.sh 2>&1)" || { echo "$out" >&2; return 1; }
  assert_contains "$out" "harness-lint: OK" "exit 0"
}
t_agents_md_has_sections() {
  local h
  for h in "## Verification" "## Agent skills" "## Context loading" "## Cadence" "## Work Artifacts" "## Agent Authorization" "## Working Principles"; do
    grep -q "^$h" "$A/AGENTS.md" || _fail "AGENTS.md lacks $h"
  done
  grep -q 'quick audit: every 30 days · full audit: every 90 days or after an incident · garden: every 7 days' "$A/AGENTS.md" || _fail "cadence line"
  grep -q 'Pack working notes: .harness/notes/' "$A/AGENTS.md" || _fail "pack notes line"
  grep -q 'docs/agents/issue-tracker.md' "$A/AGENTS.md" || _fail "issue tracker pointer"
  grep -q 'docs/agents/triage-labels.md' "$A/AGENTS.md" || _fail "triage pointer"
  grep -q 'docs/agents/domain.md' "$A/AGENTS.md" || _fail "domain pointer"
  ! grep -q '^## Skills and plugins' "$A/AGENTS.md" || _fail "old heading"
  [ "$(wc -l < "$A/AGENTS.md")" -le 100 ] || _fail "AGENTS.md > 100 lines"
}
t_invariants_has_target_and_budgets() {
  grep -q '^- Harness target: Robust' "$A/INVARIANTS.md" || _fail "target"
  grep -q '^## Context Budget' "$A/INVARIANTS.md" || _fail "context budget"
  grep -q '^## File Size Budget' "$A/INVARIANTS.md" || _fail "file budget"
  grep -q 'No real customer or production data in seeds or fixtures — Severity: Critical — Enforced by: sensor no-prod-data' "$A/INVARIANTS.md" || _fail "no-prod-data"
  grep -q '\.env\.local' "$A/gitignore.append" || _fail "gitignore"
  grep -q 'Read(./\*\*/.env.local)' "$A/claude-settings.json" || _fail "deny"
}
t_templates_level_experimental() {
  local d; d="$(mk_template_repo)"
  assert_eq "$(python3 "$PLUGIN/scripts/level.py" "$d" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["level"])')" "Experimental" "level"
}
