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
  (cd "$d" && bash "$HOOKS/pre-push") >/dev/null 2>&1 && _fail "pre-push should fail" || true
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
    out="$(cd "$d" && bash "$HOOKS/$h" 2>&1)" || _fail "$h blocked mid-init"
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
  mkdir -p "$d/.harness/evidence"; printf '### 2026-01-01 · %s · PASS\n' "$(git -C "$d" rev-parse --short HEAD)" > "$d/.harness/evidence/2026-01-01-p.md"
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
