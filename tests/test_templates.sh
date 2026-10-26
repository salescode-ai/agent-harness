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
  if grep -qF 'Read(./.env.*)' "$A/claude-settings.json"; then _fail "deny .env.* hides .env.example"; fi
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$A/claude-settings.json" || _fail "settings json"
  if grep -qF '.env.*)' "$PLUGIN/skills/harness-workspace/assets/claude/settings.json"; then _fail "workspace deny .env.*"; fi
}
t_templates_level_experimental() {
  local d; d="$(mk_template_repo)"
  assert_eq "$(python3 "$PLUGIN/scripts/level.py" "$d" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["level"])')" "Experimental" "level"
}
t_init_materialises_issue_tracker() {
  local R="$PLUGIN/skills/harness-init"
  grep -q 'issue-tracker-<tracker>.md` → `docs/agents/issue-tracker.md' "$R/references/layers.md" || _fail "layers rule"
  grep -q 'issue-tracker-<' "$R/SKILL.md" || _fail "SKILL pointer"
  [ "$(wc -l < "$R/SKILL.md")" -le 120 ] || _fail "SKILL.md > 120"
}
t_no_old_skills_heading() {
  local f
  for f in $(find "$PLUGIN/skills" -path '*assets*' -name AGENTS.md); do
    ! grep -q 'Skills and plugins' "$f" || _fail "$f has old heading"
  done
}
