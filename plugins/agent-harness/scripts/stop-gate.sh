#!/usr/bin/env bash
# Stop: if code changed (uncommitted, or committed ahead of the base branch) since the last green run,
# run the repo's check-fast and block the stop on failure. In a workspace, does this for every member repo
# that changed, using that repo's own gate. Success is silent. Disable with HARNESS_STOP_GATE=0.
source "$(dirname "$0")/_lib.sh"
[[ "${HARNESS_STOP_GATE:-1}" == "0" ]] && exit 0
# Loop guard: after a block (stop_hook_active, read with grep so a missing python3 can't loop), re-check only
# repos whose code changed since that block, and give up after MAX_BLOCKS consecutive blocks.
ACTIVE=0; grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true' <<<"$HOOK_INPUT" && ACTIVE=1
MAX_BLOCKS=3

STATE=""; LC_SUFFIX=""; FAILED=0; REPORT=""; SKIPPED=""; RERAN=0; STILL=""
changed_since() { # changed_since <dir> <base>: uncommitted source changes or commits ahead of base
  local ahead=0
  [[ -n "$(git -C "$1" status --porcelain -- . ':(exclude)docs' ':(exclude)*.md' ':(exclude).harness' 2>/dev/null)" ]] && return 0
  git -C "$1" rev-parse --verify -q "$2" >/dev/null && ahead="$(git -C "$1" rev-list --count "$2"..HEAD 2>/dev/null || echo 0)"
  [[ "$ahead" != "0" ]]
}
fail_summary() { # failure-marker lines (up to 20), then the last 10 lines; without markers the last 30
  local m; m="$(grep -E 'FAIL|ERROR|Error:|expected|AssertionError|Tests run:.*Failures|tests? completed, [0-9]+ failed|✗|error TS|SyntaxError' <<<"$1" | head -20)"
  if [[ -n "$m" ]]; then printf '%s\n...\n' "$m"; tail -10 <<<"$1"; else tail -30 <<<"$1"; fi
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
  local failkey="$STATE/last-fail-${label//[^A-Za-z0-9_-]/_}"
  if (( ACTIVE )) && [[ -f "$failkey" && "$(cat "$failkey")" == "$fp" ]]; then  # unchanged since the block
    FAILED=1; STILL+=" $label"; REPORT+="---- $label: check-fast still failing (no change since the last block)"$'\n'; return 0
  fi
  out="$(cd "$dir" && eval "$cmd" 2>&1)"; rc=$?
  mkdir -p "$STATE" 2>/dev/null  # only now: repos without a harness never get a .harness/
  if (( rc == 0 )); then echo "$fp" > "$key"; echo "$fp pass $(date +%Y-%m-%d)" > "$STATE/last-check$LC_SUFFIX"; rm -f "$failkey"; return 0; fi
  FAILED=1; RERAN=1; STILL+=" $label"
  echo "$fp" > "$failkey" 2>/dev/null
  REPORT+="---- $label: check-fast failed (failure lines, then the last lines)"$'\n'"$(fail_summary "$out")"$'\n'
}

ws="$(workspace_root)"
if [[ -n "$ws" && -z "$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null)" ]]; then
  STATE="$ws/.harness"
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
  STATE="$root/.harness"
  gate_repo "$root" "${HARNESS_BASE:-$(default_base "$root")}" "repo"
fi
BLOCKS="$STATE/stop-blocks"
(( ACTIVE )) || rm -f "$BLOCKS" 2>/dev/null  # a new stop chain
(( FAILED == 0 )) && { rm -f "$BLOCKS" 2>/dev/null; exit 0; }
n="$(cat "$BLOCKS" 2>/dev/null)"; [[ "$n" =~ ^[0-9]+$ ]] || n=0
if (( ACTIVE )) && { (( RERAN == 0 || n >= MAX_BLOCKS )) || ! echo $((n + 1)) > "$BLOCKS" 2>/dev/null; }; then
  # give up (no change since the last block, too many blocks, or no state to count with): allow, visibly
  rm -f "$BLOCKS" 2>/dev/null
  why="no code change since the last block"; (( RERAN )) && why="$n blocks in a row"
  msg="agent-harness: stop gate gave up ($why); check-fast still failing in:$STILL. Not verified: run make check-fast."
  msg="${msg//\\/\\\\}"; msg="${msg//\"/\\\"}"
  printf '{"systemMessage":"%s"}\n' "$msg"
  echo "$msg" >&2
  exit 0
fi
(( ACTIVE )) || { mkdir -p "$STATE" 2>/dev/null; echo 1 > "$BLOCKS" 2>/dev/null; }
{
  echo "Stop blocked by agent-harness: a repo's check-fast failed on your changes."
  echo "Fix the failures below in the repo named (do not disable or skip checks), then finish."
  echo "$REPORT"
  [[ -n "$SKIPPED" ]] && echo "Not gated (no complete harness), changed anyway:$SKIPPED"
} >&2
exit 2
