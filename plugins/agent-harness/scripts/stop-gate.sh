#!/usr/bin/env bash
# Stop: if this session changed code (vs the code_fp SessionStart recorded; without one, any uncommitted code or
# commits ahead of the base) and the repo is ahead of its base or dirty, run the repo's check-fast and block the stop
# on failure. The base is the repo's own (`make harness-base`, cached per HEAD), else HARNESS_BASE, else origin/HEAD.
# In a workspace, does this for every member repo that changed, using that repo's own gate. Success is silent; a
# check-fast that could not run (Docker down or missing, a setup error) warns instead of blocking: a repo's gate can
# print a line starting with "setup error:" (e.g. "setup error: no base branch") to be treated so. HARNESS_STOP_GATE=0 disables it.
# --subagent (SubagentStop): gates only a subagent working in a linked git worktree (an isolated implementer);
# reviewers and explorers in the main checkout are never blocked by the main session's unfinished work.
source "$(dirname "$0")/_lib.sh"
[[ "${HARNESS_STOP_GATE:-1}" == "0" ]] && exit 0
SUB=0
if [[ "${1:-}" == "--subagent" ]]; then
  SUB=1
  t="$(json_get "d.get('agent_transcript_path','')")"; c=""
  [[ -f "$t" ]] && c="$(grep -oE '"cwd":"[^"]*"' "$t" | tail -1 | cut -d'"' -f4)"
  [[ -n "$c" && -d "$c" ]] && HOOK_CWD="$c"
  gd="$(cd "$HOOK_CWD" 2>/dev/null && cd "$(git rev-parse --git-dir 2>/dev/null)" 2>/dev/null && pwd -P)"
  cd_="$(cd "$HOOK_CWD" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)"
  [[ -n "$gd" && "$gd" != "$cd_" ]] || exit 0
fi
# Loop guard: after a block (stop_hook_active, read with grep so a missing python3 can't loop), re-check only
# repos whose code changed since that block, and give up after MAX_BLOCKS consecutive blocks.
ACTIVE=0; grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true' <<<"$HOOK_INPUT" && ACTIVE=1
MAX_BLOCKS=3

STATE=""; LC_SUFFIX=""; FAILED=0; REPORT=""; SKIPPED=""; RERAN=0; STILL=""; ENVFAIL=""
# only what Docker, a shell or Testcontainers print when Docker is unusable, or a line a repo starts with "setup error:";
# free text ("requires docker" in a skip reason, a test name) would turn a real failure into a warning
ENV_RE='docker is not running|cannot connect to the docker daemon|is the docker daemon running|could not find a valid docker environment|docker: (command )?not found|command not found: docker|^[[:space:]]*setup error:'
repo_base() { # repo_base <dir>: the repo's HARNESS_BASE (harness-base target), cached per HEAD and branch in .harness/
  local dir="$1" cache="$1/.harness/base-cache" key b="" cmd
  key="$(git -C "$dir" rev-parse HEAD 2>/dev/null) $(git -C "$dir" branch --show-current 2>/dev/null)"
  [[ -f "$cache" ]] && b="$(awk -F'\t' -v k="$key" '$1 == k {print $2}' "$cache" 2>/dev/null)"
  if [[ -z "$b" ]]; then
    # cached only when the repo's harness-base answered: a fallback writes nothing into the repo
    b="$(harness_cmd "$dir" --base)" && mkdir -p "$dir/.harness" 2>/dev/null && printf '%s\t%s\n' "$key" "$b" > "$cache" 2>/dev/null
  fi
  echo "$b"
}
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
gate_repo() { # gate_repo <repo dir> <base, empty: repo_base> <label>
  local dir="$1" base="$2" label="$3" cmd fp out rc start
  [[ -f "$dir/AGENTS.md" ]] || return 0
  [[ -n "$base" ]] || base="$(repo_base "$dir")"
  # half-built harness (harness-init has not wired the gate) or no check-fast: not gated, named if another repo blocks
  init_pending "$dir" && { changed_since "$dir" "$base" && SKIPPED+=" $label (gate not wired)"; return 0; }
  cmd="$(harness_cmd "$dir" check-fast 2>/dev/null)" || { changed_since "$dir" "$base" && SKIPPED+=" $label (check-fast not resolvable)"; return 0; }
  changed_since "$dir" "$base" || return 0
  fp="$(code_fp "$dir")"
  # a session that only read code (or started on a dirty tree and left it alone) is not gated
  start="$(session_file "$dir")"; [[ -n "$start" && -f "$start" && "$(cat "$start")" == "$fp" ]] && return 0
  local key="$STATE/last-green-${label//[^A-Za-z0-9_-]/_}"
  [[ -f "$key" && "$(cat "$key")" == "$fp" ]] && return 0
  local failkey="$STATE/last-fail-${label//[^A-Za-z0-9_-]/_}"
  if (( ACTIVE )) && [[ -f "$failkey" && "$(cat "$failkey")" == "$fp" ]]; then  # unchanged since the block
    FAILED=1; STILL+=" $label"; REPORT+="---- $label: check-fast still failing (no change since the last block)"$'\n'; return 0
  fi
  out="$(cd "$dir" && eval "$cmd" 2>&1)"; rc=$?
  mkdir -p "$STATE" 2>/dev/null  # only now: repos without a harness never get a .harness/
  if (( rc == 0 )); then echo "$fp" > "$key"; echo "$fp pass $(date +%Y-%m-%d)" > "$STATE/last-check$LC_SUFFIX"; rm -f "$failkey"; return 0; fi
  grep -qiE "$ENV_RE" <<<"$out" && { ENVFAIL+=" $label ($(grep -iE "$ENV_RE" <<<"$out" | head -1 | cut -c1-120))"; return 0; }
  FAILED=1; RERAN=1; STILL+=" $label"
  echo "$fp" > "$failkey" 2>/dev/null
  REPORT+="---- $label: check-fast failed (failure lines, then the last lines)"$'\n'"$(fail_summary "$out")"$'\n'
}

ws="$(workspace_root)"
if (( ! SUB )) && [[ -n "$ws" && -z "$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null)" ]]; then
  STATE="$ws/.harness"
  while IFS=$'\t' read -r name path base; do
    [[ -n "$name" && -d "$ws/$path" ]] || continue
    b="${base:+origin/$base}"  # the manifest's base, else the member's own (repo_base)
    st="$(member_state "$ws/$path")"
    if [[ "$st" != present ]]; then changed_since "$ws/$path" "$b" && SKIPPED+=" $name ($st harness)"; continue; fi
    LC_SUFFIX="-${name//[^A-Za-z0-9_-]/_}"
    gate_repo "$ws/$path" "$b" "$name"
  done <<<"$(workspace_members "$ws")"
else
  root="$(repo_root)"; [[ -n "$root" ]] || exit 0
  STATE="$root/.harness"
  gate_repo "$root" "" "repo"
fi
if (( SUB )); then  # remember a red implementer branch: the Bash guard refuses to merge it (subagents can't be held open)
  red="$(cd "$HOOK_CWD" && cd "$(git rev-parse --git-common-dir)" && pwd -P)/harness-red"
  br="$(git -C "$HOOK_CWD" branch --show-current 2>/dev/null)"
  if [[ -n "$br" ]]; then
    if (( FAILED )); then mkdir -p "$red" && printf '%s\t%s\t%s\n' "$br" "$root" "$(date +%Y-%m-%d)" > "$red/${br//[^A-Za-z0-9_.-]/_}"
    else rm -f "$red/${br//[^A-Za-z0-9_.-]/_}"; fi
  fi
fi
BLOCKS="$STATE/stop-blocks"
(( ACTIVE )) || rm -f "$BLOCKS" 2>/dev/null  # a new stop chain
if [[ -n "$ENVFAIL" ]]; then  # environment, not code: say so, never block on it
  msg="agent-harness: check-fast could not run (environment, not your change) in:$ENVFAIL. Not verified: start it, then make check-fast."
  msg="${msg//\\/\\\\}"; msg="${msg//\"/\\\"}"; msg="$(tr -d '\000-\037' <<<"$msg")"
  (( FAILED )) && REPORT+="$msg"$'\n' || printf '{"systemMessage":"%s"}\n' "$msg"
fi
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
  if (( SUB )); then
    echo "Subagent stop blocked by agent-harness: check-fast failed in this worktree ($HOOK_CWD)."
    echo "Fix the failures below before reporting done (do not disable or skip checks). Until it passes here, merging this branch is refused."
    echo "If dependencies or services are missing in this new worktree, run \`$(harness_cmd "$HOOK_CWD" setup 2>/dev/null || echo make setup)\` first."
  else
    echo "Stop blocked by agent-harness: a repo's check-fast failed on your changes."
    echo "Fix the failures below in the repo named (do not disable or skip checks), then finish."
  fi
  echo "$REPORT"
  [[ -n "$SKIPPED" ]] && echo "Not gated (no complete harness or gate not wired), changed anyway:$SKIPPED"
} >&2
exit 2
