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
    print("\t".join([r["name"], r.get("path", r["name"]), r.get("base","")]))
PY
}
plan_dirs() { # plan folders named in <root>/AGENTS.md (Work Artifacts), else docs/plans/active
  local root="$1" dirs
  dirs="$(grep -oE '`[^` ]*plans/[^` ]*`' "$root/AGENTS.md" 2>/dev/null | tr -d '`' | while read -r p; do dirname "$p"; done | sort -u)"
  [[ -z "$dirs" ]] && dirs="docs/plans/active"
  echo "$dirs"
}
active_plan() { # active_plan <root> <branch>: plan for the branch's ticket key (KEY-12-slug), else its slug, else newest (≤14 days) with unchecked items
  local root="$1" branch="$2" slug key cands f
  slug="${branch##*/}"; case "$slug" in main|master|develop|"") slug="" ;; esac
  key="$(grep -oE '^[A-Za-z][A-Za-z0-9]+-[0-9]+' <<<"$slug")"
  cands="$(cd "$root" && for d in $(plan_dirs "$root"); do ls -t "$d"/*.md 2>/dev/null; done | grep -v '/TEMPLATE\.md$')"
  [[ -z "$cands" ]] && return
  if [[ -n "$key" ]]; then  # file name, then the plan's Ticket: line
    f="$(grep -iE -- "(^|[^A-Za-z0-9])$key([^0-9]|$)" <<<"$cands" | head -1)"
    [[ -z "$f" ]] && f="$(while IFS= read -r c; do grep -qiE -- "Ticket[*]*:(.*[^A-Za-z0-9])?$key([^0-9]|$)" "$root/$c" 2>/dev/null && { echo "$c"; break; }; done <<<"$cands")"
    [[ -n "$f" ]] && { echo "$f"; return; }
  fi
  if [[ -n "$slug" ]]; then f="$(grep -i -- "$slug" <<<"$cands" | head -1)"; [[ -n "$f" ]] && { echo "$f"; return; }; fi
  while IFS= read -r f; do
    [[ -n "$(cd "$root" && find "$f" -mtime -14 2>/dev/null)" ]] || continue
    grep -qE '^[[:space:]]*- \[ \]' "$root/$f" && { echo "$f"; return; }
  done <<<"$(head -10 <<<"$cands")"
}
CODE_PATHS=(. ':(exclude)docs' ':(exclude)*.md' ':(exclude).harness')  # what counts as code for the stop gate
code_fp() { # code_fp <dir>: checksum of HEAD, uncommitted code changes and untracked code files
  ( cd "$1" 2>/dev/null || exit 0
    { git rev-parse HEAD; git diff HEAD -- "${CODE_PATHS[@]}"
      git ls-files -z --others --exclude-standard -- "${CODE_PATHS[@]}" | xargs -0 cksum 2>/dev/null; } 2>/dev/null | cksum | cut -d' ' -f1 )
}
session_file() { # session_file <dir>: where SessionStart records code_fp for this session (empty without a session id)
  local sid; sid="$(json_get "d.get('session_id','')")"
  [[ -n "$sid" ]] && echo "$1/.harness/session-${sid//[^A-Za-z0-9_-]/_}"
}
init_pending() { # init_pending <dir>: true while harness-init is mid-setup (init-state.json without "gate_wired": true)
  local f="$1/.harness/init-state.json"
  [[ -f "$f" ]] || return 1
  command -v python3 >/dev/null || { ! grep -qE '"gate_wired"[[:space:]]*:[[:space:]]*true' "$f"; return; }
  python3 -c "import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(1)  # unreadable state file: ignore it, keep gating
sys.exit(0 if isinstance(d,dict) and d.get('gate_wired') is not True else 1)" "$f" 2>/dev/null
}
harness_cmd() { # harness_cmd <dir> <target> [T]: print the command for a harness target (see harness-cmd.sh)
  bash "$(dirname "${BASH_SOURCE[0]}")/harness-cmd.sh" "$@"
}
member_state() { # member_state <dir>: present (AGENTS.md + INVARIANTS.md + resolvable check) | partial | none
  local d="$1" n=0
  [[ -f "$d/AGENTS.md" ]] && n=$((n+1))
  [[ -f "$d/INVARIANTS.md" ]] && n=$((n+1))
  harness_cmd "$d" check >/dev/null 2>&1 && n=$((n+1))
  case $n in 3) echo present;; 0) echo none;; *) echo partial;; esac
}
