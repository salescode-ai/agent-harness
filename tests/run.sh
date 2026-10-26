#!/usr/bin/env bash
# Usage: tests/run.sh [pattern]  -- runs t_* functions from tests/test_*<pattern>*.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"
pass=0; failed=0; skipped=0
for f in "${TESTS_DIR:-$HERE}"/test_*"${1:-}"*.sh; do
  [ -f "$f" ] || continue
  . "$f"
  for fn in $(compgen -A function | grep '^t_'); do

    ( set -e; "$fn" ); rc=$?  # not on the left of ||, which would disable set -e
    name="$(basename "$f" .sh)::${fn#t_}"
    case $rc in
      0) echo "ok   $name"; pass=$((pass+1));;
      77) skipped=$((skipped+1));;
      *) echo "FAIL $name"; failed=$((failed+1));;
    esac
    unset -f "$fn"
  done
done
echo "$pass ok, $failed failed, $skipped skipped"
[ "$failed" = 0 ]
