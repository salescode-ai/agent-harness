GATE="$PLUGIN/scripts/stop-gate.sh"

# _gate_repo <check-fast body>: git repo with AGENTS.md, a Makefile check-fast, and one dirty source file
_gate_repo() {
  local d; d="$(mktemp -d)"
  ( cd "$d"; git init -q -b main; git config user.email t@example.com; git config user.name test
    printf '# a\n' > AGENTS.md; printf '# i\n' > INVARIANTS.md
    printf 'check-fast:\n\t@%s\ncheck:\n\t@true\n' "$1" > Makefile
    printf '.harness/\n' > .gitignore
    git add -A; git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m init
    git update-ref refs/remotes/origin/main HEAD
    echo 'x=1' > src.py ) >/dev/null
  echo "$d"
}
# _run_gate <cwd> [extra json]: sets RC and ERR
_run_gate() {
  RC=0; ERR="$(printf '{"cwd":"%s"%s}' "$1" "${2:-}" | "$GATE" 2>&1 >/dev/null)" || RC=$?
}

t_blocks_on_failure() {
  local d; d="$(_gate_repo false)"
  _run_gate "$d"
  assert_eq "$RC" 2 "exit"; assert_contains "$ERR" "repo" "names repo"
}
t_passes_and_records_last_check() {
  local d; d="$(_gate_repo true)"
  _run_gate "$d"
  assert_eq "$RC" 0 "exit"; assert_eq "$ERR" "" "silent"
  assert_contains "$(cat "$d/.harness/last-check")" " pass $(date +%Y-%m-%d)" "last-check"
}
t_silent_when_unwired() {
  local d; d="$(_gate_repo false)"; mkdir "$d/.harness"
  echo '{"gate_wired": false}' > "$d/.harness/init-state.json"
  _run_gate "$d"
  assert_eq "$RC" 0 "exit"; assert_eq "$ERR" "" "silent"
}
t_bad_init_state_ignored() {
  local d; d="$(_gate_repo false)"; mkdir "$d/.harness"; echo '{oops' > "$d/.harness/init-state.json"
  _run_gate "$d"
  assert_eq "$RC" 2 "blocks"
}
t_registered_runner_used() {
  local d; d="$(_gate_repo true)"; mkdir "$d/.agents"
  echo '{"commands":{"check-fast":"false"}}' > "$d/.agents/harness.json"
  _run_gate "$d"
  assert_eq "$RC" 2 "blocks via registered runner"
}
t_no_make_silent() {
  local d; d="$(_gate_repo false)"; rm "$d/Makefile"
  _run_gate "$d"
  assert_eq "$RC" 0 "exit"; assert_eq "$ERR" "" "silent"
}
t_loop_guard() {
  local d; d="$(_gate_repo false)"
  _run_gate "$d" ',"stop_hook_active":true'
  assert_eq "$RC" 0 "exit"
}
t_workspace_skips_non_present_members() {
  local ws; ws="$(mktemp -d)"
  mkdir "$ws/good" "$ws/bare"
  cp -R "$(_gate_repo false)/." "$ws/good/"
  ( cd "$ws/bare"; git init -q -b main; git config user.email t@example.com; git config user.name test
    echo a > f.txt; git add -A; git -c commit.gpgsign=false commit -q -m i; echo b > g.py ) >/dev/null
  echo '{"repos":[{"name":"good","path":"good"},{"name":"bare","path":"bare"}]}' > "$ws/harness-workspace.json"
  _run_gate "$ws"
  assert_eq "$RC" 2 "exit"; assert_contains "$ERR" "good" "present member blocks"
  assert_not_contains "$ERR" "bare" "none member skipped"
}
t_member_state() {
  . "$PLUGIN/scripts/_lib.sh" </dev/null
  local d; d="$(_gate_repo true)"
  assert_eq "$(member_state "$d")" present "present"
  rm "$d/INVARIANTS.md"; assert_eq "$(member_state "$d")" partial "partial"
  rm "$d/AGENTS.md" "$d/Makefile"; assert_eq "$(member_state "$d")" none "none"
}
t_workspace_last_check_per_member() {
  local ws a b; ws="$(mktemp -d)"; mkdir "$ws/a" "$ws/b"
  cp -R "$(_gate_repo false)/." "$ws/a/"; cp -R "$(_gate_repo true)/." "$ws/b/"
  echo '{"repos":[{"name":"a"},{"name":"b"}]}' > "$ws/harness-workspace.json"
  _run_gate "$ws"
  assert_eq "$RC" 2 "a fails"
  assert_contains "$(cat "$ws/.harness/last-check-b")" " pass " "b pass"
  [ ! -e "$ws/.harness/last-check-a" ] || _fail "a has no last-check"
  [ ! -e "$ws/.harness/last-check" ] || _fail "no shared last-check"
  [ ! -e "$ws/a/.harness" ] && [ ! -e "$ws/b/.harness" ] || _fail "member dirs written"
}
t_path_with_space() {
  local d s; d="$(_gate_repo false)"; s="$(mktemp -d)/sp ace"; mkdir "$s"; cp -R "$d/." "$s/"
  _run_gate "$s"
  assert_eq "$RC" 2 "blocks"
}
t_cwd_in_subdir() {
  local d; d="$(_gate_repo false)"; mkdir "$d/sub"
  _run_gate "$d/sub"
  assert_eq "$RC" 2 "blocks"
}
t_init_state_without_gate_key_silent() {
  local d; d="$(_gate_repo false)"; mkdir "$d/.harness"
  echo '{"layers_done": []}' > "$d/.harness/init-state.json"
  _run_gate "$d"
  assert_eq "$RC" 0 "silent mid-init"; assert_eq "$ERR" "" "no output"
  echo '{"layers_done": [], "gate_wired": true}' > "$d/.harness/init-state.json"
  _run_gate "$d"
  assert_eq "$RC" 2 "gates once wired"
}
