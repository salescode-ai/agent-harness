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
  harness-workspace.json)
    [[ -f "$path" ]] && decide ask "harness-workspace.json defines which repos own which changes. Confirm this edit was requested." ;;
esac
exit 0
