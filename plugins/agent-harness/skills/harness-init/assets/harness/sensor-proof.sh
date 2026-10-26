#!/usr/bin/env bash
# Usage: sensor-proof.sh <name> | --recheck   (run from the repo root)
# Proof: clean passes -> planted fixture fails with output -> clean passes. --recheck runs steps 2+3 for all.
REG=scripts/harness/sensors/registry.json
command -v python3 >/dev/null 2>&1 || { echo "sensor-proof: python3 is required to read $REG" >&2; exit 2; }
[ -f "$REG" ] || { echo "sensor-proof: $REG not found (run from the repo root)" >&2; exit 2; }

# get <name> <field>: prints the field ('' if absent); exit 3 if the sensor is unknown
get() { python3 -c '
import json,sys
for s in json.load(open(sys.argv[1])).get("sensors",[]):
    if s.get("name")==sys.argv[2]:
        print(s.get(sys.argv[3],"")); sys.exit(0)
sys.exit(3)' "$REG" "$1" "$2"; }
names() { python3 -c '
import json,sys
for s in json.load(open(sys.argv[1])).get("sensors",[]): print(s["name"])' "$REG"; }

OUT=""
# exec_sensor <name> clean|fixture: sets OUT, returns the sensor's exit code
exec_sensor() {
  local name="$1" which="$2" run mode target cmd rc=0  # dest/f/d/list/made stay global: the EXIT trap needs them
  run="$(get "$name" run)"; mode="$(get "$name" mode)"; target="$(get "$name" "$which")"
  if [ "$which" = fixture ]; then
    for p in "$target" "$(get "$name" dest)"; do
      [ -z "$p" ] && continue
      case "/$p/" in /\/*|*/../*) OUT="registry path '$p' must be relative with no '..'"; return 99;; esac
    done
  fi
  if [ "$mode" = copy ]; then
    if [ "$which" = clean ]; then OUT="$(bash -c "$run" 2>&1)" || rc=$?; return $rc; fi
    dest="$(get "$name" dest)"; dest="${dest:-.}"; target="${target%/}"
    list="$(mktemp)"; made="$(mktemp)"
    ( cd "$target" && find . -type f | sed 's|^\./||' ) > "$list"
    while IFS= read -r f; do
      [ -e "$dest/$f" ] && { rm -f "$list" "$made"; OUT="refusing to overwrite existing $dest/$f"; return 99; }
    done < "$list"
    # always remove exactly what we copied (files, then dirs we created); runs in the step subshell
    trap 'while IFS= read -r f; do [ -n "$f" ] && rm -f "$dest/$f"; done < "$list"; sort -r "$made" | while IFS= read -r d; do rmdir "$d" 2>/dev/null; done; rm -f "$list" "$made"' EXIT
    while IFS= read -r f; do
      d=""
      for seg in $(echo "$dest/$(dirname "$f")" | tr '/' ' '); do  # record every missing ancestor (shortcut: segments with spaces unsupported)
        [ "$seg" = . ] && continue
        d="${d:+$d/}$seg"; [ -d "$d" ] || { mkdir "$d"; echo "$d" >> "$made"; }
      done
      cp "$target/$f" "$dest/$f"
    done < "$list"
    OUT="$(bash -c "$run" 2>&1)" || rc=$?
    return $rc
  fi
  cmd="${run//\{paths\}/$(printf '%q' "$target")}"
  OUT="$(bash -c "$cmd" 2>&1)" || rc=$?
  return $rc
}

# Each sensor runs in a subshell so copy-mode's EXIT trap cleans up on exit, INT and TERM.
step() { # step <name> <which>; result goes to $TMPRC / $TMPOUT
  ( trap 'exit 130' INT TERM; exec_sensor "$1" "$2"; echo "$?" > "$TMPRC"; printf '%s' "$OUT" > "$TMPOUT" )
}

prove() { # prove <name> <with-step1>
  local name="$1" s1="$2" rc
  get "$name" run >/dev/null 2>&1 || { echo "proof $name: FAIL - not in $REG" >&2; return 2; }  # registry parsed OK at startup
  if [ "$s1" = 1 ]; then
    step "$name" clean; rc="$(cat "$TMPRC")"
    [ "$rc" = 0 ] || { echo "proof $name: FAIL step 1 (clean code must pass, got exit $rc)"; cat "$TMPOUT"; return 1; }
  fi
  step "$name" fixture; rc="$(cat "$TMPRC")"
  [ "$rc" = 99 ] && { echo "proof $name: FAIL step 2 ($(cat "$TMPOUT"))"; return 1; }
  [ "$rc" != 0 ] || { echo "proof $name: FAIL step 2 (planted fixture passed; the sensor does not fire)"; return 1; }
  [ -s "$TMPOUT" ] || { echo "proof $name: FAIL step 2 (sensor failed with no message; it must say what is wrong)"; return 1; }
  step "$name" clean; rc="$(cat "$TMPRC")"
  [ "$rc" = 0 ] || { echo "proof $name: FAIL step 3 (clean must pass again, got exit $rc)"; cat "$TMPOUT"; return 1; }
  echo "proof $name: OK"
}

NAMES="$(names)" || { echo "sensor-proof: cannot parse $REG" >&2; exit 2; }
TMPRC="$(mktemp)"; TMPOUT="$(mktemp)"; trap 'rm -f "$TMPRC" "$TMPOUT"' EXIT
case "${1:-}" in
  "") echo "usage: sensor-proof.sh <name> | --recheck" >&2; exit 2;;
  --recheck)
    fail=0
    for n in $NAMES; do prove "$n" 0 || fail=1; done
    exit $fail;;
  *) prove "$1" 1;;
esac
