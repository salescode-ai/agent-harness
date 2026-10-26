# Shared test helpers. bash 3.2 compatible. Assertions return 1; run.sh runs each test under set -e.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$ROOT/plugins/agent-harness"
FIXTURES="$ROOT/tests/fixtures"

_fail() { echo "    assertion failed: $1" >&2; return 1; }

assert_eq() { [ "$1" = "$2" ] || _fail "$3 (expected '$2', got '$1')"; }
assert_contains() { case "$1" in *"$2"*) ;; *) _fail "$3 (missing '$2')";; esac; }
assert_not_contains() { case "$1" in *"$2"*) _fail "$3 (unexpected '$2')";; esac; }

# assert_exit <code> <msg> -- <cmd...>
assert_exit() {
  local want="$1" msg="$2" got=0
  shift 3
  "$@" >/dev/null 2>&1 || got=$?
  [ "$got" = "$want" ] || _fail "$msg (expected exit $want, got $got)"
}

# skip <name>: <reason> ends the current test as skipped (exit 77 is read by run.sh)
skip() { echo "skip $1: $2"; exit 77; }

# mk_repo <fixture-name>: fresh git repo from a fixture, one commit, fake origin/main; echoes path
mk_repo() {
  local d
  d="$(mktemp -d)"
  cp -R "$FIXTURES/$1/." "$d/"
  (
    cd "$d"
    git init -q -b main
    git config user.email t@example.com
    git config user.name test
    git add -A
    git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m init
    git update-ref refs/remotes/origin/main HEAD
  ) >/dev/null
  echo "$d"
}

# mk_template_repo: git repo with all v2 templates, lint.sh, harness.mk included from a Makefile; echoes path
mk_template_repo() {
  local d A="$PLUGIN/skills/harness-init/assets"
  d="$(mktemp -d)"
  ( cd "$A" && tar cf - AGENTS.md INVARIANTS.md CLAUDE.md GLOSSARY.md docs harness.mk ) | ( cd "$d" && tar xf - )
  mkdir -p "$d/scripts/harness" "$d/scripts"
  cp "$A/lint.sh" "$d/scripts/harness/lint.sh"; cp "$A/harness/plan-check.sh" "$d/scripts/harness/plan-check.sh"
  cat "$A/gitignore.append" > "$d/.gitignore"
  printf 'include harness.mk\n' > "$d/Makefile"
  ( cd "$d" && git init -q -b main ) >/dev/null
  echo "$d"
}

_stack_script() { # writes fail.sh: a JUnit-style failure buried above 60 stack frames
  printf '%s\n' 'echo "Running FooTest"' 'echo "Tests run: 5, Failures: 1, Errors: 0"' \
    'echo "FooTest.adds FAILED: expected:<1> but was:<2>"' \
    'i=0; while [ $i -lt 60 ]; do echo "	at org.example.Frame$i.call(Frame.java:$i)"; i=$((i+1)); done' \
    'echo "BUILD FAILED in 3s"; exit 1' > "$1/fail.sh"
}
