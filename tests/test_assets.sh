ASSETS="$PLUGIN/scripts/assets.py"
_age() { # _age <repo> <dest>: replace an installed asset with "old" content recorded as the installed copy
  printf '# old plugin copy\n' > "$1/$2"
  python3 - "$1" "$2" <<'PY'
import hashlib, json, sys
p = sys.argv[1] + "/scripts/harness/assets.json"; m = json.load(open(p))
m["sha256"][sys.argv[2]] = hashlib.sha256(open(sys.argv[1] + "/" + sys.argv[2], "rb").read()).hexdigest()
json.dump(m, open(p, "w"))
PY
}

t_assets_stale_refresh_skips_modified() {
  local d out; d="$(mktemp -d)/my repo"; mkdir -p "$d"; ( cd "$d" && git init -q -b main && printf '# a\n' > AGENTS.md )
  mkdir -p "$d/scripts/harness/sensors"; printf '{"mine":1}\n' > "$d/scripts/harness/sensors/registry.json"; printf 'all:\n' > "$d/Makefile"
  out="$(python3 "$ASSETS" install "$d")"
  assert_contains "$out" "installed scripts/harness/cmd.sh" "install"
  [ -x "$d/scripts/harness/cmd.sh" ] && [ -x "$d/.githooks/pre-commit" ] && [ -f "$d/harness.mk" ]
  [ -f "$d/scripts/harness/sensors/fixtures/no-prod-data/seed.sql" ] || _fail "missing starter fixture not installed"
  assert_eq "$(cat "$d/scripts/harness/sensors/registry.json")" '{"mine":1}' "existing registry kept on install"
  assert_contains "$(python3 "$ASSETS" status "$d")" "current" "all current"
  assert_eq "$(python3 "$ASSETS" count "$d")" 0 "none stale"
  _age "$d" harness.mk; _age "$d" scripts/harness/sensors/no-prod-data.sh
  printf '# my edit\n' >> "$d/scripts/harness/lint.sh"
  out="$(python3 "$ASSETS" status "$d")"
  assert_contains "$out" "stale     harness.mk" "stale reported"
  assert_contains "$out" "modified  scripts/harness/lint.sh — modified locally, review diff" "modified reported"
  assert_eq "$(python3 "$ASSETS" count "$d")" 2 "two stale"
  assert_contains "$(printf '{"cwd":"%s"}' "$d" | "$PLUGIN/scripts/session-context.sh")" \
    "harness scripts are older than the plugin (2 files) — run /agent-harness:harness-upgrade" "session line"
  out="$(python3 "$ASSETS" refresh "$d")"
  assert_contains "$out" "updated   harness.mk" "refreshed"
  cmp -s "$d/harness.mk" "$PLUGIN/skills/harness-init/assets/harness.mk" || _fail "harness.mk not refreshed"
  cmp -s "$d/scripts/harness/sensors/no-prod-data.sh" "$PLUGIN/skills/harness-init/assets/harness/sensors/no-prod-data.sh" || _fail "sensor not refreshed"
  grep -q '# my edit' "$d/scripts/harness/lint.sh" || _fail "modified copy overwritten"
  assert_eq "$(cat "$d/scripts/harness/sensors/registry.json")" '{"mine":1}' "registry untouched"
  assert_eq "$(cat "$d/Makefile")" 'all:' "Makefile untouched"
  assert_not_contains "$(cat "$d/scripts/harness/assets.json")" "registry.json" "repo-owned not in manifest"
  assert_eq "$(python3 "$ASSETS" count "$d")" 0 "nothing stale after refresh"
  assert_not_contains "$(printf '{"cwd":"%s"}' "$d" | "$PLUGIN/scripts/session-context.sh")" "older than the plugin" "line gone"
}
t_assets_released_copy_without_manifest_is_stale() {
  local d c out f=plugins/agent-harness/scripts/harness-cmd.sh; d="$(mktemp -d)"; mkdir -p "$d/scripts/harness"
  # a pre-manifest install holding the first released cmd.sh: recognised through asset-history.json
  c="$(git -C "$ROOT" log --format=%H -- "$f" 2>/dev/null | tail -1)"
  [ -n "$c" ] || skip assets_history "no git history"
  git -C "$ROOT" show "$c:$f" > "$d/scripts/harness/cmd.sh"
  printf 'unknown\n' > "$d/scripts/harness/lint.sh"
  out="$(python3 "$ASSETS" status "$d")"
  assert_contains "$out" "stale     scripts/harness/cmd.sh" "released copy is stale"
  assert_contains "$out" "modified  scripts/harness/lint.sh" "unknown content is modified"
}
t_assets_workspace() {
  local w out; w="$(mktemp -d)"; echo '{"repos":[]}' > "$w/harness-workspace.json"
  out="$(python3 "$ASSETS" install "$w")"
  [ -x "$w/ws.sh" ] && [ -f "$w/scripts/harness/cmd.sh" ] && [ ! -e "$w/harness.mk" ] && [ ! -e "$w/.githooks" ]
  _age "$w" ws.sh
  assert_contains "$(python3 "$ASSETS" status "$w")" "stale     ws.sh" "workspace stale"
}
t_assets_history_has_current() {
  python3 - "$PLUGIN" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1] + "/scripts"); import assets
h = json.load(open(assets.HISTORY))
miss = [s for s, _ in assets.assets(None) if assets.sha(sys.argv[1] + "/" + s) not in h.get(s, {})]
assert not miss, "asset-history.json lacks the current copy of %s: add its sha256 for this release" % miss
PY
}
t_assets_released_precommit_refreshed() {
  # a 2.0.4 repo's unmodified pre-commit (no plan-close check) is refreshed automatically
  local d; d="$(mktemp -d)"; ( cd "$d" && git init -q -b main && printf '# a\n' > AGENTS.md ); python3 "$ASSETS" install "$d" >/dev/null
  git -C "$ROOT" show f7d2c32:plugins/agent-harness/skills/harness-init/assets/githooks/pre-commit > "$d/.githooks/pre-commit" 2>/dev/null \
    || skip assets_precommit "no git history"
  assert_contains "$(python3 "$ASSETS" status "$d")" "stale     .githooks/pre-commit" "released copy is stale"
  python3 "$ASSETS" refresh "$d" >/dev/null
  grep -q 'plan-check.sh fresh' "$d/.githooks/pre-commit" || _fail "pre-commit not refreshed"
}
