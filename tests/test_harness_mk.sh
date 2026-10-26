# harness.mk: build a temp dir with a Makefile that includes a copy of the fragment.
HMK="$PLUGIN/skills/harness-init/assets/harness.mk"
mk_dir() { # mk_dir <Makefile body>; echoes dir
  local d; d="$(mktemp -d)"; cp "$HMK" "$d/harness.mk"; printf '%s\n' "$1" > "$d/Makefile"; echo "$d"
}

t_targets_listed() {
  local d out t; d="$(mk_dir 'include harness.mk')"
  out="$(cd "$d" && make help 2>&1)"
  for t in help check check-fast lint typecheck test smoke setup seed reset dev harness-lint; do
    assert_contains "$out" "  $t " "help lists $t"
  done
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
  out="$(cd "$d" && make seed 2>&1)" || rc=$?
  [ "$rc" != 0 ] || _fail "seed should exit non-zero"
  assert_contains "$out" "seed: not configured" "message"
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
