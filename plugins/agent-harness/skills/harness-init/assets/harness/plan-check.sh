#!/usr/bin/env bash
# scripts/harness/plan-check.sh — one reading of a plan's Ticket and of its local verification evidence (lint.sh, ws.sh, skills).
# Run from the repo (or workspace) root.
#   plan-check.sh ticket <plan>    exit 0 valid · 1 missing/placeholder/unrecognised · 2 valid but a Jira key outside
#                                  the project named in docs/agents/issue-tracker.md. Prints the problem on failure.
#   plan-check.sh fresh <evidence>  exit 0 when the latest "### <date> · <commit> · <verdict>" entry in the local
#                                  evidence file (.harness/evidence/<plan file name>, never committed) is PASS, its commit
#                                  has the same code as HEAD (docs/plans and plans/ excluded) and nothing outside them is
#                                  uncommitted. An "uncommitted" entry is never fresh: commit, then run harness-verify again.
set -uo pipefail
cmd="${1:-}"; plan="${2:-}"
[[ -n "$cmd" && -n "$plan" ]] || { echo "usage: plan-check.sh <ticket <plan.md>|fresh <evidence.md>>" >&2; exit 2; }

ticket_of() { # the "Ticket:" value (up to " · " or end of line)
  grep -m1 -E '(^|[^A-Za-z])Ticket\**:' "$1" | sed -E 's/.*Ticket\**:\**[[:space:]]*//; s/[[:space:]]+·.*$//; s/[[:space:]]+$//'
}
latest() { # the latest "### <date> · …" entry
  grep -E '^### [0-9]{4}-[0-9]{2}-[0-9]{2}' "$1" 2>/dev/null | tail -1
}

case "$cmd" in
  ticket)
    [[ -f "$plan" ]] || { echo "$plan: no such plan" >&2; exit 2; }
    v="$(ticket_of "$plan")"
    if [[ -z "$v" || "$v" == *"<"* || "$v" =~ ^(TODO|tbd|TBD|\[verify\]|none|none\ *\(\ *\))$ ]]; then
      echo "$plan has no ticket — set 'Ticket: <KEY-123 | #123 | .scratch/... | none (<reason>)>' under the title"; exit 1
    fi
    key="$(grep -oE '(^|[^A-Za-z0-9])[A-Z][A-Z0-9]+-[0-9]+([^0-9]|$)' <<<"$v" | head -1 | grep -oE '[A-Z][A-Z0-9]+-[0-9]+')"
    if [[ -n "$key" ]]; then
      jira="$(grep -oE 'Jira project `[A-Z][A-Z0-9]+`' docs/agents/issue-tracker.md 2>/dev/null | head -1 | tr -d '`' | awk '{print $3}')"
      [[ -n "$jira" && "${key%-*}" != "$jira" ]] && { echo "$plan Ticket $key is not in Jira project $jira (docs/agents/issue-tracker.md)"; exit 2; }
      exit 0
    fi
    # #123, an issue/browse/merge-request URL, a .scratch/ path, or none (<reason>)
    grep -qE '(^|[^&A-Za-z0-9])#[0-9]+|https?://[^ ]+/(issues|browse|pull|merge_requests)/[^ ]+|(^|[ (])\.scratch/|^none \(.+\)$' <<<"$v" && exit 0
    echo "$plan Ticket '$v' names no Jira key (ABC-123), #123, issue URL, .scratch/ path or 'none (<reason>)'"; exit 1 ;;
  fresh)
    [[ -f "$plan" ]] || { echo "no verification evidence on this machine ($plan) — run harness-verify"; exit 1; }
    e="$(latest "$plan")"
    [[ "$e" =~ ·\ PASS[[:space:]]*$ ]] || { echo "$plan: latest entry is not PASS (${e:-none}) — run harness-verify"; exit 1; }
    c="$(awk -F' · ' '{print $(NF-1)}' <<<"$e" | tr -d ' ')"
    if [[ "$c" == uncommitted ]] || ! git rev-parse -q --verify "$c^{commit}" >/dev/null 2>&1; then
      echo "$plan: the PASS entry is for '$c', not a commit — commit, then run harness-verify again"; exit 1
    fi
    git diff --quiet "$c" HEAD -- . ':!docs/plans' ':!plans' ':!.harness' 2>/dev/null \
      || { echo "$plan: code changed since the PASS entry ($c) — run harness-verify again"; exit 1; }
    [[ -z "$(git status --porcelain -- . ':!docs/plans' ':!plans' ':!.harness' 2>/dev/null)" ]] \
      || { echo "$plan: uncommitted code changes after the PASS entry — commit, then run harness-verify again"; exit 1; }
    exit 0 ;;
  *) echo "usage: plan-check.sh <ticket <plan.md>|fresh <evidence.md>>" >&2; exit 2 ;;
esac
