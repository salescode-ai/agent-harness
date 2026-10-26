t_no_named_packs() {
  local out
  out="$(cd "$ROOT" && grep -rniE 'superpowers|mattpocock|pocock|karpathy' plugins README.md install-local.sh || true)"
  assert_eq "$out" "" "no named packs"
}
t_version_2() {
  grep -q '"version": "2.0.1"' "$PLUGIN/.claude-plugin/plugin.json"
  grep -q '"version": "2.0.1"' "$ROOT/.claude-plugin/marketplace.json"
}
t_no_pycache() {
  local out
  out="$(find "$ROOT/plugins" -name __pycache__)"
  assert_eq "$out" "" "no __pycache__"
}
t_runner_fails_on_nonfinal_assert() {
  local d out rc=0
  d="$(mktemp -d)"
  printf 't_bad() {\n assert_eq a b "boom"\n true\n}\n' > "$d/test_x.sh"
  out="$(TESTS_DIR="$d" bash "$ROOT/tests/run.sh" 2>&1)" || rc=$?
  assert_contains "$out" "FAIL test_x::bad" "runner reports FAIL"
  assert_eq "$rc" "1" "runner exits non-zero"
}
t_install_local() {
  local d out
  d="$(mktemp -d)/my repo"; mkdir -p "$d"
  bash "$ROOT/install-local.sh" "$d" >/dev/null
  [ -f "$d/.agents/skills/harness-audit/SKILL.md" ]
  [ -f "$d/scripts/harness/cmd.sh" ]
  [ -f "$d/scripts/harness/lint.sh" ]
  [ -f "$d/scripts/harness/setup.sh" ]
  [ -f "$d/scripts/harness/sensors/registry.json" ]
  [ -x "$d/.githooks/pre-commit" ]
  [ -f "$d/.agents/scripts/level.py" ] && [ -f "$d/.agents/scripts/harness-cmd.sh" ]
  (cd "$d" && bash .agents/skills/harness-init/scripts/scan.sh . >/dev/null) || _fail "installed scan.sh wrapper"
  out="$(bash "$ROOT/install-local.sh" "$d")"
  assert_contains "$out" "skip  scripts/harness/cmd.sh" "second run skips"
  assert_not_contains "$out" "added" "second run adds nothing"
}
t_install_local_end_to_end() {
  local d A="$PLUGIN/skills/harness-init/assets"
  d="$(mk_repo node-app)"
  bash "$ROOT/install-local.sh" "$d" >/dev/null
  (cd "$A" && tar cf - AGENTS.md INVARIANTS.md CLAUDE.md GLOSSARY.md docs harness.mk) | (cd "$d" && tar xf -)
  printf 'include harness.mk\n' > "$d/Makefile"
  (cd "$d" && bash scripts/harness/lint.sh >/dev/null)
  local out; out="$(python3 "$PLUGIN/scripts/level.py" "$d" --json)"
  assert_not_contains "$out" '"level": "none"' "level measured"
}
t_py_parses_old_pythons() {
  local f
  for f in $(find "$PLUGIN" -name '*.py'); do
    python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read(), feature_version=(3,8))' "$f"
    # newer parsers accept py3.12-only syntax even with feature_version; check with the system 3.9 too
    if [ -x /usr/bin/python3 ]; then
      /usr/bin/python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" || _fail "py parse $f"
    fi
  done
}
