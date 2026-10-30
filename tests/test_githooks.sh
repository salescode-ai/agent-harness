HOOKS="$PLUGIN/skills/harness-init/assets/githooks"

# _hook_repo <check-fast body> [nocmd]: repo with a Makefile and (unless nocmd) a copied scripts/harness/cmd.sh
_hook_repo() {
  local d; d="$(mktemp -d)"
  printf 'check-fast:\n\t@%s\ncheck:\n\t@%s\n' "$1" "$1" > "$d/Makefile"
  if [ "${2:-}" != nocmd ]; then mkdir -p "$d/scripts/harness"; cp "$PLUGIN/scripts/harness-cmd.sh" "$d/scripts/harness/cmd.sh"; fi
  echo "$d"
}
t_precommit_blocks_failing() {
  local d rc=0; d="$(_hook_repo false)"
  (cd "$d" && bash "$HOOKS/pre-commit") >/dev/null 2>&1 || rc=$?
  [ "$rc" != 0 ] || _fail "expected non-zero"
  (cd "$d" && bash "$HOOKS/pre-push" </dev/null) >/dev/null 2>&1 && _fail "pre-push should fail" || true
}
t_precommit_passes() {
  local d; d="$(_hook_repo true)"
  (cd "$d" && bash "$HOOKS/pre-commit" >/dev/null 2>&1)
}
t_precommit_skips_unwired() {
  local d out; d="$(mktemp -d)"; mkdir -p "$d/scripts/harness"; cp "$PLUGIN/scripts/harness-cmd.sh" "$d/scripts/harness/cmd.sh"
  out="$(cd "$d" && bash "$HOOKS/pre-commit" 2>&1)"
  assert_contains "$out" "check-fast not wired, skipping" "msg"
  d="$(_hook_repo false nocmd)"
  out="$(cd "$d" && bash "$HOOKS/pre-commit" 2>&1)"
  assert_contains "$out" "scripts/harness/cmd.sh missing, skipping" "msg"
}
t_hooks_executable() { [ -x "$HOOKS/pre-commit" ] && [ -x "$HOOKS/pre-push" ]; }
t_hooks_skip_mid_init() {
  local d out h; d="$(_hook_repo false)"; mkdir "$d/.harness"
  echo '{"layers_done": []}' > "$d/.harness/init-state.json"
  for h in pre-commit pre-push; do
    out="$(cd "$d" && bash "$HOOKS/$h" </dev/null 2>&1)" || _fail "$h blocked mid-init"
    assert_contains "$out" "harness: setup in progress, skipping" "$h msg"
  done
  echo '{"gate_wired": true}' > "$d/.harness/init-state.json"
  (cd "$d" && bash "$HOOKS/pre-commit") >/dev/null 2>&1 && _fail "wired: pre-commit should fail" || true
}
_done_repo() { # repo with a committed active plan, plan-check.sh and a passing check-fast
  local d; d="$(_hook_repo true)"; cp "$PLUGIN/skills/harness-init/assets/harness/plan-check.sh" "$d/scripts/harness/"
  mkdir -p "$d/docs/plans/active" "$d/docs/plans/done"; printf '# P\n\n**Status**: active\n' > "$d/docs/plans/active/2026-01-01-p.md"
  ( cd "$d" && git init -q -b main && git add -A && git -c user.email=t@e -c user.name=t -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm init ) >/dev/null
  echo "$d"
}
t_precommit_blocks_unverified_done() {
  local d out rc=0; d="$(_done_repo)"
  ( cd "$d" && git mv docs/plans/active/2026-01-01-p.md docs/plans/done/ )
  out="$(cd "$d" && bash "$HOOKS/pre-commit" 2>&1)" || rc=$?
  assert_eq "$rc" 1 "moved to done/ without evidence blocks"
  assert_contains "$out" "closed as done without a fresh PASS" "msg"
  assert_contains "$out" "Run harness-verify, commit the code, then close" "fix"
  out="$(cd "$d" && HARNESS_ALLOW_UNVERIFIED_DONE=1 bash "$HOOKS/pre-commit" 2>&1)" || _fail "override with no evidence dir should pass"
  assert_contains "$out" "closing plan(s) unverified" "notice"
  mkdir -p "$d/.harness/evidence"; printf '### 2026-01-01 · %s · PASS\nRed: proven (tests/x)\n' "$(git -C "$d" rev-parse --short HEAD)" > "$d/.harness/evidence/2026-01-01-p.md"
  (cd "$d" && bash "$HOOKS/pre-commit") >/dev/null 2>&1 || _fail "fresh PASS should allow closing"
  echo 'x=1' > "$d/code.py"; git -C "$d" add code.py
  rc=0; out="$(cd "$d" && HARNESS_ALLOW_UNVERIFIED_DONE=1 bash "$HOOKS/pre-commit" 2>&1)" || rc=$?
  assert_eq "$rc" 1 "code staged with the close is not fresh, override does not apply when evidence exists"
}
t_precommit_blocks_status_done_in_place() {
  local d rc=0; d="$(_done_repo)"
  sed -i.bak 's/active$/done/' "$d/docs/plans/active/2026-01-01-p.md"; rm "$d/docs/plans/active/"*.bak; git -C "$d" add -A
  (cd "$d" && bash "$HOOKS/pre-commit") >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" 1 "Status: done without evidence blocks"
  printf '\nnote\n' >> "$d/docs/plans/active/2026-01-01-p.md"; git -C "$d" -c user.email=t@e -c user.name=t -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm x >/dev/null
  printf 'more\n' >> "$d/docs/plans/active/2026-01-01-p.md"; git -C "$d" add -A
  (cd "$d" && bash "$HOOKS/pre-commit") >/dev/null 2>&1 || _fail "editing an already-done plan is not a close"
}
t_hooks_fail_closed_when_gate_unresolvable() {
  local d out rc h; d="$(_hook_repo true)"; mkdir "$d/.harness"
  echo '{"gate_wired": true}' > "$d/.harness/init-state.json"
  printf 'include missing.mk\n' >> "$d/Makefile"
  for h in pre-commit pre-push; do
    rc=0; out="$(cd "$d" && bash "$HOOKS/$h" </dev/null 2>&1)" || rc=$?
    assert_eq "$rc" 1 "$h fails when make -n rejects the Makefile"
    assert_contains "$out" "cannot resolve" "$h says why"; assert_contains "$out" "make -n check" "$h names the fix"
    assert_contains "$out" "missing.mk" "$h shows make's error"
  done
  rm "$d/.harness/init-state.json"; rc=0
  (cd "$d" && bash "$HOOKS/pre-commit" >/dev/null 2>&1) || rc=$?
  assert_eq "$rc" 1 "no local init state (a teammate's clone) but a Makefile: still an error"
  echo '{"layers_done": []}' > "$d/.harness/init-state.json"
  (cd "$d" && bash "$HOOKS/pre-commit" >/dev/null 2>&1) || _fail "mid-setup still skips"
}
_staged_repo() { # committed a.sh; check-fast syntax-checks every *.sh
  local d; d="$(_hook_repo 'for f in *.sh; do sh -n $$f || exit 1; done')"
  ( cd "$d" && echo 'echo a' > a.sh && git init -q -b main && git add -A \
    && git -c user.email=t@e -c user.name=t -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm init ) >/dev/null
  echo "$d"
}
_commit() { RC=0; OUT="$(cd "$1" && shift && git -c user.email=t@e -c user.name=t -c commit.gpgsign=false -c core.hooksPath="$HOOKS" commit -qm x "$@" 2>&1)" || RC=$?; }
t_precommit_staged_snapshot() {
  local d; d="$(_staged_repo)"
  echo 'echo b' > "$d/b.sh"; git -C "$d" add b.sh; echo 'if then' > "$d/a.sh"   # good change staged, broken edit not
  _commit "$d"; assert_eq "$RC" 1 "default: the working tree is tested"
  assert_contains "$OUT" "unstaged or untracked changes are part of this check (a.sh)" "warning names them"
  HARNESS_HOOK_STAGED_ONLY=1 _commit "$d"; assert_eq "$RC" 0 "staged-only: the commit is good on its own"
  assert_eq "$(git -C "$d" worktree list | wc -l | tr -d ' ')" 1 "scratch worktree removed"
  assert_eq "$(cat "$d/a.sh")" "if then" "unstaged edit untouched"
  echo 'fi fi' > "$d/c.sh"; git -C "$d" add c.sh; rm "$d/c.sh"           # broken file staged, deleted on disk
  HARNESS_HOOK_STAGED_ONLY=1 _commit "$d"; assert_eq "$RC" 1 "staged-only: a broken staged file fails"
  git -C "$d" rm -q --cached c.sh; echo 'echo a' > "$d/a.sh"; echo 'echo d' > "$d/d.sh"; git -C "$d" add d.sh
  _commit "$d"; assert_eq "$RC" 0 "clean tree"; assert_not_contains "$OUT" "unstaged" "no warning"
}
t_precommit_staged_snapshot_keeps_merge_head() {
  # merge-aware test selection in the repo reads MERGE_HEAD; the scratch worktree must see the real one
  local d m; d="$(_staged_repo)"; printf 'check-fast:\n\t@echo "MH=$$(git rev-parse -q --verify MERGE_HEAD)"\n' > "$d/Makefile"
  ( cd "$d" && git add Makefile && git -c user.email=t@e -c user.name=t -c commit.gpgsign=false commit -qm mk && git checkout -qb side \
    && echo 'echo s' > s.sh && git add s.sh && git -c user.email=t@e -c user.name=t -c commit.gpgsign=false commit -qm s \
    && git checkout -q main && echo 'echo u' > u.sh ) >/dev/null   # u.sh untracked: the staged-only path runs
  m="$(git -C "$d" rev-parse side)"
  RC=0; OUT="$(cd "$d" && HARNESS_HOOK_STAGED_ONLY=1 bash "$HOOKS/pre-commit" 2>&1)" || RC=$?
  assert_eq "$RC" 0 "no merge: $OUT"; assert_contains "$OUT" "MH=" "ran"; assert_not_contains "$OUT" "MH=$m" "no MERGE_HEAD without a merge"
  git -C "$d" -c user.email=t@e -c user.name=t merge -q --no-ff --no-commit side >/dev/null 2>&1
  RC=0; OUT="$(cd "$d" && HARNESS_HOOK_STAGED_ONLY=1 bash "$HOOKS/pre-commit" 2>&1)" || RC=$?
  assert_eq "$RC" 0 "merge: $OUT"; assert_contains "$OUT" "MH=$m" "MERGE_HEAD visible in the staged snapshot"
  assert_eq "$(git -C "$d" worktree list | wc -l | tr -d ' ')" 1 "scratch worktree removed"
  assert_eq "$(git -C "$d" rev-parse MERGE_HEAD)" "$m" "the real merge is untouched"
}
_push() { # _push <dir> <stdin> [env...]: run pre-push with git's ref lines
  local d="$1" in="$2"; shift 2; RC=0
  OUT="$(cd "$d" && printf '%s\n' "$in" | env "$@" bash "$HOOKS/pre-push" 2>&1)" || RC=$?
}
t_prepush_tests_only_what_is_pushed() {
  local d h z=0000000000000000000000000000000000000000; d="$(_staged_repo)"; h="$(git -C "$d" rev-parse HEAD)"
  printf 'check-fast:\n\t@true\ncheck:\n\t@false\n' > "$d/Makefile"
  ( cd "$d" && git -c user.email=t@e -c user.name=t -c commit.gpgsign=false commit -qam mk ) >/dev/null; h="$(git -C "$d" rev-parse HEAD)"
  _push "$d" "refs/heads/main $h refs/heads/main $z"; assert_eq "$RC" 2 "the checked-out branch runs check"
  _push "$d" "refs/tags/v1 $h refs/tags/v1 $z"; assert_eq "$RC" 0 "tag push skips"; assert_contains "$OUT" "skipping" "says so"
  _push "$d" "(delete) $z refs/heads/old $h"; assert_eq "$RC" 0 "branch deletion skips"
  _push "$d" "refs/heads/other 1111111111111111111111111111111111111111 refs/heads/other $z"
  assert_eq "$RC" 0 "another branch skips"; assert_contains "$OUT" "checked-out" "names why"
  _push "$d" "refs/heads/main $h refs/heads/main $z" SKIP_HOOKS=1; assert_eq "$RC" 0 "SKIP_HOOKS=1 skips"
  assert_contains "$OUT" "SKIP_HOOKS=1" "says so"
  RC=0; (cd "$d" && SKIP_HOOKS=1 bash "$HOOKS/pre-commit" >/dev/null 2>&1) || RC=$?; assert_eq "$RC" 0 "pre-commit too"
}
t_prepush_tests_the_pushed_commit() {
  # opted in, check judges what is pushed: an uncommitted fix must not hide a broken commit, nor a half-edit block a good one
  local d h z=0000000000000000000000000000000000000000; d="$(_staged_repo)"
  printf 'check:\n\t@for f in *.sh; do sh -n $$f || exit 1; done\n' > "$d/Makefile"
  ( cd "$d" && git add Makefile && echo 'if then' > b.sh && git add b.sh \
    && git -c user.email=t@e -c user.name=t -c commit.gpgsign=false commit -qm broken && echo 'echo b' > b.sh ) >/dev/null
  h="$(git -C "$d" rev-parse HEAD)"
  _push "$d" "refs/heads/main $h refs/heads/main $z" HARNESS_HOOK_STAGED_ONLY=1; assert_eq "$RC" 2 "broken commit, fixed tree: blocked: $OUT"
  assert_contains "$OUT" "scratch worktree" "says it checked the pushed commit"
  assert_eq "$(cat "$d/b.sh")" "echo b" "working tree untouched"
  ( cd "$d" && git add b.sh && git -c user.email=t@e -c user.name=t -c commit.gpgsign=false commit -qm fix && echo 'if then' > b.sh ) >/dev/null
  h="$(git -C "$d" rev-parse HEAD)"
  _push "$d" "refs/heads/main $h refs/heads/main $z" HARNESS_HOOK_STAGED_ONLY=1; assert_eq "$RC" 0 "good commit, broken edit: passes: $OUT"
  assert_eq "$(git -C "$d" worktree list | wc -l | tr -d ' ')" 1 "scratch worktree removed"
  echo 'echo b' > "$d/b.sh"
  _push "$d" "refs/heads/main $h refs/heads/main $z"; assert_eq "$RC" 0 "clean tree passes"
  assert_contains "$OUT" "in place" "clean tree runs in place"
}
t_prepush_dirty_tree_checks_in_place_by_default() {
  # a scratch worktree lacks gitignored inputs (local config, generated code, build caches): opt-in only
  local d h z=0000000000000000000000000000000000000000 hk; d="$(_staged_repo)"
  printf 'check:\n\t@test -f local.cfg && echo GATE-OK\n' > "$d/Makefile"; printf 'local.cfg\n' >> "$d/.gitignore"; touch "$d/local.cfg"
  ( cd "$d" && git add -A && git -c user.email=t@e -c user.name=t -c commit.gpgsign=false commit -qm cfg && echo 'echo w' > w.sh ) >/dev/null
  h="$(git -C "$d" rev-parse HEAD)"
  _push "$d" "refs/heads/main $h refs/heads/main $z"; assert_eq "$RC" 0 "gitignored input present in place: $OUT"
  assert_contains "$OUT" "HARNESS_HOOK_STAGED_ONLY=1" "names the opt-in"; assert_contains "$OUT" "GATE-OK" "ran"
  hk="$(mktemp -d)"; cp "$HOOKS/pre-push" "$hk/"   # an upgrade that never installed snapshot.sh
  RC=0; OUT="$(cd "$d" && printf '%s\n' "refs/heads/main $h refs/heads/main $z" | HARNESS_HOOK_STAGED_ONLY=1 bash "$hk/pre-push" 2>&1)" || RC=$?
  assert_eq "$RC" 0 "no snapshot.sh: in place: $OUT"; assert_contains "$OUT" "snapshot.sh missing" "says so"
}
