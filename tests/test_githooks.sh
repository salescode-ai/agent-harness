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
