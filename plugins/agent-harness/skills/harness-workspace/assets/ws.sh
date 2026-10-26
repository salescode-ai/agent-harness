#!/usr/bin/env bash
# ws.sh — multi-repo workspace helper for the agent harness.
# The workspace folder is not a git repo; each member repo keeps its own harness (AGENTS.md, Makefile, gate).
# Usage: bash ws.sh <status|changed|check|check-fast|test|branch|bootstrap|lint> [args]
set -uo pipefail
WS="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$WS/harness-workspace.json"
[[ -f "$MANIFEST" ]] || { echo "ws: no harness-workspace.json in $WS" >&2; exit 1; }
command -v python3 >/dev/null || { echo "ws: python3 is required" >&2; exit 1; }

members() { python3 - "$MANIFEST" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))
for r in m.get("repos",[]):
    print("\t".join([r["name"], r.get("path", r["name"]), r.get("base","main"), r.get("remote","")]))
PY
}
merge_order() { python3 -c "import json,sys;print(' '.join(json.load(open(sys.argv[1])).get('mergeOrder',[])))" "$MANIFEST"; }
is_repo() { git -C "$WS/$1" rev-parse --show-toplevel >/dev/null 2>&1 && [[ "$(git -C "$WS/$1" rev-parse --show-toplevel)" == "$(cd "$WS/$1" && pwd -P)" ]]; }
changed() { # changed <path> <base>: true if uncommitted changes or commits ahead of origin/<base>
  local p="$1" b="$2" ahead=0
  [[ -n "$(git -C "$WS/$p" status --porcelain 2>/dev/null)" ]] && return 0
  git -C "$WS/$p" rev-parse --verify -q "origin/$b" >/dev/null && ahead="$(git -C "$WS/$p" rev-list --count "origin/$b"..HEAD 2>/dev/null || echo 0)"
  [[ "$ahead" != "0" ]]
}
path_of() { members | awk -F'\t' -v n="$1" '$1==n {print $2}'; }

cmd="${1:-status}"; shift || true
case "$cmd" in
  status)
    printf '%-18s %-34s %-6s %-6s %s\n' REPO BRANCH DIRTY AHEAD HARNESS
    while IFS=$'\t' read -r name path base _; do
      if ! is_repo "$path"; then printf '%-18s %s\n' "$name" "not checked out ($path) — run: make bootstrap"; continue; fi
      br="$(git -C "$WS/$path" branch --show-current)"; dirty="$(git -C "$WS/$path" status --porcelain | wc -l | tr -d ' ')"
      ahead="-"; git -C "$WS/$path" rev-parse --verify -q "origin/$base" >/dev/null && ahead="$(git -C "$WS/$path" rev-list --count "origin/$base"..HEAD)"
      h="yes"; [[ -f "$WS/$path/AGENTS.md" ]] || h="MISSING"; make -C "$WS/$path" -n check >/dev/null 2>&1 || h="$h (no make check)"
      printf '%-18s %-34s %-6s %-6s %s\n' "$name" "${br:-detached}" "$dirty" "$ahead" "$h"
    done <<<"$(members)" ;;
  changed)
    while IFS=$'\t' read -r name path base _; do if is_repo "$path" && changed "$path" "$base"; then echo "$name"; fi; done <<<"$(members)"
    exit 0 ;;
  check|check-fast)
    fail=0; ran=0
    while IFS=$'\t' read -r name path base _; do
      is_repo "$path" && changed "$path" "$base" || continue
      ran=$((ran+1))
      if ! make -C "$WS/$path" -n "$cmd" >/dev/null 2>&1; then echo "FAIL  $name: no '$cmd' target — the repo has no harness"; fail=1; continue; fi
      out="$(make -s -C "$WS/$path" "$cmd" 2>&1)" && { echo "ok    $name: $cmd"; continue; }
      fail=1; echo "FAIL  $name: make $cmd"; tail -30 <<<"$out" | sed 's/^/      /'
    done <<<"$(members)"
    (( ran == 0 )) && echo "$cmd: no repo has changes"
    exit $fail ;;
  test)
    repo="${1:?usage: ws.sh test <repo> [T]}"; p="$(path_of "$repo")"; [[ -n "$p" ]] || { echo "ws: unknown repo $repo" >&2; exit 1; }
    if [[ -n "${2:-}" ]]; then make -C "$WS/$p" test T="$2"; else make -C "$WS/$p" test; fi ;;
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
      git clone -q --branch "$base" "$remote" "$WS/$path" && echo "clone $name"
    done <<<"$(members)" ;;
  lint)
    fail=0
    [[ -f "$WS/AGENTS.md" ]] || { echo "FAIL  workspace AGENTS.md missing"; fail=1; }
    if [[ -f "$WS/CLAUDE.md" ]] && grep -vE '^[[:space:]]*$|^[[:space:]]*#|^[[:space:]]*@[^ ]+[[:space:]]*$' "$WS/CLAUDE.md" | grep -q .; then echo "FAIL  workspace CLAUDE.md has real content"; fail=1; fi
    while IFS=$'\t' read -r name path _ _; do
      grep -q -- "$name" "$WS/AGENTS.md" 2>/dev/null || { echo "FAIL  $name is in the manifest but not in AGENTS.md"; fail=1; }
      is_repo "$path" || { echo "warn  $name not checked out"; continue; }
      [[ -f "$WS/$path/AGENTS.md" ]] || { echo "FAIL  $name has no AGENTS.md (run harness-init in it)"; fail=1; }
      make -C "$WS/$path" -n check >/dev/null 2>&1 || { echo "FAIL  $name has no 'make check'"; fail=1; }
    done <<<"$(members)"
    for o in $(merge_order); do members | cut -f1 | grep -qx "$o" || { echo "FAIL  mergeOrder names unknown repo $o"; fail=1; }; done
    (( fail )) || echo "workspace-lint: OK"
    exit $fail ;;
  *) echo "usage: ws.sh <status|changed|check|check-fast|test <repo> [T]|branch <name> <repo...>|bootstrap|lint>" >&2; exit 2 ;;
esac
