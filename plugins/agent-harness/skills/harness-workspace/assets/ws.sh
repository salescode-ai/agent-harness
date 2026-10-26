#!/usr/bin/env bash
# ws.sh — multi-repo workspace helper for the agent harness.
# The workspace folder is not a git repo; each member repo keeps its own harness (AGENTS.md, Makefile, gate).
# Usage: bash ws.sh <status|state <name>|changed|check|check-fast|setup|claude-md|test|branch|bootstrap|lint> [args]
set -uo pipefail
WS="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$WS/harness-workspace.json"
[[ -f "$MANIFEST" ]] || { echo "ws: no harness-workspace.json in $WS" >&2; exit 1; }
command -v python3 >/dev/null || { echo "ws: python3 is required" >&2; exit 1; }

members() { python3 - "$MANIFEST" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))
for r in m.get("repos",[]):
    print("\t".join([r["name"], r.get("path", r["name"]), r.get("base",""), r.get("remote","")]))
PY
}
merge_order() { python3 -c "import json,sys;print(' '.join(json.load(open(sys.argv[1])).get('mergeOrder',[])))" "$MANIFEST"; }
is_repo() { git -C "$WS/$1" rev-parse --show-toplevel >/dev/null 2>&1 && [[ "$(git -C "$WS/$1" rev-parse --show-toplevel)" == "$(cd "$WS/$1" && pwd -P)" ]]; }
base_ref() { # base_ref <path> <manifest base>: origin/<base>; no base -> origin/HEAD, else origin/main, else origin/master
  [[ -n "$2" ]] && { echo "origin/$2"; return; }
  local b; b="$(git -C "$WS/$1" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  [[ -n "$b" ]] && { echo "$b"; return; }
  git -C "$WS/$1" rev-parse -q --verify origin/main >/dev/null 2>&1 && { echo origin/main; return; }
  echo origin/master
}
changed() { # changed <path> <base>: true if uncommitted changes or commits ahead of the base ref
  local p="$1" b ahead=0; b="$(base_ref "$1" "$2")"
  [[ -n "$(git -C "$WS/$p" status --porcelain 2>/dev/null)" ]] && return 0
  git -C "$WS/$p" rev-parse --verify -q "$b" >/dev/null && ahead="$(git -C "$WS/$p" rev-list --count "$b"..HEAD 2>/dev/null || echo 0)"
  [[ "$ahead" != "0" ]]
}
# resolve <dir> <target> [T]: print the command via the sibling resolver; falls back to a make probe when it is not installed
resolve() {
  local d="$1" t="$2"
  if [[ -f "$WS/scripts/harness/cmd.sh" ]]; then bash "$WS/scripts/harness/cmd.sh" "$d" "$t" "${3:-}"; return; fi
  make -n -C "$d" "$t" >/dev/null 2>&1 || return 3
  printf 'make -s -C %q %s%s\n' "$d" "$t" "${3:+ T=$(printf %q "$3")}"
}
state() { # state <path>: present | partial | none (same definition as member_state in scripts/_lib.sh)
  local d="$WS/$1" n=0
  [[ -f "$d/AGENTS.md" ]] && n=$((n+1)); [[ -f "$d/INVARIANTS.md" ]] && n=$((n+1))
  resolve "$d" check >/dev/null 2>&1 && n=$((n+1))
  case $n in 3) echo present;; 0) echo none;; *) echo partial;; esac
}
skip_warn() { echo "warn  $1: harness $2 — gate skipped (create it only if asked: harness-init in $WS/$3)"; }
run_target() { # run_target <path> <target> [T]: run the resolved command inside the member; returns its status
  local c rc=0; c="$(resolve "$WS/$1" "$2" "${3:-}")" || return 3
  (cd "$WS/$1" && eval "$c") || rc=$?
  (( rc == 3 )) && rc=1  # only the resolver's exit 3 means "not wired"; a command exiting 3 is a failure
  return $rc
}
fail_summary() { # failure-marker lines (up to 20), then the last 10 lines; without markers the last 30
  local m; m="$(grep -E 'FAIL|ERROR|Error:|expected|AssertionError|Tests run:.*Failures|✗|error TS|SyntaxError' <<<"$1" | head -20)"
  if [[ -n "$m" ]]; then printf '%s\n...\n' "$m"; tail -10 <<<"$1"; else tail -30 <<<"$1"; fi
}
path_of() { members | awk -F'\t' -v n="$1" '$1==n {print $2}'; }

cmd="${1:-status}"; shift || true
case "$cmd" in
  status)
    printf '%-18s %-34s %-6s %-6s %s\n' REPO BRANCH DIRTY AHEAD HARNESS
    while IFS=$'\t' read -r name path base _; do
      if ! is_repo "$path"; then printf '%-18s %s\n' "$name" "not checked out ($path) — run: make bootstrap"; continue; fi
      br="$(git -C "$WS/$path" branch --show-current)"; dirty="$(git -C "$WS/$path" status --porcelain | wc -l | tr -d ' ')"
      b="$(base_ref "$path" "$base")"; ahead="-"; git -C "$WS/$path" rev-parse --verify -q "$b" >/dev/null && ahead="$(git -C "$WS/$path" rev-list --count "$b"..HEAD)"
      h="$(state "$path")"
      printf '%-18s %-34s %-6s %-6s %s\n' "$name" "${br:-detached}" "$dirty" "$ahead" "$h"
    done <<<"$(members)" ;;
  state)
    p="$(path_of "${1:?usage: ws.sh state <name>}")"; [[ -n "$p" ]] || { echo "ws: unknown repo $1" >&2; exit 1; }
    state "$p" ;;
  changed)
    while IFS=$'\t' read -r name path base _; do if is_repo "$path" && changed "$path" "$base"; then echo "$name"; fi; done <<<"$(members)"
    exit 0 ;;
  check|check-fast)
    fail=0; ran=0
    while IFS=$'\t' read -r name path base _; do
      if ! is_repo "$path"; then echo "warn  $name: not checked out ($path) — skipped (run: make bootstrap)"; continue; fi
      changed "$path" "$base" || continue
      ran=$((ran+1))
      st="$(state "$path")"
      if [[ "$st" != present ]]; then skip_warn "$name" "$st" "$path"; continue; fi
      out="$(run_target "$path" "$cmd" 2>&1)"; rc=$?
      (( rc == 0 )) && { echo "ok    $name: $cmd"; continue; }
      (( rc == 3 )) && { echo "warn  $name: no '$cmd' command — skipped"; continue; }
      fail=1; echo "FAIL  $name: $cmd"; fail_summary "$out" | sed 's/^/      /'
    done <<<"$(members)"
    (( ran == 0 )) && echo "$cmd: no repo has changes"
    exit $fail ;;
  setup)
    fail=0; order="$(merge_order)"
    for n in $order $(members | cut -f1 | grep -vxF -f <(tr ' ' '\n' <<<"$order") || true); do
      path="$(path_of "$n")"; [[ -n "$path" ]] || continue
      if ! is_repo "$path"; then echo "warn  $n: not checked out ($path) — setup skipped (run: make bootstrap)"; continue; fi
      st="$(state "$path")"
      if [[ "$st" != present ]]; then skip_warn "$n" "$st" "$path"; continue; fi
      out="$(run_target "$path" setup 2>&1)"; rc=$?
      if (( rc == 0 )); then echo "ok    $n: setup"
      elif (( rc == 3 )); then echo "warn  $n: no 'setup' command — skipped"
      else fail=1; echo "FAIL  $n: setup"; fail_summary "$out" | sed 's/^/      /'; fi
    done
    exit $fail ;;
  claude-md)
    imp="@AGENTS.md"$'\n'"@INVARIANTS.md"; files=("$WS/AGENTS.md" "$WS/INVARIANTS.md"); mimp=""; links=""
    while IFS=$'\t' read -r name path _ _; do
      is_repo "$path" && [[ "$(state "$path")" == present ]] || continue
      mimp="$mimp"$'\n'"@$path/INVARIANTS.md"; files+=("$WS/$path/INVARIANTS.md")
      grep -qF "($path/INVARIANTS.md)" "$WS/AGENTS.md" 2>/dev/null || links="$links- [$name invariants]($path/INVARIANTS.md)"$'\n'
    done <<<"$(members)"
    tok=$(( $(cat "${files[@]}" 2>/dev/null | wc -c) / 4 ))
    if (( tok > 5000 )); then
      mimp=""
      # over budget: route through AGENTS.md instead of importing (append only the missing links)
      # shortcut: links go to the end of AGENTS.md, which is under the heading only while it stays the last section
      if [[ -n "$links" ]]; then
        grep -q '^## Member invariants' "$WS/AGENTS.md" 2>/dev/null || printf '\n## Member invariants\n\n' >> "$WS/AGENTS.md"
        printf '%s' "$links" >> "$WS/AGENTS.md"
      fi
      echo "warn  member invariants exceed budget — linked from AGENTS.md (## Member invariants) instead"
    fi
    printf '# Claude Code entry point for this workspace — instructions live in AGENTS.md\n\n%s%s\n' "$imp" "$mimp" > "$WS/CLAUDE.md"
    echo "claude-md: written" ;;
  test)
    repo="${1:?usage: ws.sh test <repo> [T]}"; p="$(path_of "$repo")"; [[ -n "$p" ]] || { echo "ws: unknown repo $repo" >&2; exit 1; }
    run_target "$p" test "${2:-}" || { echo "ws: no 'test' command for $repo" >&2; exit 1; } ;;
  branch)
    name="${1:?usage: ws.sh branch <branch-name> <repo...>}"; shift
    (( $# )) || { echo "ws: name the repos that need this branch (only repos the feature touches)" >&2; exit 1; }
    for repo in "$@"; do
      p="$(path_of "$repo")"; [[ -n "$p" ]] || { echo "ws: unknown repo $repo" >&2; exit 1; }
      if git -C "$WS/$p" show-ref --verify -q "refs/heads/$name"; then git -C "$WS/$p" switch -q "$name" && echo "$repo: switched to $name"
      else git -C "$WS/$p" switch -q -c "$name" && echo "$repo: created $name"; fi
    done ;;
  bootstrap)
    while IFS=$'\t' read -r name path base remote; do
      if is_repo "$path"; then echo "ok    $name: present"; continue; fi
      [[ -n "$remote" ]] || { echo "skip  $name: no remote in manifest"; continue; }
      git clone -q ${base:+--branch "$base"} "$remote" "$WS/$path" && echo "clone $name"
    done <<<"$(members)" ;;
  lint)
    fail=0
    [[ -f "$WS/AGENTS.md" ]] || { echo "FAIL  workspace AGENTS.md missing"; fail=1; }
    if [[ -f "$WS/CLAUDE.md" ]] && grep -vE '^[[:space:]]*$|^[[:space:]]*#|^[[:space:]]*@[^ ]+[[:space:]]*$' "$WS/CLAUDE.md" | grep . >/dev/null; then echo "FAIL  workspace CLAUDE.md has real content"; fail=1; fi
    while IFS=$'\t' read -r name path _ _; do
      grep -q -- "$name" "$WS/AGENTS.md" 2>/dev/null || { echo "FAIL  $name is in the manifest but not in AGENTS.md"; fail=1; }
      is_repo "$path" || { echo "warn  $name not checked out"; continue; }
      st="$(state "$path")"; [[ "$st" == present ]] || skip_warn "$name" "$st" "$path"
    done <<<"$(members)"
    for o in $(merge_order); do members | cut -f1 | grep -x "$o" >/dev/null || { echo "FAIL  mergeOrder names unknown repo $o"; fail=1; }; done
    for f in "$WS"/plans/active/*.md; do  # cross-repo plans carry a ticket (the same reading as a repo's harness-lint)
      [[ -f "$f" ]] || continue
      [[ -f "$WS/scripts/harness/plan-check.sh" ]] || { echo "warn  scripts/harness/plan-check.sh missing — plan tickets not checked; run /agent-harness:harness-upgrade"; break; }
      msg="$(cd "$WS" && bash scripts/harness/plan-check.sh ticket "plans/active/$(basename "$f")" 2>&1)"; rc=$?
      (( rc == 1 )) && { echo "FAIL  $msg (manifest issueKey)"; fail=1; }
      (( rc == 2 )) && echo "warn  $msg"
    done
    (( fail )) || echo "workspace-lint: OK"
    exit $fail ;;
  *) echo "usage: ws.sh <status|state <name>|changed|check|check-fast|setup|claude-md|test <repo> [T]|branch <name> <repo...>|bootstrap|lint>" >&2; exit 2 ;;
esac
