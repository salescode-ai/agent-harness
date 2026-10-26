LEVEL="$PLUGIN/scripts/level.py"

# _lv <dir> [args]: prints JSON field via python path expr in $JQ
_lv() { python3 "$LEVEL" "$@"; }
_field() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

# _lvrepo: minimal Experimental-passing repo (lint passes), with a Makefile check target
_lvrepo() {
  local d; d="$(mktemp -d)"
  ( cd "$d"; git init -q -b main
    printf '# a\n' > AGENTS.md
    printf '# i\n\n## Security\n\n- no secrets — Severity: Critical — Enforced by: `make check`\n' > INVARIANTS.md
    printf 'check:\n\t@true\n' > Makefile
    printf '.harness/\n' > .gitignore ) >/dev/null
  echo "$d"
}
_pass() { mkdir -p "$1/.harness"; echo "abc pass 2026-01-01" > "$1/.harness/last-check"; }

t_no_harness_is_none() {
  local d; d="$(mktemp -d)"
  assert_eq "$(_lv "$d" --json | _field "d['level']")" none "level"
}
t_experimental() {
  local d; d="$(_lvrepo)"
  assert_eq "$(_lv "$d" --json | _field "d['level']")" Experimental "level"
}
t_functional_via_githooks() {
  local d; d="$(_lvrepo)"; _pass "$d"
  mkdir "$d/.githooks"; echo '#!/bin/sh' > "$d/.githooks/pre-commit"; git -C "$d" config core.hooksPath .githooks
  assert_eq "$(_lv "$d" --json | _field "d['level']")" Functional "level"
}
t_functional_via_ci() {
  local d; d="$(_lvrepo)"; _pass "$d"
  mkdir -p "$d/.github/workflows"; printf 'jobs:\n  c:\n    steps:\n      - run: make check\n' > "$d/.github/workflows/ci.yml"
  assert_eq "$(_lv "$d" --json | _field "d['level']")" Functional "level"
}
t_robust_blocked_by_unenforced_security() {
  local d; d="$(_lvrepo)"; _pass "$d"
  printf '# i\n\n## Security\n\n- no secrets — Severity: Critical — Enforced by: not yet enforced\n- other — Severity: Important — Enforced by: `make check`\n' > "$d/INVARIANTS.md"
  mkdir -p "$d/.github/workflows" "$d/docs/plans" "$d/.claude"
  printf 'run: make check\n' > "$d/.github/workflows/ci.yml"
  echo '{"permissions":{"deny":["Read(.env)"]}}' > "$d/.claude/settings.json"
  printf '# a\n## Cadence\n' > "$d/AGENTS.md"
  local out; out="$(_lv "$d" --json)"
  assert_eq "$(echo "$out" | _field "d['level']")" Functional "level"
  assert_contains "$(echo "$out" | _field "d['next_level_blockers']")" "not yet enforced" "blocker"
}
t_target_read() {
  local d; d="$(_lvrepo)"
  assert_eq "$(_lv "$d" --json | _field "d['target']")" Robust "default"
  printf '# i\n\n- Harness target: Enterprise\n' > "$d/INVARIANTS.md"
  assert_eq "$(_lv "$d" --json | _field "d['target']")" Enterprise "read"
}
t_log_appends_one_line() {
  local d; d="$(_lvrepo)"
  _lv "$d" --log --health 82 >/dev/null
  local f="$d/docs/harness/AUDIT-LOG.md"
  assert_eq "$(grep -c '^| 20' "$f")" 1 "one row"
  assert_contains "$(tail -1 "$f")" "| Experimental | g=" "row"
  assert_contains "$(tail -1 "$f")" "health=82" "health"
  _lv "$d" --log >/dev/null
  assert_eq "$(grep -c '^| 20' "$f")" 2 "two rows"
  assert_contains "$(tail -1 "$f")" "health=-" "no health"
}
t_workspace_member_below_functional() {
  local ws; ws="$(mktemp -d)"; mkdir "$ws/a" "$ws/b"
  echo '{"repos":[{"name":"a","path":"a"},{"name":"b","path":"b"}]}' > "$ws/harness-workspace.json"
  assert_contains "$(_lv "$ws" --json | _field "d['layers']['observability']['missing']")" "below Functional" "ws"
}
t_human_review_not_functional() {
  local d; d="$(_lvrepo)"; _pass "$d"; echo 'check:' >/dev/null
  mkdir -p "$d/.github/workflows"; echo 'run: make check' > "$d/.github/workflows/ci.yml"
  printf '# i\n\n## Security\n\n- a — Severity: Critical — Enforced by: human review\n- b — Severity: Important — Enforced by: verifier agent\n' > "$d/INVARIANTS.md"
  local out; out="$(_lv "$d" --json)"
  assert_eq "$(echo "$out" | _field "d['level']")" Experimental "level"
  assert_contains "$(echo "$out" | _field "d['next_level_blockers']")" "machine-enforced" "blocker"
}
t_workspace_malformed_manifest() {
  local ws; ws="$(mktemp -d)"; echo '{oops' > "$ws/harness-workspace.json"
  assert_contains "$(_lv "$ws" --json | _field "d['layers']['observability']['missing']")" "unreadable" "ws"
}
t_workspace_entry_missing_path() {
  local ws; ws="$(mktemp -d)"; echo '{"repos":[{"name":"a"}]}' > "$ws/harness-workspace.json"
  assert_contains "$(_lv "$ws" --json | _field "d['layers']['observability']['missing']")" "missing name/path" "ws"
}
t_workspace_self_loop() {
  local ws; ws="$(mktemp -d)"; echo '{"repos":[{"name":"a","path":"."}]}' > "$ws/harness-workspace.json"
  assert_contains "$(_lv "$ws" --json | _field "d['layers']['observability']['missing']")" "below Functional" "ws"
}
t_workspace_member_last_check() {
  local ws; ws="$(mktemp -d)"; mkdir "$ws/a"
  cp -R "$(_lvrepo)/." "$ws/a/"; mkdir -p "$ws/a/.githooks" "$ws/.harness"
  echo '#!/bin/sh' > "$ws/a/.githooks/pre-commit"; rm -rf "$ws/a/.git"; ( cd "$ws/a"; git init -q; git config core.hooksPath .githooks )
  echo '{"repos":[{"name":"a b","path":"a"}]}' > "$ws/harness-workspace.json"
  assert_contains "$(_lv "$ws" --json | _field "d['layers']['observability']['missing']")" "below Functional" "no pass yet"
  echo "x pass 2026-01-01" > "$ws/.harness/last-check-a_b"
  assert_not_contains "$(_lv "$ws" --json | _field "d['layers']['observability']['missing']")" "below Functional" "member Functional"
}
