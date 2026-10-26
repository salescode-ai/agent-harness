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
_run_active() { # _run_active <cwd>: a Stop after a block; sets RC, ERR, OUT
  local f; f="$(mktemp)"; RC=0
  OUT="$(printf '{"cwd":"%s","stop_hook_active":true}' "$1" | "$GATE" 2>"$f")" || RC=$?
  ERR="$(cat "$f")"
}
t_recheck_after_block_is_bounded() {
  local d; d="$(_gate_repo false)"
  _run_gate "$d"; assert_eq "$RC" 2 "first stop blocks"
  _run_active "$d"; assert_eq "$RC" 0 "unchanged since the block: allow"
  assert_contains "$OUT" '"systemMessage":"agent-harness: stop gate gave up (no code change since the last block)' "visible give-up"
  assert_contains "$OUT" "still failing in: repo" "names what fails"
  _run_gate "$d"; assert_eq "$RC" 2 "new chain blocks again"
  echo 'x=2' > "$d/src.py"; _run_active "$d"; assert_eq "$RC" 2 "changed and still failing: block 2"
  assert_contains "$ERR" "check-fast failed" "report"
  echo 'x=3' > "$d/src.py"; _run_active "$d"; assert_eq "$RC" 2 "block 3"
  echo 'x=4' > "$d/src.py"; _run_active "$d"; assert_eq "$RC" 0 "gives up after 3 blocks"
  assert_contains "$OUT" "gave up (3 blocks in a row)" "count named"
  python3 -c 'import json,sys; json.loads(sys.argv[1])' "$OUT" || _fail "systemMessage is valid JSON"
}
t_recheck_passes_once_fixed() {
  local d; d="$(_gate_repo 'test ! -f broken')"; touch "$d/broken"
  _run_gate "$d"; assert_eq "$RC" 2 "blocks"
  rm "$d/broken"; echo 'x=2' > "$d/src.py"
  _run_active "$d"; assert_eq "$RC" 0 "fixed"; assert_eq "$OUT" "" "silent"; assert_eq "$ERR" "" "quiet"
  [ ! -e "$d/.harness/stop-blocks" ] || _fail "counter cleared"
}
t_recheck_without_state_cannot_loop() {
  local d; d="$(_gate_repo false)"
  _run_gate "$d"; assert_eq "$RC" 2 "blocks"
  rm -f "$d/.harness/stop-blocks"; mkdir "$d/.harness/stop-blocks"  # counter can't be read or written
  echo 'x=2' > "$d/src.py"; _run_active "$d"
  assert_eq "$RC" 0 "no writable counter: allow instead of looping"
}
t_no_state_dir_without_harness() {
  local d; d="$(_gate_repo false)"; rm "$d/AGENTS.md"
  _run_gate "$d"; assert_eq "$RC" 0 "unharnessed: allow"
  [ ! -e "$d/.harness" ] || _fail "no .harness/ created in an unharnessed repo"
  d="$(_gate_repo true)"; _run_gate "$d"; [ -d "$d/.harness" ] || _fail "harnessed repo keeps its state"
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
  assert_not_contains "$ERR" "---- bare" "none member not gated"
  assert_contains "$ERR" "bare (none harness)" "skipped member named when blocking"
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
  rm -rf "$ws/.harness"; ( cd "$ws/b" && git checkout -q -- . && git clean -qfd ) >/dev/null
  echo '{"repos":[{"name":"b"}]}' > "$ws/harness-workspace.json"; rm "$ws/b/AGENTS.md"
  _run_gate "$ws"; assert_eq "$RC" 0 "nothing gated"
  [ ! -e "$ws/b/.harness" ] || _fail "unharnessed member written"
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
t_master_default_repo_gates_committed_work() {
  local d; d="$(_gate_repo false)"
  ( cd "$d" && git branch -q -m main master && git update-ref -d refs/remotes/origin/main \
    && git update-ref refs/remotes/origin/master HEAD && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master \
    && git add -A && git -c core.hooksPath=/dev/null commit -qm work ) >/dev/null
  [ -z "$(git -C "$d" status --porcelain)" ] || _fail "tree should be clean"
  _run_gate "$d"
  assert_eq "$RC" 2 "committed failing work on master-default repo blocks"
  git -C "$d" symbolic-ref -d refs/remotes/origin/HEAD
  _run_gate "$d"
  assert_eq "$RC" 2 "origin/master fallback"
}
t_block_report_summarises_failures() {
  local d; d="$(_gate_repo 'sh fail.sh')"; _stack_script "$d"
  _run_gate "$d"
  assert_eq "$RC" 2 "blocks"
  assert_contains "$ERR" "Tests run: 5, Failures: 1" "failure count kept"
  assert_contains "$ERR" "expected:<1> but was:<2>" "assertion kept"
  assert_contains "$ERR" "BUILD FAILED in 3s" "tail kept"
  assert_not_contains "$ERR" "Frame30.call" "middle frames dropped"
  [ "$(wc -l <<<"$ERR")" -le 45 ] || _fail "report capped (~40 lines)"
}
t_workspace_names_unwired_member() {
  local ws; ws="$(mktemp -d)"; mkdir "$ws/good" "$ws/half"
  cp -R "$(_gate_repo false)/." "$ws/good/"; cp -R "$(_gate_repo true)/." "$ws/half/"
  mkdir -p "$ws/half/.harness"; echo '{"gate_wired": false}' > "$ws/half/.harness/init-state.json"
  echo '{"repos":[{"name":"good"},{"name":"half"}]}' > "$ws/harness-workspace.json"
  _run_gate "$ws"
  assert_eq "$RC" 2 "good blocks"; assert_contains "$ERR" "half (gate not wired)" "unwired member listed as not gated"
  assert_not_contains "$ERR" "---- half" "unwired member not run"
  out="$(printf '{"cwd":"%s"}' "$ws" | "$PLUGIN/scripts/session-context.sh" 2>&1)"
  assert_contains "$out" "half: main · 1 uncommitted · harness present (gate not wired)" "session view"
  assert_contains "$out" "good: main · 1 uncommitted · harness present
" "wired member plain"
}
