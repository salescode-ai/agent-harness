#!/usr/bin/env bash
# PreToolUse(Bash): deny destructive or check-bypassing commands; ask before pushing to the default branch.
# Logic lives in guard_bash.py (quote-aware parsing). Without python3 it fails closed for what it exists for: a command
# that may skip hooks, change git history, delete, or write a file the harness protects asks; the rest is allowed.
command -v python3 >/dev/null 2>&1 && exec python3 "$(dirname "$0")/guard_bash.py"
[ "${HARNESS_GUARD:-1}" = 0 ] && exit 0
IFS= read -r -d '' in  # the hook JSON; builtins only from here: a machine without python3 may lack more
# shortcut: a word match on the raw hook JSON (nothing parses it without python3), so quoted text can also ask
risky='--no-verify|SKIP_HOOKS|HUSKY|SKIP=|core\.hooksPath|git[^"]*[[:space:]](commit|push|merge|rebase|reset|clean|checkout|restore|cherry-pick|branch|stash|config|worktree|filter-branch|update-ref)([^a-z-]|$)|(^|[^a-z])rm[[:space:]]|CLAUDE\.md|INVARIANTS\.md|\.env|init-state\.json|harness-workspace\.json'
sql='(drop|truncate)[[:space:]]+(table|database|schema)'
r=""; [[ $in =~ $risky ]] && r=1
shopt -s nocasematch; [[ $in =~ $sql ]] && r=1; shopt -u nocasematch
sid=""; re='"session_id"[[:space:]]*:[[:space:]]*"([^"]*)"'; [[ $in =~ $re ]] && sid="${BASH_REMATCH[1]}"
mark="${TMPDIR:-/tmp}/agent-harness-no-python3-${sid:-unknown}"
msg=""
if [ ! -e "$mark" ]; then
  : > "$mark" 2>/dev/null
  msg=',"systemMessage":"agent-harness: python3 not found, so the Bash guard cannot parse commands: git commits, pushes and history changes, rm, hook skipping and writes to harness files ask instead of being checked. Install python3 to restore the full guard."'
fi
if [ -n "$r" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"agent-harness: python3 is missing, so this command could not be checked. Review it yourself."}%s}\n' "$msg"
elif [ -n "$msg" ]; then
  printf '{%s}\n' "${msg#,}"
fi
exit 0
