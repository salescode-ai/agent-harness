#!/usr/bin/env bash
# scripts/harness/plan-check.sh — one reading of a plan's Ticket and of its local verification evidence (lint.sh, ws.sh, skills).
# Run from the repo (or workspace) root.
#   plan-check.sh ticket <plan>    exit 0 valid · 1 missing/placeholder/unrecognised · 2 valid but a Jira key outside
#                                  the project named in docs/agents/issue-tracker.md. Prints the problem on failure.
#                                  Valid when the Ticket line holds, anywhere: a Jira key (also inside a Markdown link,
#                                  or a comma-separated list "SHOP-12, SHOP-13" on that line), #123, an issues/browse/pull/
#                                  merge_requests URL, a .scratch/ path, or exactly "none (<reason>)". Any "<" fails.
#   plan-check.sh fresh <evidence>  exit 0 when the latest "### <date> · <commit> · <verdict>" entry in the local
#                                  evidence file (.harness/evidence/<plan file name>, never committed) is PASS, its commit
#                                  has the same code as HEAD (docs/plans and plans/ excluded) and nothing outside them is
#                                  uncommitted. An "uncommitted" entry is never fresh: commit, then run harness-verify again.
#                                  Workspace evidence ("### <date> · <repo> · <commit> · <verdict>", run from the workspace
#                                  root): each repo's latest entry is checked in <repo path from harness-workspace.json>.
set -uo pipefail
cmd="${1:-}"; plan="${2:-}"
[[ -n "$cmd" && -n "$plan" ]] || { echo "usage: plan-check.sh <ticket <plan.md>|fresh <evidence.md>>" >&2; exit 2; }

ticket_of() { # the "Ticket:" value (up to " · " or end of line)
  grep -m1 -E '(^|[^A-Za-z])Ticket\**:' "$1" | sed -E 's/.*Ticket\**:\**[[:space:]]*//; s/[[:space:]]+·.*$//; s/[[:space:]]+$//'
}
latest() { # the latest "### <date> · …" entry
  grep -E '^### [0-9]{4}-[0-9]{2}-[0-9]{2}' "$1" 2>/dev/null | tail -1
}
repo_path() { # a workspace member's path from harness-workspace.json (else its name)
  local p; p="$(python3 -c 'import json,sys
for r in json.load(open("harness-workspace.json")).get("repos", []):
    if r.get("name") == sys.argv[1]: print(r.get("path", r["name"]))' "$1" 2>/dev/null)"
  echo "${p:-$1}"
}
fresh_one() { # fresh_one <entry> <repo dir> <label>: the entry is PASS and still covers that repo's code
  local e="$1" g="$2" l="$3" c
  [[ "$e" =~ ·\ PASS[[:space:]]*$ ]] || { echo "$l: latest entry is not PASS (${e:-none}) — run harness-verify"; return 1; }
  c="$(awk -F' · ' '{print $(NF-1)}' <<<"$e" | tr -d ' ')"
  if [[ "$c" == uncommitted ]] || ! git -C "$g" rev-parse -q --verify "$c^{commit}" >/dev/null 2>&1; then
    echo "$l: the PASS entry is for '$c', not a commit — commit, then run harness-verify again"; return 1
  fi
  git -C "$g" diff --quiet "$c" HEAD -- . ':!docs/plans' ':!plans' ':!.harness' 2>/dev/null \
    || { echo "$l: code changed since the PASS entry ($c) — run harness-verify again"; return 1; }
  [[ -z "$(git -C "$g" status --porcelain -- . ':!docs/plans' ':!plans' ':!.harness' 2>/dev/null)" ]] \
    || { echo "$l: uncommitted code changes after the PASS entry — commit, then run harness-verify again"; return 1; }
}

case "$cmd" in
  ticket)
    [[ -f "$plan" ]] || { echo "$plan: no such plan" >&2; exit 2; }
    v="$(ticket_of "$plan")"
    if [[ -z "$v" || "$v" == *"<"* || "$v" =~ ^(TODO|tbd|TBD|\[verify\]|none|none\ *\(\ *\))$ ]]; then
      echo "$plan has no ticket — set 'Ticket: <your Jira key | #<issue> | .scratch/... | none (<reason>)>' under the title"; exit 1
    fi
    key="$(grep -oE '(^|[^A-Za-z0-9])[A-Z][A-Z0-9]+-[0-9]+([^0-9]|$)' <<<"$v" | head -1 | grep -oE '[A-Z][A-Z0-9]+-[0-9]+')"
    if [[ "$key" =~ ^(KEY-[0-9]+|ABC-123|XXX-0+)$ ]]; then  # template / hint examples, not tickets
      echo "$plan Ticket $key is an example key — set the real ticket"; exit 1
    fi
    if [[ -n "$key" ]]; then
      jira="$(grep -oE 'Jira project `[A-Z][A-Z0-9]+`' docs/agents/issue-tracker.md 2>/dev/null | head -1 | tr -d '`' | awk '{print $3}')"
      [[ -n "$jira" && "${key%-*}" != "$jira" ]] && { echo "$plan Ticket $key is not in Jira project $jira (docs/agents/issue-tracker.md)"; exit 2; }
      exit 0
    fi
    # #123, an issue/browse/merge-request URL, a .scratch/ path, or none (<reason>)
    grep -qE '(^|[^&A-Za-z0-9])#[0-9]+|https?://[^ ]+/(issues|browse|pull|merge_requests)/[^ ]+|(^|[ (])\.scratch/|^none \(.+\)$' <<<"$v" && exit 0
    echo "$plan Ticket '$v' names no Jira key (<PROJECT>-<number>), #123, issue URL, .scratch/ path or 'none (<reason>)'"; exit 1 ;;
  fresh)
    [[ -f "$plan" ]] || { echo "no verification evidence on this machine ($plan) — run harness-verify"; exit 1; }
    e="$(latest "$plan")"
    [[ -n "$e" ]] || { echo "$plan: no entry yet — run harness-verify"; exit 1; }
    if [[ "$(awk -F' · ' '{print NF}' <<<"$e")" -lt 4 ]]; then fresh_one "$e" . "$plan"; exit; fi
    # workspace: "### <date> · <repo> · <commit> · <verdict>" — every repo's latest entry must be PASS and fresh
    rc=0
    for r in $(grep -E '^### [0-9]{4}-[0-9]{2}-[0-9]{2} · ' "$plan" | awk -F' · ' 'NF>=4{print $2}' | sort -u); do
      e="$(grep -E '^### [0-9]{4}-[0-9]{2}-[0-9]{2} · ' "$plan" | awk -F' · ' -v r="$r" '$2==r' | tail -1)"
      fresh_one "$e" "$(repo_path "$r")" "$plan ($r)" || rc=1
    done
    exit $rc ;;
  *) echo "usage: plan-check.sh <ticket <plan.md>|fresh <evidence.md>>" >&2; exit 2 ;;
esac
