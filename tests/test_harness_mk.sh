# harness.mk: build a temp dir with a Makefile that includes a copy of the fragment.
HMK="$PLUGIN/skills/harness-init/assets/harness.mk"
mk_dir() { # mk_dir <Makefile body>; echoes dir
  local d; d="$(mktemp -d)"; cp "$HMK" "$d/harness.mk"; printf '%s\n' "$1" > "$d/Makefile"; echo "$d"
}

t_targets_listed() {
  local d out t; d="$(mk_dir 'include harness.mk')"
  out="$(cd "$d" && make help 2>&1)"
  for t in help check check-fast lint typecheck test smoke setup harness-lint; do
    assert_contains "$out" "  $t " "help lists $t"
  done
  for t in seed reset dev; do assert_not_contains "$out" "  $t " "unconfigured $t hidden"; done
  d="$(mk_dir 'HARNESS_SEED = @echo s
HARNESS_RESET = @echo r
HARNESS_DEV = @echo d
include harness.mk')"
  out="$(cd "$d" && make help 2>&1)"
  for t in seed reset dev; do assert_contains "$out" "  $t " "configured $t listed"; done
}

t_header_line() {
  assert_eq "$(head -1 "$HMK")" "# Agents: run only make targets listed here. No direct shell commands." "line 1"
}

t_existing_targets_not_clobbered() {
  local d out err
  d="$(mk_dir 'HARNESS_DEFINE_HELP=0
HARNESS_DEFINE_SETUP=0
include harness.mk
help:
	@echo repo-help
setup:
	@echo repo-setup')"
  out="$(cd "$d" && make help 2>"$d/err")"; err="$(cat "$d/err")"
  assert_eq "$out" "repo-help" "repo help recipe runs"
  assert_not_contains "$err" "overriding" "no override warning"
  assert_eq "$(cd "$d" && make setup 2>&1)" "repo-setup" "repo setup recipe runs"
}

t_unconfigured_fails_loud() {
  local d out rc=0; d="$(mk_dir 'include harness.mk')"
  out="$(cd "$d" && HARNESS_ALLOW_SEED=1 make seed 2>&1)" || rc=$?
  [ "$rc" != 0 ] || _fail "seed should exit non-zero"
  assert_contains "$out" "No rule to make target" "message"
  # and the resolver cannot see it, so setup.sh skips the step
  cp "$PLUGIN/scripts/harness-cmd.sh" "$d/cmd.sh"
  assert_exit 3 "seed unresolvable" -- bash "$d/cmd.sh" "$d" seed
}
t_define_seed_0_wins_over_value() {
  local d; d="$(mk_dir 'HARNESS_DEFINE_SEED=0
HARNESS_SEED = @echo s
include harness.mk')"
  assert_not_contains "$(cd "$d" && make help 2>&1)" "  seed " "guard respected"
}
t_base_derived_from_origin_head() {
  local d; d="$(mk_dir 'include harness.mk
show-base:
	@echo $(HARNESS_BASE)')"
  ( cd "$d" && git init -q -b master && git config user.email t@e.com && git config user.name t && git add -A \
    && git -c core.hooksPath=/dev/null commit -qm i && git update-ref refs/remotes/origin/master HEAD ) >/dev/null
  assert_eq "$(cd "$d" && make -s show-base)" origin/master "no origin/main -> origin/master"
  git -C "$d" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master
  git -C "$d" update-ref refs/remotes/origin/main HEAD
  assert_eq "$(cd "$d" && make -s show-base)" origin/master "origin/HEAD wins"
  assert_eq "$(cd "$d" && make -s show-base HARNESS_BASE=origin/dev)" origin/dev "override"
}

t_default_goal_help() {
  local d; d="$(mk_dir 'include harness.mk')"
  assert_contains "$(cd "$d" && make 2>&1)" "  check " "bare make shows help"
}

t_help_respects_guards() {
  local d out
  d="$(mk_dir 'HARNESS_DEFINE_SEED=0
HARNESS_DEFINE_LINT=0
include harness.mk
lint: ## repo lint
	@true')"
  out="$(cd "$d" && make help 2>&1)"
  assert_not_contains "$out" "  seed " "no phantom seed"
  assert_eq "$(printf '%s\n' "$out" | grep -c '^  lint ')" "1" "exactly one lint line"
  assert_contains "$out" "repo lint" "repo lint described"
}

t_changed_includes_untracked() {
  local d out rc=0; d="$(mk_dir 'HARNESS_LINT = @true
HARNESS_TEST_CHANGED = @sh -c '"'"'for f in "$$@"; do case $$f in *Test.java) echo "FAILED $$f"; exit 1;; esac; done'"'"' t
include harness.mk')"
  ( cd "$d" && git init -q -b main && git config user.email t@e.com && git config user.name t && git add -A \
    && git -c core.hooksPath=/dev/null commit -qm i && git update-ref refs/remotes/origin/main HEAD ) >/dev/null
  echo 'class NewTest {}' > "$d/NewTest.java"
  out="$(cd "$d" && make check-fast 2>&1)" || rc=$?
  [ "$rc" != 0 ] || _fail "check-fast must fail on a new untracked failing test"
  assert_contains "$out" "FAILED NewTest.java" "untracked file passed to HARNESS_TEST_CHANGED"
}
t_skipped_tools_wired_let_check_pass() {
  local d; d="$(mk_dir 'HARNESS_LINT = @echo "lint: skipped (no JDK 11, 2026-10-26)"
HARNESS_TEST_ALL = @echo "test: skipped (no JDK 11, 2026-10-26)"
include harness.mk')"
  ( cd "$d" && git init -q -b main ) >/dev/null
  assert_contains "$(make -s -C "$d" check-fast 2>&1)" "check-fast: OK" "skipped tools do not keep the gate red"
  assert_contains "$(make -s -C "$d" lint 2>&1)" "lint: skipped (no JDK 11" "skip stays visible"
}
# dev-check: HARNESS_DEV records its shell pid; health is a command
_dev_dir() {
  local d; d="$(mk_dir "HARNESS_DEV = @echo \$\$\$\$ > dev.pid; sleep 300
HARNESS_HEALTH = ${1:-test -f dev.pid}
HARNESS_HEALTH_SECS = 4
include harness.mk")"
  mkdir -p "$d/scripts/harness"; cp "$PLUGIN/skills/harness-init/assets/harness/dev-check.sh" "$d/scripts/harness/"; echo "$d"
}
t_dev_check_runs_and_always_stops() {
  local d out pid; d="$(_dev_dir)"
  out="$(cd "$d" && make -s dev-check RUN='echo ran-against-app' 2>&1)" || _fail "dev-check failed: $out"
  assert_contains "$out" "ran-against-app" "RUN executed"
  pid="$(cat "$d/dev.pid")"; sleep 1
  kill -0 "$pid" 2>/dev/null && { kill "$pid"; _fail "dev server $pid left running"; }
  out="$(cd "$d" && make -s dev-check RUN='false' 2>&1)" && return 1
  pid="$(cat "$d/dev.pid")"; sleep 1; ! kill -0 "$pid" 2>/dev/null || _fail "left running after RUN failed"
}
t_dev_check_health_timeout_stops() {
  local d out pid; d="$(_dev_dir false)"
  out="$(cd "$d" && make -s dev-check 2>&1)" && return 1
  assert_contains "$out" "not healthy" "timeout named"
  pid="$(cat "$d/dev.pid")"; sleep 1; ! kill -0 "$pid" 2>/dev/null || { kill "$pid"; _fail "left running"; }
}
t_dev_check_needs_health() {
  local d out; d="$(mk_dir 'HARNESS_DEV = @sleep 1
include harness.mk')"
  out="$(cd "$d" && make help 2>&1)"
  assert_not_contains "$out" "  dev-check " "no HARNESS_HEALTH: no dev-check"
  assert_not_contains "$out" "  dev-stop " "dev-stop only with dev-check (a repo's own dev-stop stays unclobbered)"
}

t_test_args_placeholder_or_appended() {
  local d out
  d="$(mk_dir "HARNESS_TEST_ONE = @echo one -Dtest='{T}' end
include harness.mk")"
  assert_eq "$(cd "$d" && make -s test T=FooTest)" "one -Dtest=FooTest end" "{T} substituted, not appended"
  d="$(mk_dir 'HARNESS_TEST_ONE = @echo one
include harness.mk')"
  assert_eq "$(cd "$d" && make -s test T=FooTest)" "one FooTest" "no placeholder: appended as before"
  d="$(mk_dir 'HARNESS_LINT = @true
HARNESS_TEST_CHANGED = @echo [{CHANGED}] end
include harness.mk')"
  ( cd "$d" && git init -q && touch a.py )
  out="$(cd "$d" && make -s check-fast HARNESS_BASE=HEAD)"
  assert_contains "$out" "[" "ran"; assert_contains "$out" "a.py" "changed file substituted"
  assert_contains "$out" "] end" "{CHANGED} substituted, not appended"
}

t_test_exit_code_kept_with_and_colon() {
  local d
  d="$(mk_dir 'HARNESS_TEST_ONE = @false && :
include harness.mk')"
  assert_exit 2 "&& : keeps the failure" -- make -s -C "$d" test T=x
  d="$(mk_dir 'HARNESS_TEST_ONE = @false {T}
include harness.mk')"
  assert_exit 2 "{T}: the failure reaches make" -- make -s -C "$d" test T=x
}

t_test_arg_cannot_run_commands() {
  # `Bash(make test:*)` is auto-approved, so T must never reach the shell or make as code
  local d p out rc
  d="$(mk_dir 'HARNESS_TEST_ONE = @echo ran
include harness.mk')"
  for p in 'x; touch pwned' 'x && touch pwned' 'x`touch pwned`' 'x$$(touch pwned)' '$(shell touch pwned)' 'x | touch pwned' \
           "x' ; touch pwned" 'x > pwned' "$(printf 'x\ntouch pwned')" '-o pwned'; do
    rc=0; out="$(cd "$d" && make -s test T="$p" 2>&1)" || rc=$?
    [ "$rc" != 0 ] || _fail "T='$p' was accepted: $out"
    assert_not_contains "$out" "ran" "nothing ran for T='$p'"
    [ ! -e "$d/pwned" ] || _fail "T='$p' ran a command"; rm -f "$d/pwned"
  done
  assert_contains "$out" "test: T may only hold" "says why"
  for p in 'src/test/java/a/FooTest.java' 'FooTest#bar' 'FooTest,BarTest' 'tests/test_a.py::test_x[1-2]' 'src/*.test.ts' 'a.py b.py' 'pkg/foo:bar@1'; do
    assert_eq "$(cd "$d" && make -s test T="$p" 2>&1)" "ran $p" "accepted: $p"
  done
}
t_changed_file_names_cannot_run_commands() {
  local d out; d="$(mk_dir 'HARNESS_LINT = @true
HARNESS_TEST_CHANGED = @echo files:
include harness.mk')"
  ( cd "$d" && git init -q && touch ok.py 'x;touch pwned' '$(touch pwned)' '-rf' ) 
  out="$(cd "$d" && make -s check-fast HARNESS_BASE=HEAD 2>&1)"
  [ ! -e "$d/pwned" ] || _fail "a changed file name ran a command"
  assert_contains "$out" "ok.py" "plain name kept"; assert_not_contains "$out" "-rf" "option-like name dropped"
}
t_check_fast_changed_args_opt_out() {
  local d bin out; d="$(mk_dir 'HARNESS_LINT = @true
HARNESS_TEST_CHANGED = @echo runner-args:
include harness.mk')"
  bin="$d/bin"; mkdir "$bin"; printf '#!/bin/sh\necho "$*" >> %s/git.log\n' "$d" > "$bin/git"; chmod +x "$bin/git"
  out="$(cd "$d" && PATH="$bin:$PATH" make -s check-fast HARNESS_BASE=x 2>&1)"
  assert_contains "$(cat "$d/git.log")" "ls-files" "default: CHANGED is computed"
  rm -f "$d/git.log"
  out="$(cd "$d" && PATH="$bin:$PATH" make -s check-fast HARNESS_BASE=x HARNESS_TEST_CHANGED_ARGS= 2>&1)"
  assert_contains "$out" "check-fast: OK" "runs"; [ ! -f "$d/git.log" ] || _fail "git ran with the args opted out: $(cat "$d/git.log")"
  assert_eq "$(cd "$d" && make -s harness-base HARNESS_BASE=origin/dev)" "origin/dev" "harness-base prints the base"
}

t_help_prints_apostrophes() {
  # a repo may override _HELP_<target> after the include; any text must print verbatim
  local d out; d="$(mk_dir "include harness.mk
_HELP_check := Runs the branch's tests, not \"all\" (100%)")"
  out="$(cd "$d" && make help 2>&1)" || _fail "make help failed: $out"
  assert_contains "$out" "  check          Runs the branch's tests, not \"all\" (100%)" "override printed verbatim"
}
t_test_secs_is_data() {
  # HARNESS_TEST_SECS reached a shell test at parse time: a command-line value could run code
  local d out; d="$(mk_dir 'HARNESS_LINT = @true
HARNESS_TEST_ALL = @echo RAN_ALL
include harness.mk')"
  out="$(cd "$d" && make check-fast HARNESS_TEST_SECS="1\" ]; touch $d/pwned; [ \"" 2>&1)" || true
  [ ! -e "$d/pwned" ] || _fail "HARNESS_TEST_SECS ran a command"
  assert_not_contains "$out" "RAN_ALL" "an invalid value runs no tests"
  out="$(cd "$d" && make check-fast HARNESS_TEST_SECS=30 2>&1)"; assert_contains "$out" "RAN_ALL" "30: full suite"
  out="$(cd "$d" && make check-fast HARNESS_TEST_SECS=90 2>&1)"; assert_not_contains "$out" "RAN_ALL" "90: no tests"
  out="$(cd "$d" && make check-fast HARNESS_TEST_SECS=' 60 ' 2>&1)"; assert_contains "$out" "RAN_ALL" "60, padded: full suite"
}
t_help_does_not_claim_all_tests() {
  # test runs HARNESS_TEST_ALL, which a repo may point at a selector (only what changed): help must not say "all tests"
  local d out; d="$(mk_dir 'HARNESS_TEST_ALL = ./t changed
include harness.mk')"
  out="$(cd "$d" && make help 2>&1)"
  assert_not_contains "$(tr 'A' 'a' <<<"$out")" "all tests" "no claim of all tests"
  assert_contains "$out" "HARNESS_TEST_ALL" "names what runs"
}
