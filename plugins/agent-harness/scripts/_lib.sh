# Shared helpers for agent-harness hooks. Hooks fail open: if a helper is missing, allow and stay quiet.
HOOK_INPUT="$(cat)"
json_get() { # json_get <python expression on d>, e.g. json_get "d['tool_input']['command']"
  command -v python3 >/dev/null || { echo ""; return; }
  HOOK_INPUT="$HOOK_INPUT" python3 -c "import json,os
try:
  d=json.loads(os.environ['HOOK_INPUT']); v=$1
  print(v if v is not None else '')
except Exception: print('')" 2>/dev/null
}
decide() { # decide <allow|ask|deny> <reason>
  command -v python3 >/dev/null || exit 0
  python3 -c "import json,sys; print(json.dumps({'hookSpecificOutput':{'hookEventName':'PreToolUse','permissionDecision':sys.argv[1],'permissionDecisionReason':sys.argv[2]}}))" "$1" "$2"
  exit 0
}
HOOK_CWD="$(json_get "d.get('cwd','')")"; [[ -n "$HOOK_CWD" && -d "$HOOK_CWD" ]] || HOOK_CWD="$PWD"
repo_root() { git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null; }
workspace_root() { # nearest ancestor of the session cwd holding harness-workspace.json
  local d="$HOOK_CWD"
  while [[ -n "$d" && "$d" != "/" ]]; do
    [[ -f "$d/harness-workspace.json" ]] && { echo "$d"; return; }
    d="$(dirname "$d")"
  done
}
workspace_members() { # prints "name<TAB>path<TAB>base" per member repo (paths relative to workspace root)
  command -v python3 >/dev/null || return
  python3 - "$1/harness-workspace.json" <<'PY' 2>/dev/null
import json,sys
m=json.load(open(sys.argv[1]))
for r in m.get("repos",[]):
    print("\t".join([r["name"], r.get("path", r["name"]), r.get("base","main")]))
PY
}
plan_dirs() { # plan folders named in <root>/AGENTS.md (Work Artifacts), else docs/plans/active
  local root="$1" dirs
  dirs="$(grep -oE '`[^` ]*plans/[^` ]*`' "$root/AGENTS.md" 2>/dev/null | tr -d '`' | while read -r p; do dirname "$p"; done | sort -u)"
  [[ -z "$dirs" ]] && dirs="docs/plans/active"
  echo "$dirs"
}
active_plan() { # active_plan <root> <branch>: plan matching the branch, else newest (≤14 days) with unchecked items
  local root="$1" branch="$2" slug cands f
  slug="${branch##*/}"; case "$slug" in main|master|develop|"") slug="" ;; esac
  cands="$(cd "$root" && for d in $(plan_dirs "$root"); do ls -t "$d"/*.md 2>/dev/null; done | grep -v '/TEMPLATE\.md$')"
  [[ -z "$cands" ]] && return
  if [[ -n "$slug" ]]; then f="$(grep -i -- "$slug" <<<"$cands" | head -1)"; [[ -n "$f" ]] && { echo "$f"; return; }; fi
  while IFS= read -r f; do
    [[ -n "$(cd "$root" && find "$f" -mtime -14 2>/dev/null)" ]] || continue
    grep -qE '^[[:space:]]*- \[ \]' "$root/$f" && { echo "$f"; return; }
  done <<<"$(head -10 <<<"$cands")"
}
harness_cmd() { # harness_cmd <dir> <target> [T]: print the command for a harness target (see harness-cmd.sh)
  "$(dirname "${BASH_SOURCE[0]}")/harness-cmd.sh" "$@"
}
