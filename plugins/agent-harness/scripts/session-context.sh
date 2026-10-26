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
    echo "[agent-harness]   $name: ${br:-detached} · $dirty uncommitted · harness $(member_state "$ws/$path")"
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
if [[ -d "$root/.githooks" && -z "$(git -C "$root" config core.hooksPath 2>/dev/null)" ]]; then
  mgr=""; for m in .husky lefthook.yml lefthook.yaml .lefthook.yml .pre-commit-config.yaml; do [[ -e "$root/$m" ]] && mgr=1; done
  [[ -z "$mgr" ]] && echo "[agent-harness] git hooks not installed — run: make setup"
fi
log="$root/docs/harness/AUDIT-LOG.md"
if [[ -f "$log" ]] && command -v python3 >/dev/null; then
  cad="$(grep -oE 'quick audit: every [0-9]+ days' "$root/AGENTS.md" 2>/dev/null | head -1 | grep -oE '[0-9]+')"
  age="$(grep -E '^\| *[0-9]{4}-[0-9]{2}-[0-9]{2} *\|' "$log" | tail -1 | python3 -c "import sys,datetime
try: print((datetime.date.today()-datetime.date.fromisoformat(sys.stdin.read().split('|')[1].strip())).days)
except Exception: pass" 2>/dev/null)"
  [[ -n "$age" && "$age" -gt "${cad:-30}" ]] && echo "[agent-harness] harness audit is $age days old — run /harness-audit"
fi
if [[ -f "$root/.harness/init-state.json" ]] && command -v python3 >/dev/null; then
  python3 -c "import json,sys
sys.exit(0 if len(json.load(open(sys.argv[1])).get('layers_done',[]))<5 else 1)" "$root/.harness/init-state.json" 2>/dev/null \
    && echo "[agent-harness] harness setup in progress — resume with /harness-init"
fi
echo "[agent-harness] resuming work? use the harness-session skill · before claiming done: harness-verify"
exit 0
