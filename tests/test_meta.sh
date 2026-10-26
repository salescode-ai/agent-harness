t_no_named_packs() {
  local out
  out="$(cd "$ROOT" && grep -rniE 'superpowers|mattpocock|pocock|karpathy' plugins README.md install-local.sh || true)"
  assert_eq "$out" "" "no named packs"
}
t_version_2() {
  grep -q '"version": "2.0.0"' "$PLUGIN/.claude-plugin/plugin.json"
  grep -q '"version": "2.0.0"' "$ROOT/.claude-plugin/marketplace.json"
}
t_no_pycache() {
  local out
  out="$(find "$ROOT/plugins" -name __pycache__)"
  assert_eq "$out" "" "no __pycache__"
}
