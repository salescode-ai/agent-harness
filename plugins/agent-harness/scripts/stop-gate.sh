#!/usr/bin/env bash
# Stop: if code changed (uncommitted, or committed ahead of the base branch) since the last green run,
# run the repo's check-fast and block the stop on failure. In a workspace, does this for every member repo
# that changed, using that repo's own gate. Success is silent. Disable with HARNESS_STOP_GATE=0.
source "$(dirname "$0")/_lib.sh"
[[ "${HARNESS_STOP_GATE:-1}" == "0" ]] && exit 0
# Loop guard first, with a grep fallback so a missing python3 can never cause an endless block.
grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true' <<<"$HOOK_INPUT" && exit 0

STATE=""; LC_SUFFIX=""; FAILED=0; REPORT=""; SKIPPED=""
changed_since() { # changed_since <dir> <base>: uncommitted source changes or commits ahead of base
  local ahead=0
  [[ -n "$(git -C "$1" status --porcelain -- . ':(exclude)docs' ':(exclude)*.md' ':(exclude).harness' 2>/dev/null)" ]] && return 0
  git -C "$1" rev-parse --verify -q "$2" >/dev/null && ahead="$(git -C "$1" rev-list --count "$2"..HEAD 2>/dev/null || echo 0)"
  [[ "$ahead" != "0" ]]
}
gate_repo() { # gate_repo <repo dir> <base> <label>
  local dir="$1" base="$2" label="$3" cmd fp out rc
  [[ -f "$dir/AGENTS.md" ]] || return 0
  init_pending "$dir" && return 0  # half-built harness: harness-init has not wired the gate yet
  cmd="$(harness_cmd "$dir" check-fast 2>/dev/null)" || return 0
  changed_since "$dir" "$base" || return 0
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
    b="${HARNESS_BASE:-${base:+origin/$base}}"; [[ -n "$b" ]] || b="$(default_base "$ws/$path")"
    st="$(member_state "$ws/$path")"
    if [[ "$st" != present ]]; then changed_since "$ws/$path" "$b" && SKIPPED+=" $name ($st harness)"; continue; fi
    LC_SUFFIX="-${name//[^A-Za-z0-9_-]/_}"
    gate_repo "$ws/$path" "$b" "$name"
  done <<<"$(workspace_members "$ws")"
else
  root="$(repo_root)"; [[ -n "$root" ]] || exit 0
  STATE="$root/.harness"; mkdir -p "$STATE"
  gate_repo "$root" "${HARNESS_BASE:-$(default_base "$root")}" "repo"
fi
(( FAILED == 0 )) && exit 0
{
  echo "Stop blocked by agent-harness: a repo's check-fast failed on your changes."
  echo "Fix the failures below in the repo named (do not disable or skip checks), then finish."
  echo "$REPORT"
  [[ -n "$SKIPPED" ]] && echo "Not gated (no complete harness), changed anyway:$SKIPPED"
} >&2
exit 2
