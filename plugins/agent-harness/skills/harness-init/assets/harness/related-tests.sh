#!/usr/bin/env bash
# related-tests.sh: run the tests related to the changed files (check-fast's HARNESS_TEST_CHANGED).
# Usage: bash scripts/harness/related-tests.sh [-C <dir>] <stack> "<test command>" <changed files...>
#   stack:  jest | vitest | node | maven | gradle | go | pytest
#   "<test command>": the repo's runner prefix, e.g. "./mvnw -B -q test"; "" uses the stack default
#   -C <dir>: run inside <dir> (a monorepo module); files outside it are ignored
# A changed test file runs itself. A changed source file selects tests by name (Foo → FooTest/FooTests/FooIT/TestFoo,
# foo.py → test_foo.py/foo_test.py) and by reference (test files that mention it). Jest/Vitest use their own
# related-test lookup; Go tests each changed package. Nothing related: one line, exit 0.
dir=.
if [ "${1:-}" = "-C" ]; then dir="${2:?-C needs a dir}"; shift 2; fi
stack="${1:?usage: related-tests.sh [-C dir] <stack> \"<test command>\" <files...>}"; cmd="${2:-}"
shift; [ $# -gt 0 ] && shift
cd "$dir" || { echo "related-tests: no such dir: $dir" >&2; exit 1; }

case "$stack" in
  jest|vitest|node) ext='[cm]?[jt]sx?' ; is_test='\.(test|spec)\.[cm]?[jt]sx?$|(^|/)(test|tests|__tests__)/' ;;
  maven|gradle)     ext='java|kt|groovy|scala' ; is_test='(^|/)src/test[^/]*/' ;;
  go)               ext='go' ; is_test='_test\.go$' ;;
  pytest)           ext='py' ; is_test='(^|/)(test_[^/]*|[^/]*_test|conftest)\.py$' ;;
  *) echo "related-tests: unknown stack '$stack' (jest vitest node maven gradle go pytest)" >&2; exit 2 ;;
esac

files=""  # newline-separated changed files of this stack, relative to $dir
for f in "$@"; do
  [ "$dir" != . ] && { case "$f" in "${dir%/}/"*) f="${f#"${dir%/}/"}" ;; *) continue ;; esac; }
  [ -f "$f" ] && printf '%s\n' "$f" | grep -qE "\.($ext)$" && files="$files$f"$'\n'
done
if [ -z "$files" ]; then echo "tests: no changed $stack files"; exit 0; fi

run() { # run <args...>: the runner with the selection appended, each argument shell-quoted
  local q=""; for a in "$@"; do q="$q $(printf '%q' "$a")"; done
  echo "tests: $cmd$q" >&2
  eval "$cmd$q"
}

if [ "$stack" = jest ]; then cmd="${cmd:-npx jest --ci}"; set --; while IFS= read -r f; do [ -n "$f" ] && set -- "$@" "$f"; done <<<"$files"
  run --findRelatedTests --passWithNoTests "$@"; exit; fi
if [ "$stack" = vitest ]; then cmd="${cmd:-npx vitest}"; set --; while IFS= read -r f; do [ -n "$f" ] && set -- "$@" "$f"; done <<<"$files"
  run related --run --passWithNoTests "$@"; exit; fi
if [ "$stack" = go ]; then
  cmd="${cmd:-go test}"; set --
  while IFS= read -r d; do [ -n "$d" ] && set -- "$@" "./$d"; done <<<"$(while IFS= read -r f; do [ -n "$f" ] && dirname "$f"; done <<<"$files" | sed 's#^\./##; s#^\.$##' | sort -u)"
  # shortcut: packages that import a changed package are not re-tested; check (pre-push) runs ./...
  run "$@"; exit; fi

tests="$(git ls-files --cached --others --exclude-standard 2>/dev/null | grep -E "$is_test" | grep -E "\.($ext)$")"
sel=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if printf '%s\n' "$f" | grep -qE "$is_test"; then sel="$sel$f"$'\n'; continue; fi
  b="$(basename "$f")"; s="${b%.*}"
  [ "$s" = __init__ ] && s="$(basename "$(dirname "$f")")"  # a package: tests that mention the package
  [ -n "$tests" ] || continue
  case "$stack" in
    maven|gradle) pat="(^|/)($s|${s}Test|${s}Tests|${s}IT|Test${s})\.($ext)$" ;;
    pytest)       pat="(^|/)(test_${s}|${s}_test)\.py$" ;;
    *)            pat="(^|/)${s}\.(test|spec)\.[cm]?[jt]sx?$" ;;
  esac
  sel="$sel$(grep -E "$pat" <<<"$tests")"$'\n'
  sel="$sel$(while IFS= read -r t; do [ -n "$t" ] && grep -qw -- "$s" "$t" 2>/dev/null && echo "$t"; done <<<"$tests")"$'\n'
  if [ "$stack" = pytest ]; then  # else the package's tests: those that mention its top-level package
    p="${f#src/}"; p="${p%%/*}"; p="${p%.py}"
    [ -n "$(grep -E "$pat" <<<"$tests")" ] || [ "$p" = "$s" ] || \
      sel="$sel$(while IFS= read -r t; do [ -n "$t" ] && grep -qw -- "$p" "$t" 2>/dev/null && echo "$t"; done <<<"$tests")"$'\n'
  fi
done <<<"$files"
sel="$(grep -v '^$' <<<"$sel" | grep -vE '(^|/)conftest\.py$' | sort -u)"
if [ -z "$sel" ]; then echo "tests: no tests related to the changed $stack files"; exit 0; fi

set --; while IFS= read -r t; do set -- "$@" "$t"; done <<<"$sel"
case "$stack" in
  maven)
    names=""; for t in "$@"; do b="$(basename "$t")"; names="${names:+$names,}${b%.*}"; done
    [ -z "$cmd" ] && { [ -x ./mvnw ] && cmd="./mvnw -B -q test" || cmd="mvn -B -q test"; }
    run "-Dtest=$names" -Dsurefire.failIfNoSpecifiedTests=false -DfailIfNoTests=false ;;
  gradle)
    [ -z "$cmd" ] && { [ -x ./gradlew ] && cmd="./gradlew test --console=plain -q" || cmd="gradle test --console=plain -q"; }
    a=(); for t in "$@"; do b="$(basename "$t")"; a+=(--tests "${b%.*}"); done
    run "${a[@]}" ;;
  pytest) cmd="${cmd:-python3 -m pytest -q}"; run "$@" ;;
  node)   cmd="${cmd:-node --test}"; run "$@" ;;
esac
