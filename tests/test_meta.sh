t_no_named_packs() {
  local out
  out="$(cd "$ROOT" && grep -rniE 'superpowers|mattpocock|pocock|karpathy' plugins README.md install-local.sh || true)"
  assert_eq "$out" "" "no named packs"
}
t_version_2() {
  grep -q '"version": "2.0.0"' "$PLUGIN/.claude-plugin/plugin.json"
  grep -q '"version": "2.0.0"' "$ROOT/.claude-plugin/marketplace.json"
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
