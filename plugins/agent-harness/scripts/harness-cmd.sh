#!/usr/bin/env bash
# harness-cmd.sh <repo-dir> <target> [T] -- resolve a harness target to a shell command.
# Prints the command; callers run it with `eval` (or `bash -c`) from the repo dir.
# Standalone: also installed in repos as scripts/harness/cmd.sh.
#   .agents/harness.json commands[target] -> printed verbatim, {T} replaced by T (or removed)
#   otherwise -> make -s -C <dir> <target> [T=<T>], only if `make -n <target>` succeeds
# Exit: 3 unresolvable (prints nothing); 4 make not installed.
dir="${1:-}"; target="${2:-}"; t="${3:-}"
[ -n "$dir" ] && [ -n "$target" ] || { echo "usage: harness-cmd.sh <repo-dir> <target> [T]" >&2; exit 2; }

q() { case "$1" in ''|*[!A-Za-z0-9_./=:@%+,-]*) printf "'%s'" "$(printf %s "$1" | sed "s/'/'\\\\''/g")";; *) printf %s "$1";; esac; }

f="$dir/.agents/harness.json"
if [ -f "$f" ]; then
  rc=0
  out="$(python3 - "$f" "$target" "$t" 2>/dev/null <<'PY'
import json,sys
try:
    c=json.load(open(sys.argv[1]))["commands"].get(sys.argv[2])
except Exception: sys.exit(2)
if not isinstance(c,str) or not c.strip(): sys.exit(1)
print(c.replace("{T}",sys.argv[3]).rstrip() if sys.argv[3] else " ".join(c.replace("{T}","").split()))
PY
)" || rc=$?
  case $rc in
    0) printf '%s\n' "$out"; exit 0;;
    2|127) echo "harness-cmd: .agents/harness.json unreadable, using make" >&2;;
  esac
fi

command -v make >/dev/null 2>&1 || { echo "harness-cmd: make not found" >&2; exit 4; }
make -C "$dir" -n "$target" >/dev/null 2>&1 || exit 3
printf 'make -s -C %s %s' "$(q "$dir")" "$(q "$target")"
[ -n "$t" ] && printf ' T=%s' "$(q "$t")"
echo
