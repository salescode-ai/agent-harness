# red-proof.sh: the change's tests must pass with it and fail without it.
RP="$PLUGIN/skills/harness-init/assets/harness/red-proof.sh"
_rp_repo() { # repo with `make test T=<file>` running a shell test, one committed source file; echoes path
  local d; d="$(mktemp -d)"
  ( cd "$d"; git init -q -b main; git config user.email t@example.com; git config user.name test
    mkdir -p scripts/harness src tests
    cp "$PLUGIN/scripts/harness-cmd.sh" scripts/harness/cmd.sh; cp "$RP" scripts/harness/red-proof.sh
    printf 'test:\n\t@sh $(T)\n' > Makefile
    echo 'add() { echo $(($1+$2)); }' > src/calc.sh
    git add -A; git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m init ) >/dev/null
  echo "$d"
}
_rp() { RC=0; OUT="$(cd "$1" && bash scripts/harness/red-proof.sh ${2:-} 2>&1)" || RC=$?; }

t_red_proven_for_new_behaviour_with_test() {
  local d; d="$(_rp_repo)"
  echo 'double() { echo $(($1*2)); }' >> "$d/src/calc.sh"
  printf '. src/calc.sh\n[ "$(double 2)" = 4 ]\n' > "$d/tests/test_double.sh"
  _rp "$d"; assert_eq "$RC" 0 "exit"; assert_contains "$OUT" "red: proven" "proven"
  assert_eq "$(git -C "$d" worktree list | wc -l | tr -d ' ')" 1 "scratch worktree removed"
}
t_red_not_proven_without_test_change() {
  local d; d="$(_rp_repo)"; echo 'double() { echo $(($1*2)); }' >> "$d/src/calc.sh"
  _rp "$d"; assert_eq "$RC" 1 "exit"; assert_contains "$OUT" "no test changed" "names why"
}
t_red_not_proven_when_test_passes_without_change() {
  local d; d="$(_rp_repo)"; echo 'double() { echo $(($1*2)); }' >> "$d/src/calc.sh"
  printf '. src/calc.sh\n[ "$(add 1 1)" = 2 ]\n' > "$d/tests/test_add.sh"
  _rp "$d"; assert_eq "$RC" 1 "exit"; assert_contains "$OUT" "passes without the change: tests/test_add.sh" "names test"
}
t_red_na_for_docs_only() {
  local d; d="$(_rp_repo)"; echo '# notes' > "$d/README.md"
  _rp "$d"; assert_eq "$RC" 0 "exit"; assert_contains "$OUT" "red: n/a" "n/a"
}
t_red_inconclusive_when_test_red_with_change() {
  local d; d="$(_rp_repo)"; echo 'double() { echo 0; }' >> "$d/src/calc.sh"
  printf '. src/calc.sh\n[ "$(double 2)" = 4 ]\n' > "$d/tests/test_double.sh"
  _rp "$d"; assert_eq "$RC" 2 "exit"; assert_contains "$OUT" "inconclusive" "green control fails"
}
t_red_committed_branch_against_base() {
  local d; d="$(_rp_repo)"; git -C "$d" checkout -q -b KEY-1-double
  echo 'double() { echo $(($1*2)); }' >> "$d/src/calc.sh"
  printf '. src/calc.sh\n[ "$(double 2)" = 4 ]\n' > "$d/tests/test_double.sh"
  ( cd "$d" && git add -A && git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm x )
  _rp "$d" main; assert_eq "$RC" 0 "exit"; assert_contains "$OUT" "red: proven" "committed change vs main"
  _rp "$d"; assert_contains "$OUT" "red: n/a" "no remote: base HEAD, nothing uncommitted"
}
t_red_explicit_base_is_fork_point() {
  local d; d="$(_rp_repo)"; git -C "$d" checkout -q -b KEY-2-double
  ( cd "$d" && git checkout -q main && echo 'other() { :; }' > src/other.sh && git add -A \
    && git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm base-moves && git checkout -q KEY-2-double ) >/dev/null
  echo 'double() { echo $(($1*2)); }' >> "$d/src/calc.sh"
  printf '. src/calc.sh\n[ "$(double 2)" = 4 ]\n' > "$d/tests/test_double.sh"
  _rp "$d" main; assert_eq "$RC" 0 "exit"; assert_contains "$OUT" "red: proven" "proven"
  assert_contains "$OUT" "1 production file(s) reverted to $(git -C "$d" merge-base HEAD main | cut -c1-9)" "only the branch's file, vs the fork point"
}
t_red_default_base_from_the_repo() {
  # features branch from dev while origin/HEAD is main: the default base must be the repo's (make harness-base)
  local d; d="$(_rp_repo)"; git -C "$d" update-ref refs/remotes/origin/main HEAD
  ( cd "$d" && git checkout -q -b dev && echo 'devonly() { :; }' > src/devonly.sh && printf 'harness-base:\n\t@echo dev\n' >> Makefile \
    && git add -A && git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm dev && git checkout -q -b KEY-3-double ) >/dev/null
  echo 'double() { echo $(($1*2)); }' >> "$d/src/calc.sh"
  printf '. src/calc.sh\n[ "$(double 2)" = 4 ]\n' > "$d/tests/test_double.sh"
  _rp "$d"; assert_eq "$RC" 0 "exit: $OUT"; assert_contains "$OUT" "1 production file(s) reverted to $(git -C "$d" rev-parse dev | cut -c1-9)" "vs dev, not origin/main"
}
