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
