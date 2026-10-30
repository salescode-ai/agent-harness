# gate-proof.sh: a planted failing test must turn `test T=` and check-fast red; a missing test must too.
GP="$PLUGIN/skills/harness-init/assets/harness/gate-proof.sh"
_gp_repo() { # pytest repo wired through harness.mk; $1 = HARNESS_TEST_ONE, $2 = HARNESS_TEST_CHANGED; echoes path
  local d A="$PLUGIN/skills/harness-init/assets"; d="$(mktemp -d)"
  ( cd "$d"; git init -q -b main; git config user.email t@example.com; git config user.name test
    mkdir -p scripts/harness tests
    cp "$PLUGIN/scripts/harness-cmd.sh" scripts/harness/cmd.sh; cp "$GP" "$A/harness/related-tests.sh" scripts/harness/; cp "$A/harness.mk" .
    printf '.harness/\n.pytest_cache/\n__pycache__/\n' > .gitignore
    printf 'HARNESS_LINT = @true\nHARNESS_TEST_ALL = python3 -m pytest -q -p no:cacheprovider\nHARNESS_TEST_ONE = %s\nHARNESS_TEST_CHANGED = %s\ninclude harness.mk\n' "$1" "$2" > Makefile
    printf 'def test_ok():\n    assert 1 + 1 == 2\n' > tests/test_calc.py
    git add -A; git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m init ) >/dev/null
  echo "$d"
}
_gp() { RC=0; OUT="$(cd "$1" && bash scripts/harness/gate-proof.sh 2>&1)" || RC=$?; }
_gp_state() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("gate_red_proven"))' "$1/.harness/init-state.json"; }
PYT='python3 -m pytest -q -p no:cacheprovider'
CHG="bash scripts/harness/related-tests.sh pytest \"$PYT\""

t_gate_proven_with_exit_codes_kept() {
  python3 -m pytest --version >/dev/null 2>&1 || skip gate_proof "pytest not installed"
  local d; d="$(_gp_repo "$PYT" "$CHG")"
  _gp "$d"; assert_eq "$RC" 0 "exit: $OUT"; assert_contains "$OUT" "gate: proven red (pytest: red on test check-fast no-such-test" "all three red"
  assert_eq "$(_gp_state "$d")" True "recorded"
  assert_eq "$(git -C "$d" worktree list | wc -l | tr -d ' ')" 1 "scratch worktree removed"
  assert_eq "$(git -C "$d" status --short)" "" "repo left clean (.harness ignored)"
}
t_gate_not_proven_when_test_one_swallows_exit() {
  python3 -m pytest --version >/dev/null 2>&1 || skip gate_proof "pytest not installed"
  local d; d="$(_gp_repo "$PYT {T}; :" "$CHG")"
  _gp "$d"; assert_eq "$RC" 1 "exit: $OUT"; assert_contains "$OUT" "test T=<failing test> exits 0" "names test"
  assert_contains "$OUT" "test T=<no such test> exits 0" "no-such passes too"
  assert_eq "$(_gp_state "$d")" False "recorded false"
}
t_gate_not_proven_when_check_fast_swallows_exit() {
  python3 -m pytest --version >/dev/null 2>&1 || skip gate_proof "pytest not installed"
  local d; d="$(_gp_repo "$PYT" "$CHG {CHANGED}; :")"
  _gp "$d"; assert_eq "$RC" 1 "exit: $OUT"; assert_contains "$OUT" "check-fast exits 0 with a failing changed test" "names check-fast"
  assert_not_contains "$OUT" "test T=<failing test>" "test target fine"
}
t_gate_inconclusive_without_tests() {
  local d; d="$(_gp_repo "$PYT" "$CHG")"; git -C "$d" rm -q tests/test_calc.py
  _gp "$d"; assert_eq "$RC" 2 "exit: $OUT"; assert_contains "$OUT" "gate: inconclusive" "no test to plant beside"
}
_gp_junit_repo() { # Maven-shaped repo, sub/ (a separate project) sorting before the root's src/; fake runner; echoes path
  local d A="$PLUGIN/skills/harness-init/assets"; d="$(mktemp -d)"
  ( cd "$d"; git init -q -b main; git config user.email t@example.com; git config user.name test
    mkdir -p scripts/harness a/src/test/java/a src/test/java/r; touch pom.xml a/pom.xml
    cp "$PLUGIN/scripts/harness-cmd.sh" scripts/harness/cmd.sh; cp "$GP" scripts/harness/; cp "$A/harness.mk" .
    # the runner fails a missing file or one asserting false
    printf 'for f in "$@"; do [ -f "$f" ] && ! grep -q "assertTrue(false" "$f" || exit 1; done\n' > run.sh
    printf '.harness/\n' > .gitignore
    printf 'HARNESS_LINT = @true\nHARNESS_TEST_ONE = sh run.sh\ninclude harness.mk\n' > Makefile
    for f in a/src/test/java/a/ATest.java src/test/java/r/RTest.java; do
      printf 'package %s;\nimport org.junit.jupiter.api.Test;\nclass X { @Test void t() {} }\n' "$(basename "$(dirname "$f")")" > "$f"; done
    git add -A; git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m init ) >/dev/null
  echo "$d"
}
t_gate_junit5_prefers_root_module() {
  local d; d="$(_gp_junit_repo)"
  _gp "$d"; assert_eq "$RC" 0 "exit: $OUT"; assert_contains "$OUT" "planted beside src/test/java/r/RTest.java" "root module first"
}
t_gate_beside_override() {
  local d; d="$(_gp_junit_repo)"
  RC=0; OUT="$(cd "$d" && HARNESS_GATE_PROOF_BESIDE=a/src/test/java/a/ATest.java bash scripts/harness/gate-proof.sh 2>&1)" || RC=$?
  assert_eq "$RC" 0 "exit: $OUT"; assert_contains "$OUT" "planted beside a/src/test/java/a/ATest.java" "override honoured"
  RC=0; OUT="$(cd "$d" && HARNESS_GATE_PROOF_BESIDE=no/such/Test.java bash scripts/harness/gate-proof.sh 2>&1)" || RC=$?
  assert_eq "$RC" 2 "missing override file: $OUT"; assert_contains "$OUT" "HARNESS_GATE_PROOF_BESIDE" "names the variable"
}
