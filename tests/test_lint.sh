LINT="$PLUGIN/skills/harness-init/assets/lint.sh"
# _lr: fresh minimal repo with lint.sh installed; echoes path
_lr() {
  local d; d="$(mktemp -d)"; mkdir -p "$d/scripts/harness"
  cp "$LINT" "$d/scripts/harness/lint.sh"; cp "$PLUGIN/skills/harness-init/assets/harness/plan-check.sh" "$d/scripts/harness/"
  printf '# Repo\n\nRun `make check`.\n' > "$d/AGENTS.md"
  printf '# Invariants\n\n## Security\n\n- No secrets in git — Severity: Critical — Enforced by: gitleaks\n' > "$d/INVARIANTS.md"
  printf 'check:\n\t@true\n' > "$d/Makefile"
  ( cd "$d" && git init -q -b main ) >/dev/null
  echo "$d"
}
_run() { ( cd "$1" && bash scripts/harness/lint.sh 2>&1 ); }

t_clean_passes() { local d; d="$(_lr)"; _run "$d" | grep -q 'harness-lint: OK'; }
t_todo_is_warning() {
  local d out; d="$(_lr)"; echo 'TODO fill me [verify]' >> "$d/AGENTS.md"
  out="$(_run "$d")"
  assert_contains "$out" "warn  AGENTS.md has 1 TODO" "warn"
  assert_contains "$out" "harness-lint: OK" "exit 0 path"
}
t_budget_override() {
  local d i; d="$(_lr)"
  for i in $(seq 150); do echo "line $i" >> "$d/AGENTS.md"; done
  assert_exit 1 "default fails" -- bash -c "cd '$d' && bash scripts/harness/lint.sh"
  printf '\n## File Size Budget\n\n- AGENTS.md: warn 180, fail 220\n' >> "$d/INVARIANTS.md"
  assert_exit 0 "override passes" -- bash -c "cd '$d' && bash scripts/harness/lint.sh"
}
t_invariant_missing_severity_fails() {
  local d out; d="$(_lr)"; echo '- Always lint — Enforced by: ci' >> "$d/INVARIANTS.md"
  out="$(_run "$d")" && return 1
  assert_contains "$out" "Always lint" "names bullet"
}
_reg() { mkdir -p "$1/.agents"; echo "{\"runner\":\"$2\",\"commands\":{$3}}" > "$1/.agents/harness.json"; }
t_registry_mismatch_fails() {
  local d out; d="$(_lr)"
  printf '# Repo\n\nRun `just check`.\n' > "$d/AGENTS.md"; _reg "$d" just '"check":"just check"'
  _run "$d" | grep -q 'harness-lint: OK'
  printf '# Repo\n\nRun `just deploy`.\n' > "$d/AGENTS.md"
  out="$(_run "$d")" && return 1
  assert_contains "$out" "no commands.deploy" "unregistered runner cmd"
  _reg "$d" just '"check":"just check","ship":"just deploy"'
  _run "$d" | grep -q 'harness-lint: OK'
}
t_make_named_with_other_runner_fails() {
  local d out; d="$(_lr)"; _reg "$d" just '"check":"just check"'
  out="$(_run "$d")" && return 1
  assert_contains "$out" "runner is just" "msg"
}
t_make_runner_checks_makefile() {
  local d out; d="$(_lr)"; _reg "$d" make '"check":"make check"'
  _run "$d" | grep -q 'harness-lint: OK'
  : > "$d/Makefile"
  out="$(_run "$d")" && return 1
  assert_contains "$out" "Makefile has no 'check' target" "msg"
}
t_registry_without_python_warns() {
  local d out; d="$(_lr)"; _reg "$d" just '"check":"just check"'
  out="$(cd "$d" && PATH="/nonexistent" /bin/bash scripts/harness/lint.sh 2>&1)" || true
  assert_contains "$out" "python3 not found" "warn"
}
t_severity_tier_anchored_and_crlf_header() {
  local d out; d="$(_lr)"
  printf '\n## Context Budget \r\n\n- auto-loaded tokens: warn 9000, fail 9500\n' >> "$d/INVARIANTS.md"
  _run "$d" | grep -q 'harness-lint: OK'
  printf '\n## Other\n\n' >> "$d/INVARIANTS.md"
  echo '- x — Severity: Criticalish — Enforced by: ci' >> "$d/INVARIANTS.md"
  _run "$d" >/dev/null && return 1 || true
}
t_agent_skills_in_claude_fails() {
  local d out; d="$(_lr)"; printf '@AGENTS.md\n\n## Agent skills\n' > "$d/CLAUDE.md"
  out="$(_run "$d")" && return 1
  assert_contains "$out" "move to AGENTS.md" "msg"
}
t_sensor_proof_missing_fails() {
  local d out; d="$(_lr)"; mkdir -p "$d/scripts/harness/sensors"; echo '{}' > "$d/scripts/harness/sensors/registry.json"
  out="$(_run "$d")" && return 1
  assert_contains "$out" "sensor-proof.sh missing" "msg"
}
t_sensor_recheck_failure_fails() {
  local d; d="$(_lr)"; mkdir -p "$d/scripts/harness/sensors"; echo '{}' > "$d/scripts/harness/sensors/registry.json"
  echo 'echo "sensor x silent"; exit 1' > "$d/scripts/harness/sensor-proof.sh"
  assert_exit 1 "recheck fails lint" -- bash -c "cd '$d' && bash scripts/harness/lint.sh"
  assert_contains "$(cd "$d" && bash scripts/harness/lint.sh 2>&1)" "no longer fires on its fixture" "fixture msg"
  echo 'echo "proof x: FAIL step 3 (clean must pass again, got exit 1)"; exit 1' > "$d/scripts/harness/sensor-proof.sh"
  assert_contains "$(cd "$d" && bash scripts/harness/lint.sh 2>&1)" "fails on the current code (real violations" "clean msg"
  echo 'exit 0' > "$d/scripts/harness/sensor-proof.sh"
  assert_exit 0 "recheck ok" -- bash -c "cd '$d' && bash scripts/harness/lint.sh"
}
t_clean_template_passes() {
  local d out; d="$(mk_template_repo)"
  out="$(_run "$d")" || { echo "$out" >&2; return 1; }
  assert_contains "$out" "harness-lint: OK" "template lints clean"
}
_tp() { # _tp <makefile vars>: lint repo with harness.mk + related-tests.sh, a tested and an untested changed source
  local d A="$PLUGIN/skills/harness-init/assets"; d="$(_lr)"
  cp "$A/harness.mk" "$d/"; cp "$A/harness/related-tests.sh" "$d/scripts/harness/"
  printf '%b\ninclude harness.mk\n' "$1" > "$d/Makefile"
  mkdir -p "$d/src/main/java/a" "$d/src/test/java/a"
  : > "$d/src/main/java/a/Foo.java"; : > "$d/src/main/java/a/Bar.java"; : > "$d/src/test/java/a/FooTest.java"
  echo "$d"
}
t_check_fast_untested_source_warns() {
  local d out; d="$(_tp 'HARNESS_TEST_CHANGED = bash scripts/harness/related-tests.sh maven "false"')"
  out="$(_run "$d")"
  assert_contains "$out" "warn  check-fast tests nothing for src/main/java/a/Bar.java; wire scripts/harness/related-tests.sh (see layout.md)" "untested source named"
  assert_not_contains "$out" "nothing for src/main/java/a/Foo.java" "tested source quiet"
  assert_contains "$out" "harness-lint: OK" "warning only"
  d="$(_tp '')"; out="$(_run "$d")"
  assert_contains "$out" "check-fast tests nothing for src/main/java/a/Foo.java" "no test wiring: every source"
  d="$(_tp 'HARNESS_TEST_SECS = 12')"; out="$(_run "$d")"
  assert_not_contains "$out" "check-fast tests nothing" "fast full suite covers all"
  d="$(_tp 'HARNESS_TEST_CHANGED = ./mvnw test $(TEST_FILES)')"; out="$(_run "$d")"
  assert_contains "$out" "does not use related-tests.sh" "custom wiring flagged once"
}
t_check_fast_warning_survives_sigpipe() {
  # a big repo: grep stops reading early, so under pipefail `ls-files | grep -q` returned 141 and skipped the warning
  local d out b real; d="$(_tp 'HARNESS_TEST_CHANGED = ./mvnw test $(TEST_FILES)')"; b="$(mktemp -d)"; real="$(command -v git)"
  printf '#!/usr/bin/env bash
if [ "$*" = "ls-files --cached --others --exclude-standard" ]; then
  echo src/test/java/a/FooTest.java; yes src/main/java/a/Gen.java | head -n 300000; exit
fi
exec "%s" "$@"
' "$real" > "$b/git"
  chmod +x "$b/git"
  out="$(cd "$d" && PATH="$b:$PATH" bash scripts/harness/lint.sh 2>&1)"
  assert_contains "$out" "does not use related-tests.sh" "warning printed on a large ls-files"
}
_plan() { # _plan <repo> <dir> <name> <ticket line> [extra]: a plan file from the template header
  mkdir -p "$1/docs/plans/$2"; printf '# Plan: x\n\n**Status**: active · **Owner**: me\n%s\n\n## Steps\n- [ ] 1. a\n%b' "$4" "${5:-}" > "$1/docs/plans/$2/$3"
}
t_plan_ticket_required() {
  local d out t; d="$(_lr)"
  for t in '**Ticket**: ABC-12' '**Ticket**: #42' 'Ticket: .scratch/feat/issues/01-a.md' '**Ticket**: none (spike, no tracker)'; do
    _plan "$d" active p.md "$t"; out="$(_run "$d")" || _fail "accepted form refused: $t"
  done
  for t in '**Ticket**: <KEY-123 | #123 | none (<reason>)>' '**Ticket**: none' '**Ticket**: TODO' '**Owner**: me' '**Ticket**: soon' \
           '**Ticket**: KEY-123' '**Ticket**: ABC-123' 'Ticket: XXX-000' '**Ticket**: [KEY-7](https://x/browse/KEY-7)'; do
    _plan "$d" active p.md "$t"; out="$(_run "$d")" && _fail "placeholder accepted: $t"
    assert_contains "$out" "docs/plans/active/p.md" "names the plan"
  done
  mkdir -p "$d/docs/agents"; echo 'Work is tracked in Jira project `SHOP` at x.' > "$d/docs/agents/issue-tracker.md"
  _plan "$d" active p.md '**Ticket**: ABC-12'; out="$(_run "$d")" || _fail "other key must only warn"
  assert_contains "$out" "warn  docs/plans/active/p.md Ticket ABC-12 is not in Jira project SHOP" "key preference"
}
t_plan_ticket_link_and_list_forms() {
  local d out t; d="$(_lr)"
  for t in '**Ticket**: [SHOP-12](https://x.atlassian.net/browse/SHOP-12)' '**Ticket**: https://github.com/o/r/issues/12' \
           '**Ticket**: SHOP-12, SHOP-13' '**Ticket**: SHOP-12 (pay)' '**Ticket**: https://gitlab.com/o/r/-/merge_requests/3'; do
    _plan "$d" active p.md "$t"; out="$(_run "$d")" || _fail "valid form refused: $t ($out)"
  done
  _plan "$d" active p.md '**Ticket**: none (<reason>)'; out="$(_run "$d")" && _fail "placeholder reason accepted"
  _plan "$d" done old.md '**Ticket**: #1'; _plan "$d" active p.md '**Ticket**: #2'
  out="$(_run "$d")"; assert_not_contains "$out" "Verification" "lint does not look for local evidence"
}
t_plan_check_fresh_workspace_evidence() {
  local w pc="$PLUGIN/skills/harness-init/assets/harness/plan-check.sh" a b out
  w="$(mktemp -d)"; a="$(mk_repo node-app)"; b="$(mk_repo node-app)"; mv "$a" "$w/api"; mv "$b" "$w/web-ui"
  printf '{"repos":[{"name":"api","path":"api"},{"name":"portal","path":"web-ui"}]}\n' > "$w/harness-workspace.json"
  mkdir -p "$w/.harness/evidence"; a="$(git -C "$w/api" rev-parse --short HEAD)"; b="$(git -C "$w/web-ui" rev-parse --short HEAD)"
  printf '### 2026-10-27 · api · %s · FAIL\n### 2026-10-27 · portal · %s · PASS\n### 2026-10-28 · api · %s · PASS\n' "$a" "$b" "$a" > "$w/.harness/evidence/p.md"
  ( cd "$w" && bash "$pc" fresh .harness/evidence/p.md ) || _fail "every repo's latest PASS is fresh"
  echo x >> "$w/web-ui/package.json"
  out="$( cd "$w" && bash "$pc" fresh .harness/evidence/p.md )" && _fail "dirty member counted as verified"
  assert_contains "$out" "(portal): uncommitted code changes" "names the repo (path from the manifest)"
  printf '### 2026-10-29 · api · %s · FAIL\n' "$a" >> "$w/.harness/evidence/p.md"
  assert_contains "$( cd "$w" && bash "$pc" fresh .harness/evidence/p.md )" "(api): latest entry is not PASS" "per-repo latest"
}
t_plan_check_fresh_evidence() {
  local d pc="$PLUGIN/skills/harness-init/assets/harness/plan-check.sh" e c out
  d="$(mk_repo node-app)"; e="$d/.harness/evidence/p.md"; mkdir -p "$d/.harness/evidence"
  fr() { ( cd "$d" && bash "$pc" fresh .harness/evidence/p.md ); }
  out="$(fr)" && _fail "missing evidence is fresh"; assert_contains "$out" "no verification evidence on this machine" "missing"
  c="$(git -C "$d" rev-parse --short HEAD)"
  printf '### 2026-10-27 · %s · PASS\nGate: ok\n### 2026-10-28 · %s · FAIL\n' "$c" "$c" > "$e"
  out="$(fr)" && _fail "latest FAIL counted"; assert_contains "$out" "latest entry is not PASS" "latest must be PASS"
  printf '### 2026-10-27 · uncommitted · PASS\n' > "$e"; fr >/dev/null && _fail "uncommitted entry fresh"
  printf '### 2026-10-27 · %s · PASS\n' "$c" > "$e"; fr >/dev/null || _fail "same-day PASS at HEAD refused"
  mkdir -p "$d/docs/plans/active"; echo '# p' > "$d/docs/plans/active/p.md"
  ( cd "$d" && git add -A && git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm plan )
  fr >/dev/null || _fail "a plan-only commit makes the evidence stale"
  echo 'x' >> "$d/package.json"; out="$(fr)" && _fail "uncommitted code counted as verified"
  assert_contains "$out" "uncommitted code changes" "dirty tree"
  ( cd "$d" && git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qam code )
  out="$(fr)" && _fail "new code commit counted as verified"; assert_contains "$out" "code changed since the PASS entry" "new commit"
}
_build_copy() { # _build_copy <repo> <dir>: an IDE/build copy of a module AGENTS.md whose relative link breaks there
  mkdir -p "$1/$2/x"; printf '# Security\n\nSee [rules](../../../INVARIANTS.md). TODO\n' > "$1/$2/x/AGENTS.md"
}
t_build_dir_agents_copies_ignored() {
  local d out; d="$(_lr)"
  _build_copy "$d" target/classes; _build_copy "$d" build/resources; _build_copy "$d" out/production; _build_copy "$d" .gradle/tmp
  _build_copy "$d" generated; echo 'generated/' > "$d/.gitignore"  # any gitignored dir is skipped too
  out="$(_run "$d")"
  assert_contains "$out" "harness-lint: OK" "build copies don't fail lint"; assert_not_contains "$out" "TODO" "nor warn"
  rm -rf "$d/.git" "$d/generated"; out="$(_run "$d")"  # outside git only the build-dir list applies
  assert_contains "$out" "harness-lint: OK" "outside git (find fallback) too"
}
t_module_agents_still_checked() {
  local d out; d="$(_lr)"; mkdir -p "$d/src/auth"
  printf '# Auth\n\nSee [rules](../missing.md).\n' > "$d/src/auth/AGENTS.md"
  out="$(_run "$d")" && return 1
  assert_contains "$out" "src/auth/AGENTS.md" "real module link still checked"
}
