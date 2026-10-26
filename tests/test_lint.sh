LINT="$PLUGIN/skills/harness-init/assets/lint.sh"
# _lr: fresh minimal repo with lint.sh installed; echoes path
_lr() {
  local d; d="$(mktemp -d)"; mkdir -p "$d/scripts/harness"
  cp "$LINT" "$d/scripts/harness/lint.sh"
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
