#!/usr/bin/env bash
# scripts/harness/red-proof.sh — prove the change's tests fail without its production code (the red of red → green).
# Usage: bash scripts/harness/red-proof.sh [<base>]   (from the repo root; harness-verify runs it)
#   <base>: what "without the change" means. Default: the merge-base with origin/HEAD (else origin/main, origin/master);
#           with no remote, HEAD (uncommitted changes only).
# In a scratch worktree holding the current code (committed + uncommitted), each changed test file is run with the
# repo's `test T=<file>` target: it must pass (green control), then fail once the changed production files are put
# back to <base> (red). Last line, and exit code:
#   red: proven (…)        0  at least one changed test fails without the change
#   red: n/a (…)           0  no production code changed
#   red: not proven (…)    1  production code changed, but no test changed or every changed test passes without it
#   red: inconclusive (…)  2  the tests don't pass in the scratch worktree, or `test` is not wired
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "red: inconclusive (not a git repo)"; exit 2; }
cd "$ROOT" || exit 2
RES="$(cd "$(dirname "$0")" && pwd)/cmd.sh"; [ -f "$RES" ] || RES="${CLAUDE_PLUGIN_ROOT:-}/scripts/harness-cmd.sh"
[ -f "$RES" ] || { echo "red: inconclusive (scripts/harness/cmd.sh not found)"; exit 2; }

base="${1:-}"
if [ -z "$base" ]; then
  up="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  for b in "$up" origin/main origin/master; do
    [ -n "$b" ] && git rev-parse -q --verify "$b" >/dev/null 2>&1 && { base="$(git merge-base HEAD "$b" 2>/dev/null)"; break; }
  done
  base="${base:-HEAD}"
fi
git rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1 || { echo "red: inconclusive (unknown base '$base')"; exit 2; }

# shortcut: one regex per kind for every stack; a repo with other conventions gets "no test changed" — then add its pattern here
TEST_RE='(^|/)(test|tests|__tests__|spec|specs)/|(^|/)src/test[^/]*/|\.(test|spec)\.[cm]?[jt]sx?$|_test\.(go|py)$|(^|/)test_[^/]*\.py$|Tests?\.(java|kt|scala|groovy|cs)$|_spec\.rb$'
CODE_RE='\.(java|kt|kts|groovy|scala|go|py|[cm]?[jt]sx?|rb|rs|cs|php|swift|c|cc|cpp|h|hpp|sh|bash|sql|vue|svelte)$'
SKIP_RE='^(docs|plans|\.harness|\.githooks|\.agents|\.claude|scripts/harness)/|(^|/)(node_modules|target|build|dist|out)/'

changed="$( { git diff --name-only "$base" 2>/dev/null; git ls-files --others --exclude-standard; } | sort -u | grep -vE "$SKIP_RE")"
tests="$(grep -E "$TEST_RE" <<<"$changed" | while IFS= read -r f; do [ -f "$f" ] && echo "$f"; done)"
src="$(grep -vE "$TEST_RE" <<<"$changed" | grep -E "$CODE_RE")"
[ -n "$src" ] || { echo "red: n/a (no production code changed since ${base:0:9})"; exit 0; }
[ -n "$tests" ] || { echo "red: not proven (production code changed but no test changed: $(head -3 <<<"$src" | tr '\n' ' '))"; exit 1; }

tmp="$(mktemp -d)"; w="$tmp/w"
cleanup() { git worktree remove --force "$w" >/dev/null 2>&1; rm -rf "$tmp"; }
trap cleanup EXIT
git worktree add -q --detach "$w" HEAD >/dev/null 2>&1 || { echo "red: inconclusive (could not create a scratch worktree)"; exit 2; }
# the current code: uncommitted edits and new files on top of HEAD
{ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u | while IFS= read -r f; do
  if [ -e "$f" ]; then mkdir -p "$w/$(dirname "$f")"; cp -p "$f" "$w/$f"; else rm -f "$w/$f"; fi
done
# shortcut: shares the usual gitignored dependency/env folders by symlink; others (e.g. a generated client) are missing
for d in $(find . -maxdepth 3 \( -name node_modules -o -name .venv -o -name venv \) -type d -prune 2>/dev/null) .env .env.local; do
  [ -e "$d" ] && [ ! -e "$w/$d" ] && { mkdir -p "$w/$(dirname "$d")"; ln -s "$ROOT/${d#./}" "$w/${d#./}"; }
done

run_test() { # run_test <file>: 0 when the repo's test target passes for that file in the scratch worktree
  local c; c="$(bash "$RES" "$w" test "$1" 2>/dev/null)" || return 3
  (cd "$w" && eval "$c") >"$tmp/out" 2>&1
}
green=""; nogreen=""
while IFS= read -r t; do
  run_test "$t"; rc=$?
  [ $rc -eq 3 ] && { echo "red: inconclusive (the test target is not wired: \`make test T=<file>\`)"; exit 2; }
  if [ $rc -eq 0 ]; then green="$green$t"$'\n'; else nogreen="$nogreen $t"; fi
done <<<"$tests"
[ -n "$green" ] || { echo "red: inconclusive (the changed tests don't pass in a scratch worktree:$nogreen — missing dependencies or services?)"; exit 2; }

# put the production code back to base: changed files restored, new files removed
while IFS= read -r f; do
  if git cat-file -e "$base:$f" 2>/dev/null; then git -C "$w" checkout -q "$base" -- "$f"; else rm -f "$w/$f"; fi
done <<<"$src"
red=""; stillgreen=""
while IFS= read -r t; do
  [ -n "$t" ] || continue
  if run_test "$t"; then stillgreen="$stillgreen $t"; else red="$red $t"; fi
done <<<"$green"
nsrc="$(grep -c . <<<"$src")"
if [ -n "$red" ]; then
  echo "red: proven (fail without the change:$red${stillgreen:+; still pass:$stillgreen}; $nsrc production file(s) reverted to ${base:0:9})"
  exit 0
fi
echo "red: not proven (every changed test passes without the change:$stillgreen)"
exit 1
