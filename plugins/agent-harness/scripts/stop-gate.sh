#!/usr/bin/env bash
# Stop: if code changed (uncommitted, or committed ahead of the base branch) since the last green run,
# run the repo's check-fast and block the stop on failure. In a workspace, does this for every member repo
# that changed, using that repo's own gate. Success is silent. Disable with HARNESS_STOP_GATE=0.
source "$(dirname "$0")/_lib.sh"
[[ "${HARNESS_STOP_GATE:-1}" == "0" ]] && exit 0
# Loop guard first, with a grep fallback so a missing python3 can never cause an endless block.
grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true' <<<"$HOOK_INPUT" && exit 0

STATE=""; LC_SUFFIX=""; FAILED=0; REPORT=""
gate_repo() { # gate_repo <repo dir> <base> <label>
  local dir="$1" base="$2" label="$3" cmd dirty ahead=0 fp out rc
  [[ -f "$dir/AGENTS.md" ]] || return 0
  # half-built harness: init-state.json says the gate isn't wired yet (bad JSON or no python3 -> ignored)
  [[ -f "$dir/.harness/init-state.json" ]] && command -v python3 >/dev/null &&
    python3 -c "import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get('gate_wired') is False else 1)" "$dir/.harness/init-state.json" 2>/dev/null && return 0
  cmd="$(harness_cmd "$dir" check-fast 2>/dev/null)" || return 0
  dirty="$(git -C "$dir" status --porcelain -- . ':(exclude)docs' ':(exclude)*.md' ':(exclude).harness' 2>/dev/null)"
  git -C "$dir" rev-parse --verify -q "$base" >/dev/null && ahead="$(git -C "$dir" rev-list --count "$base"..HEAD 2>/dev/null || echo 0)"
  [[ -z "$dirty" && "$ahead" == "0" ]] && return 0
  fp="$( { git -C "$dir" rev-parse HEAD; git -C "$dir" diff HEAD; (cd "$dir" && git ls-files -z --others --exclude-standard | xargs -0 cksum 2>/dev/null); } 2>/dev/null | cksum | cut -d' ' -f1)"
  local key="$STATE/last-green-${label//[^A-Za-z0-9_-]/_}"
  [[ -f "$key" && "$(cat "$key")" == "$fp" ]] && return 0
  out="$(cd "$dir" && eval "$cmd" 2>&1)"; rc=$?
  if (( rc == 0 )); then echo "$fp" > "$key"; echo "$fp pass $(date +%Y-%m-%d)" > "$STATE/last-check$LC_SUFFIX"; return 0; fi
  FAILED=1
  REPORT+="---- $label: check-fast failed (last 30 lines)"$'\n'"$(tail -30 <<<"$out")"$'\n'
}

ws="$(workspace_root)"
if [[ -n "$ws" && -z "$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null)" ]]; then
  STATE="$ws/.harness"; mkdir -p "$STATE"
  while IFS=$'\t' read -r name path base; do
    [[ -n "$name" && -d "$ws/$path" ]] || continue
    [[ "$(member_state "$ws/$path")" == present ]] || continue
    LC_SUFFIX="-${name//[^A-Za-z0-9_-]/_}"
    gate_repo "$ws/$path" "${HARNESS_BASE:-origin/$base}" "$name"
  done <<<"$(workspace_members "$ws")"
else
  root="$(repo_root)"; [[ -n "$root" ]] || exit 0
  STATE="$root/.harness"; mkdir -p "$STATE"
  gate_repo "$root" "${HARNESS_BASE:-origin/main}" "repo"
fi
(( FAILED == 0 )) && exit 0
{
  echo "Stop blocked by agent-harness: a repo's check-fast failed on your changes."
  echo "Fix the failures below in the repo named (do not disable or skip checks), then finish."
  echo "$REPORT"
} >&2
exit 2
