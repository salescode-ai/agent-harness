#!/usr/bin/env bash
# PreToolUse(Bash): deny destructive or check-bypassing commands; ask before pushing to the default branch.
# Logic lives in guard_bash.py (quote-aware parsing). Fails open if python3 is unavailable.
command -v python3 >/dev/null 2>&1 || exit 0
exec python3 "$(dirname "$0")/guard_bash.py"
