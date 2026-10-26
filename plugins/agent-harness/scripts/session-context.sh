#!/usr/bin/env bash
# SessionStart: short orientation (stdout becomes session context). Silent outside harnessed repos/workspaces.
source "$(dirname "$0")/_lib.sh"
print_plan() { # print_plan <root> <branch> <label>
  local plan next last
  plan="$(active_plan "$1" "$2")"; [[ -z "$plan" ]] && return
  next="$(awk '/^## Steps/{f=1;next} /^## /{f=0} f && /- \[ \]/{sub(/^[[:space:]]*- \[ \][[:space:]]*/,""); print; exit}' "$1/$plan")"
  [[ -z "$next" ]] && next="$(grep -m1 -E '^[[:space:]]*- \[ \]' "$1/$plan" | sed -E 's/^[[:space:]]*- \[ \][[:space:]]*//')"
  last="$(grep -E '^(- )?[0-9]{4}-[0-9]{2}-[0-9]{2}' "$1/$plan" | tail -1)"
  echo "[agent-harness] ${3}active plan: $plan"
  [[ -n "$next" ]] && echo "[agent-harness] ${3}next unchecked: $next"
  [[ -n "$last" ]] && echo "[agent-harness] ${3}last progress: ${last#- }"
}
ws="$(workspace_root)"
if [[ -n "$ws" && -z "$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null)" ]]; then
  echo "[agent-harness] workspace: $(basename "$ws") — each change goes to the repo that owns it (see AGENTS.md); read that repo's AGENTS.md before editing it"
  while IFS=$'\t' read -r name path base; do
    [[ -n "$name" ]] || continue
    if [[ ! -d "$ws/$path/.git" && ! -f "$ws/$path/.git" ]]; then echo "[agent-harness]   $name: not checked out ($path)"; continue; fi
    br="$(git -C "$ws/$path" branch --show-current 2>/dev/null)"
    dirty="$(git -C "$ws/$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    h="harness"; [[ -f "$ws/$path/AGENTS.md" ]] || h="NO HARNESS"
    echo "[agent-harness]   $name: ${br:-detached} · $dirty uncommitted · $h"
  done <<<"$(workspace_members "$ws")"
  print_plan "$ws" "" ""
  echo "[agent-harness] workspace gate: make check (runs each changed repo's own gate) · before claiming done: harness-verify"
  exit 0
fi
root="$(repo_root)"; [[ -n "$root" && -f "$root/AGENTS.md" ]] || exit 0
branch="$(git -C "$root" branch --show-current 2>/dev/null)"
dirty="$(git -C "$root" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
echo "[agent-harness] branch: ${branch:-detached} · uncommitted files: $dirty"
print_plan "$root" "$branch" ""
echo "[agent-harness] resuming work? use the harness-session skill · before claiming done: harness-verify"
exit 0
