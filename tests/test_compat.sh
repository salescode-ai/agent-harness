# Upgrade compatibility: repos installed by 2.0.9-2.0.12 and the salescodeai-lite layout keep working with this plugin.
A="$PLUGIN/skills/harness-init/assets"
_old_plugin() { # _old_plugin <tag>: that release's plugin folder (cached per tag); skips without the tag
  local o="${TMPDIR:-/tmp}/ah-compat-$1"
  git -C "$ROOT" rev-parse -q --verify "$1^{commit}" >/dev/null 2>&1 || skip compat "no tag $1"
  [ -d "$o/plugins/agent-harness" ] || { mkdir -p "$o" && git -C "$ROOT" archive "$1" plugins/agent-harness | tar -x -C "$o"; }
  echo "$o/plugins/agent-harness"
}
_compat_repo() { # a git repo with origin/main and origin/dev refs and a Makefile including harness.mk
  local d; d="$(mktemp -d)"
  ( cd "$d" && git init -q -b feat && git config user.email t@e && git config user.name t && printf '# a\n' > AGENTS.md \
    && printf '# i\n' > INVARIANTS.md && printf 'HARNESS_BASE ?= origin/dev\ninclude harness.mk\n' > Makefile \
    && git add -A && git -c core.hooksPath=/dev/null commit -qm init && git update-ref refs/remotes/origin/main HEAD \
    && git update-ref refs/remotes/origin/dev HEAD ) >/dev/null
  echo "$d"
}

t_compat_upgrade_from_older_releases() {
  # every 2.0.9-2.0.12 install refreshes: unmodified copies updated, a modified one reported with its diff command,
  # repo-owned files untouched
  local tag old d out mk ag
  for tag in v2.0.9 v2.0.10 v2.0.11 v2.0.12; do
    old="$(_old_plugin "$tag")"; d="$(_compat_repo)"
    python3 "$old/scripts/assets.py" install "$d" >/dev/null
    printf '# local edit\n' >> "$d/scripts/harness/lint.sh"
    mk="$(cat "$d/Makefile")"; ag="$(cat "$d/AGENTS.md")"
    out="$(python3 "$PLUGIN/scripts/assets.py" install "$d")"
    assert_contains "$out" "updated   harness.mk (was ${tag#v})" "$tag: harness.mk refreshed"
    assert_contains "$out" "updated   .githooks/pre-commit" "$tag: hook refreshed"
    assert_contains "$out" "installed .githooks/snapshot.sh" "$tag: new hook helper installed"
    assert_contains "$out" "modified  scripts/harness/lint.sh — modified locally, review diff: diff scripts/harness/lint.sh" "$tag: modified reported"
    grep -q '# local edit' "$d/scripts/harness/lint.sh" || _fail "$tag: modified copy overwritten"
    assert_eq "$(cat "$d/Makefile")" "$mk" "$tag: Makefile untouched"; assert_eq "$(cat "$d/AGENTS.md")" "$ag" "$tag: AGENTS.md untouched"
    out="$(python3 "$PLUGIN/scripts/assets.py" status "$d")"
    assert_eq "$(grep -v '^current\|^assets:' <<<"$out")" "modified  scripts/harness/lint.sh — modified locally, review diff: diff scripts/harness/lint.sh \"$PLUGIN/skills/harness-init/assets/lint.sh\"" "$tag: only the modified copy left"
  done
}
t_compat_old_cmd_sh_without_base() {
  # red-proof.sh and diffscan.py refreshed, cmd.sh still 2.0.12 (no --base, e.g. modified locally): they fall back
  local old d out
  old="$(_old_plugin v2.0.12)"; d="$(_compat_repo)"; cp "$A/harness.mk" "$d/"; mkdir -p "$d/scripts/harness/sensors/lib"
  cp "$old/scripts/harness-cmd.sh" "$d/scripts/harness/cmd.sh"; cp "$A/harness/red-proof.sh" "$d/scripts/harness/"
  cp "$A/harness/sensors/lib/diffscan.py" "$d/scripts/harness/sensors/lib/"
  out="$(cd "$d" && python3 -c 'import sys; sys.path.insert(0, "scripts/harness/sensors/lib"); import diffscan; print(diffscan.default_base())')"
  assert_eq "$out" "origin/main" "diffscan: old cmd.sh answers nothing, origin/main"
  out="$(cd "$d" && python3 scripts/harness/sensors/lib/diffscan.py 2>&1)"; assert_eq "$?" 0 "diffscan runs"
  out="$(cd "$d" && bash scripts/harness/red-proof.sh 2>&1 | tail -1)"
  assert_contains "$out" "red: n/a" "red-proof runs with a fallback base: $out"
}
t_compat_makefile_without_harness_base() {
  # a 2.0.9 harness.mk has no harness-base target: --base falls back to HARNESS_BASE, then origin/HEAD
  local old d out rc
  old="$(_old_plugin v2.0.9)"; d="$(_compat_repo)"; cp "$old/skills/harness-init/assets/harness.mk" "$d/"
  rc=0; out="$(HARNESS_BASE=origin/dev bash "$PLUGIN/scripts/harness-cmd.sh" "$d" --base)" || rc=$?
  assert_eq "$out" "origin/dev" "HARNESS_BASE"; assert_eq "$rc" 1 "a fallback says so (exit 1)"
  git -C "$d" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  assert_eq "$(bash "$PLUGIN/scripts/harness-cmd.sh" "$d" --base)" "origin/main" "origin/HEAD"
}
t_compat_salescodeai_lite_makefile() {
  # the real consumer's shape: own harness-base, _HELP_ overrides with an apostrophe, a selector as TEST_ALL (empty ARGS:
  # test_harness_mk::check_fast_changed_args_opt_out)
  local d out; d="$(_compat_repo)"; cp "$A/harness.mk" "$d/"
  cat > "$d/Makefile" <<'EOF'
HARNESS_BASE = $(eval HARNESS_BASE := $(or $(shell git rev-parse -q --verify origin/dev >/dev/null && echo origin/dev),BASE-NOT-RESOLVED))$(HARNESS_BASE)
HARNESS_TEST_CHANGED = ./t --base $(HARNESS_BASE) changed
HARNESS_TEST_CHANGED_ARGS =
HARNESS_TEST_CHANGED_CONFIRMED = 1
HARNESS_TEST_ALL = ./t --base $(HARNESS_BASE)
HARNESS_TYPECHECK = @echo "typecheck: setup error: no fork point with $(HARNESS_BASE): git fetch origin" >&2; exit 2
include harness.mk
_HELP_check := Completion gate: lint + typecheck + tests for the branch's changes (DB tier) + harness lint
_HELP_test := Tests for the changes on this branch, or one test file or method with T=<path>; full suite: ./t all
EOF
  out="$(cd "$d" && make help 2>&1)"
  assert_contains "$out" "tests for the branch's changes (DB tier)" "_HELP_check override with an apostrophe"
  assert_contains "$out" "full suite: ./t all" "_HELP_test override"
  assert_eq "$(bash "$PLUGIN/scripts/harness-cmd.sh" "$d" --base)" "origin/dev" "the repo's harness-base answers"
}
