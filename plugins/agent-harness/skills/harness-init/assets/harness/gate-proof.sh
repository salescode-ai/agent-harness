#!/usr/bin/env bash
# scripts/harness/gate-proof.sh — prove the gate can fail: a planted failing test must turn it red.
# Usage: bash scripts/harness/gate-proof.sh [junit5|pytest|vitest|jest]   (from the repo root; harness-init step 5
#        and harness-upgrade step 3 run it). No stack given: picked from the root build file, then from the test files.
# HARNESS_GATE_PROOF_BESIDE=<existing test file> plants the test beside that file (a test the repo's test command runs);
#        otherwise the first test file found, the root module's (src/test/java/…) before nested projects'.
# In a scratch worktree holding the current code (committed + uncommitted), one trivial test is planted next to an
# existing test file, and the repo's own targets (scripts/harness/cmd.sh: make, or .agents/harness.json) must show:
#   test T=<planted>      exits 0 while the planted test passes (control), non-zero once it fails
#   test T=<no such file> exits non-zero (a selector that matches nothing must not pass)
#   check-fast            exits 0 / non-zero the same way, with only the planted file changed
#                         (n/a when check-fast runs no tests by design: HARNESS_TEST_CHANGED and HARNESS_TEST_SECS unset)
# Records "gate_red_proven" (and "gate_red_reason" when false) in .harness/init-state.json. Last line, and exit code:
#   gate: proven red (…)    0
#   gate: NOT proven (…)    1  a target passed with a failing or missing test: the gate can stay green on failures
#   gate: inconclusive (…)  2  no supported stack or test file, a target not wired, or a control that should pass failed
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "gate: inconclusive (not a git repo)"; exit 2; }
cd "$ROOT" || exit 2
RES="$(cd "$(dirname "$0")" && pwd)/cmd.sh"; [ -f "$RES" ] || RES="${CLAUDE_PLUGIN_ROOT:-}/scripts/harness-cmd.sh"

record() { # record <proven true|false> <reason>: merge into .harness/init-state.json (gitignored local state)
  mkdir -p .harness
  python3 - "$1" "$2" <<'PY' 2>/dev/null || true
import json, sys
p = ".harness/init-state.json"
try:
    d = json.load(open(p))
    d = d if isinstance(d, dict) else {}
except (OSError, ValueError):
    d = {}
d["gate_red_proven"] = sys.argv[1] == "true"
if d["gate_red_proven"]:
    d.pop("gate_red_reason", None)
else:
    d["gate_red_reason"] = sys.argv[2]
open(p, "w").write(json.dumps(d, indent=2) + "\n")
PY
}
finish() { # finish <exit> <line>
  echo "gate: $2"
  if [ "$1" = 0 ]; then record true ""; else record false "$2"; fi
  exit "$1"
}
[ -f "$RES" ] || finish 2 "inconclusive (scripts/harness/cmd.sh not found)"

files="$(git ls-files --cached --others --exclude-standard)"
first() { grep -E "$1" <<<"$files" | grep -vE '(^|/)(node_modules|vendor|target|build|dist)/' | head -200; }
# root module first: a nested src/test/java may be a separate project the repo's test command never runs
junit5() { { first '^src/test/java/.*\.java$'; first '(^|/)src/test/java/.*\.java$'; } | while IFS= read -r f; do grep -q 'org\.junit\.jupiter' "$f" 2>/dev/null && { echo "$f"; break; }; done; }
stack="${1:-}"
if [ -z "$stack" ]; then
  for f in pom.xml build.gradle build.gradle.kts package.json pyproject.toml setup.py setup.cfg requirements.txt; do
    [ -f "$f" ] || continue
    case "$f" in
      pom.xml|build.gradle*) [ -n "$(junit5)" ] && stack=junit5 ;;
      package.json) grep -q '"vitest"' package.json && stack=vitest || { grep -q '"jest"\|react-scripts' package.json && stack=jest; } ;;
      *) stack=pytest ;;
    esac
    [ -n "$stack" ] && break
  done
fi
if [ -z "$stack" ]; then  # no root build file: whatever test files exist
  if [ -n "$(junit5)" ]; then stack=junit5
  elif [ -n "$(first '(^|/)test_[^/]*\.py$')" ]; then stack=pytest; elif [ -n "$(first '\.(test|spec)\.[cm]?[jt]sx?$')" ]; then stack=jest; fi
fi

case "$stack" in
  junit5) beside="$(junit5 | head -1)" ;;
  pytest) beside="$(first '(^|/)(test_[^/]*|[^/]*_test)\.py$' | head -1)" ;;
  jest|vitest) beside="$(first '\.(test|spec)\.[cm]?[jt]sx?$' | head -1)" ;;
  "") finish 2 "inconclusive (no supported stack: JUnit 5, pytest or vitest/jest test files)" ;;
  *) finish 2 "inconclusive (unknown stack '$stack': junit5 pytest vitest jest)" ;;
esac
if [ -n "${HARNESS_GATE_PROOF_BESIDE:-}" ]; then
  beside="${HARNESS_GATE_PROOF_BESIDE#./}"
  [ -f "$beside" ] || finish 2 "inconclusive (HARNESS_GATE_PROOF_BESIDE=$beside is not a file)"
fi
[ -n "$beside" ] || finish 2 "inconclusive (no $stack test file to plant a test beside)"
dir="$(dirname "$beside")"

plant() { # plant <true|false>: write the planted test (passing or failing) into the worktree; prints its path
  local ok="$1" p
  case "$stack" in
    junit5)
      p="$dir/HarnessGateProofTest.java"
      { sed -n 's/^[[:space:]]*\(package [^;]*;\).*/\1/p' "$beside" | head -1
        printf 'class HarnessGateProofTest {\n    @org.junit.jupiter.api.Test\n    void gateProof() { org.junit.jupiter.api.Assertions.assertTrue(%s, "harness gate proof"); }\n}\n' "$ok"; } > "$w/$p" ;;
    pytest)
      p="$dir/test_harness_gate_proof.py"
      printf 'def test_harness_gate_proof():\n    assert %s, "harness gate proof"\n' "$([ "$ok" = true ] && echo True || echo False)" > "$w/$p" ;;
    jest|vitest)
      p="$dir/harness-gate-proof.test.${beside##*.}"
      { [ "$stack" = vitest ] && echo "import { test, expect } from 'vitest';"
        printf "test('harness gate proof', () => {\n  expect(%s).toBe(true);\n});\n" "$ok"; } > "$w/$p" ;;
  esac
  touch "$w/$p"; echo "$p"
}
case "$stack" in
  junit5) nosuch="$dir/HarnessNoSuchTest.java" ;;
  pytest) nosuch="$dir/test_harness_no_such.py" ;; *) nosuch="$dir/harness-no-such.test.${beside##*.}" ;;
esac

tmp="$(mktemp -d)"; w="$tmp/w"
cleanup() { git worktree remove --force "$w" >/dev/null 2>&1; rm -rf "$tmp"; }
trap cleanup EXIT
git worktree add -q --detach "$w" HEAD >/dev/null 2>&1 || finish 2 "inconclusive (could not create a scratch worktree)"
{ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u | while IFS= read -r f; do
  if [ -e "$f" ]; then mkdir -p "$w/$(dirname "$f")"; cp -p "$f" "$w/$f"; else rm -f "$w/$f"; fi
done
# shortcut: shares the usual gitignored dependency/env folders by symlink (as red-proof.sh); a cold build still compiles everything
for d in $(find . -maxdepth 3 \( -name node_modules -o -name .venv -o -name venv \) -type d -prune 2>/dev/null) .env .env.local; do
  [ -e "$d" ] && [ ! -e "$w/$d" ] && { mkdir -p "$w/$(dirname "$d")"; ln -s "$ROOT/${d#./}" "$w/${d#./}"; }
done

tail_out() { grep -v '^[[:space:]]*$' "$tmp/out" | tail -3 | tr '\n' ' ' | cut -c1-240; }
run_test() { # run_test <T>: the repo's test target in the worktree; 3 = not wired
  local c; c="$(bash "$RES" "$w" test "$1" 2>/dev/null)" || return 3
  (cd "$w" && eval "$c") >"$tmp/out" 2>&1
}
fast_cmd=""; fast_na=""
if c="$(bash "$RES" "$w" check-fast 2>/dev/null)"; then
  fast_cmd="$c"
  if [ "${c#make }" != "$c" ] && [ -f "$w/harness.mk" ]; then
    # only the planted file is "changed", and lint/typecheck can't be what turns check-fast red
    fast_cmd="$c HARNESS_BASE=HEAD HARNESS_LINT=@true HARNESS_TYPECHECK=@true"
    plan="$(make -s --no-print-directory -C "$w" harness-test-plan HARNESS_BASE=HEAD 2>/dev/null)"
    secs="$(sed -n 's/^secs=//p' <<<"$plan")"
    if [ "$(sed -n 's/^mode=//p' <<<"$plan")" = none ] && ! { [[ "$secs" =~ ^[0-9]+$ ]] && [ "$secs" -le 60 ]; }; then
      fast_na="check-fast runs no tests by design"
    fi
  fi
fi
run_fast() { (cd "$w" && eval "$fast_cmd") >"$tmp/out" 2>&1; }

t="$(plant true)"
run_test "$t"; rc=$?
[ $rc -eq 3 ] && finish 2 "inconclusive (the test target is not wired: \`make test T=<file>\`)"
[ $rc -eq 0 ] || finish 2 "inconclusive (test T=$t fails with a passing planted test: $(tail_out))"
if [ -n "$fast_cmd" ] && [ -z "$fast_na" ]; then
  run_fast || finish 2 "inconclusive (check-fast fails with only a passing planted test changed: $(tail_out))"
fi

bad=""; ok=""
plant false >/dev/null
if run_test "$t"; then bad="$bad; test T=<failing test> exits 0"; else ok="$ok test"; fi
if [ -z "$fast_cmd" ]; then bad="$bad; check-fast not wired"
elif [ -n "$fast_na" ]; then ok="$ok; $fast_na"
elif run_fast; then bad="$bad; check-fast exits 0 with a failing changed test"
else ok="$ok check-fast"; fi
rm -f "$w/$t"
if run_test "$nosuch"; then bad="$bad; test T=<no such test> exits 0 (0 tests ran must fail)"; else ok="$ok no-such-test"; fi

[ -z "$bad" ] || finish 1 "NOT proven ($stack${bad}) — a test command ending in \`; :\` or a 0-tests pass hides failures; see layout.md"
finish 0 "proven red ($stack: red on${ok}; planted beside $beside)"
