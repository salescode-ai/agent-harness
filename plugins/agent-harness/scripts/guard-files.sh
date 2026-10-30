#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit): protect secrets, the CLAUDE.md shim, and human-owned harness files.
source "$(dirname "$0")/_lib.sh"
[[ "${HARNESS_GUARD:-1}" == "0" ]] && exit 0
path="$(json_get "d['tool_input'].get('file_path','')")"
[[ -z "$path" ]] && exit 0
base="$(basename "$path")"
case "$base" in
  .env|.env.*) [[ "$base" == ".env.example" || "$base" == ".env.sample" || "$base" == ".env.template" ]] || decide deny "Writing to $base is blocked: secrets files are human-managed. Update .env.example instead." ;;
  CLAUDE.md)
    new="$(json_get "chr(10).join([d['tool_input'].get('content') or '', d['tool_input'].get('new_string') or ''] + [e.get('new_string','') for e in d['tool_input'].get('edits',[])])")"
    if [[ -n "$new" ]] && grep -vE '^[[:space:]]*$|^[[:space:]]*#|^[[:space:]]*@[^ ]+[[:space:]]*$|^[[:space:]]*<!--.*-->[[:space:]]*$' <<<"$new" | grep -q .; then
      decide deny "CLAUDE.md files are shims (@-references only). Put instructions in AGENTS.md — skill/pack setup blocks go under \"## Agent skills\", working guidelines under \"Working Principles\"."
    fi ;;
  INVARIANTS.md)
    [[ -f "$path" ]] && decide ask "INVARIANTS.md changes need human sign-off (Harness Integrity). Confirm this edit was requested." ;;
  init-state.json)
    # the git hooks skip while "gate_wired" is not true: once wired, no edit may unwire it (init/upgrade only set it true)
    if [[ "$(basename "$(dirname "$path")")" == ".harness" && -f "$path" ]] && ! HOOK_INPUT="$HOOK_INPUT" python3 - "$path" <<'PY' 2>/dev/null
import json, os, sys
d = json.loads(os.environ["HOOK_INPUT"])["tool_input"]
try:
    old = open(sys.argv[1]).read()
    if json.loads(old).get("gate_wired") is not True:
        sys.exit(0)
except ValueError:
    sys.exit(0)
new = d.get("content")
if new is None:
    new = old
    for e in d.get("edits") or [d]:
        o, n = e.get("old_string", ""), e.get("new_string", "")
        new = new.replace(o, n) if e.get("replace_all") else new.replace(o, n, 1)
try:
    sys.exit(0 if json.loads(new).get("gate_wired") is True else 1)
except (ValueError, AttributeError):
    sys.exit(1)
PY
    then
      decide deny "The harness gate is wired: .harness/init-state.json must keep \"gate_wired\": true (the git hooks skip without it). Fix the failing check instead."
    fi ;;
  harness-workspace.json)
    [[ -f "$path" ]] && decide ask "harness-workspace.json defines which repos own which changes. Confirm this edit was requested." ;;
esac
exit 0
