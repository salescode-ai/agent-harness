#!/usr/bin/env bash
# related-tests.sh: run the tests related to the changed files (check-fast's HARNESS_TEST_CHANGED).
# Usage: bash scripts/harness/related-tests.sh [-C <dir>] <stack> "<test command>" <changed files...>
#   stack:  jest | vitest | node | maven | gradle | go | pytest
#   "<test command>": the repo's runner prefix, e.g. "./mvnw -B -q test"; "" uses the stack default
#   -C <dir>: run inside <dir> (a monorepo module); files outside it are ignored
# A changed test file runs itself. A changed source file selects tests by name (Foo → FooTest/FooTests/FooIT/TestFoo,
# foo.py → test_foo.py/foo_test.py) and by reference (test files that mention it). Jest/Vitest use their own
# related-test lookup; Go tests each changed package. Nothing related: one line, exit 0.
# RELATED_TESTS_DRY=1 runs nothing and prints "none: <file>" per changed source no test selects (harness-lint).
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

[ -n "${RELATED_TESTS_DRY:-}" ] && case "$stack" in jest|vitest|go) exit 0;; esac  # native lookup: can't tell
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
# One grep pass over the test files for every stem/package name (was one grep per source x test: minutes on big repos).
words=""
while IFS= read -r f; do
  [ -n "$f" ] || continue; printf '%s\n' "$f" | grep -qE "$is_test" && continue
  b="$(basename "$f")"; s="${b%.*}"; [ "$s" = __init__ ] && s="$(basename "$(dirname "$f")")"
  words="$words$s"$'\n'
  [ "$stack" = pytest ] && { p="${f#src/}"; p="${p%%/*}"; words="$words${p%.py}"$'\n'; }
done <<<"$files"
hits=""  # "<test file>:<word>" for each word a test file mentions
if [ -n "$tests" ] && [ -n "$words" ]; then
  wf="$(mktemp)"; grep -v '^$' <<<"$words" | sort -u > "$wf"
  hits="$(tr '\n' '\0' <<<"$tests" | xargs -0 grep -HowF -f "$wf" -- 2>/dev/null | sort -u)"
  rm -f "$wf"
fi
mentions() { [ -n "$hits" ] && awk -v w="$1" '{n=length($0)-length(w)} n>1 && substr($0,n)==":" w {print substr($0,1,n-1)}' <<<"$hits"; }
sel=""; none=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if printf '%s\n' "$f" | grep -qE "$is_test"; then sel="$sel$f"$'\n'; continue; fi
  b="$(basename "$f")"; s="${b%.*}"
  [ "$s" = __init__ ] && s="$(basename "$(dirname "$f")")"  # a package: tests that mention the package
  got=""
  if [ -n "$tests" ]; then
    case "$stack" in
      maven|gradle) pat="(^|/)($s|${s}Test|${s}Tests|${s}IT|Test${s})\.($ext)$" ;;
      pytest)       pat="(^|/)(test_${s}|${s}_test)\.py$" ;;
      *)            pat="(^|/)${s}\.(test|spec)\.[cm]?[jt]sx?$" ;;
    esac
    named="$(grep -E "$pat" <<<"$tests")"
    got="$named"$'\n'"$(mentions "$s")"
    if [ "$stack" = pytest ]; then  # else the package's tests: those that mention its top-level package
      p="${f#src/}"; p="${p%%/*}"; p="${p%.py}"
      [ -n "$named" ] || [ "$p" = "$s" ] || got="$got"$'\n'"$(mentions "$p")"
    fi
  fi
  [ -n "$(grep -v '^$' <<<"$got" | grep -vE '(^|/)conftest\.py$')" ] || none="$none$f"$'\n'
  sel="$sel$got"$'\n'
done <<<"$files"
sel="$(grep -v '^$' <<<"$sel" | grep -vE '(^|/)conftest\.py$' | sort -u)"
if [ -n "${RELATED_TESTS_DRY:-}" ]; then  # harness-lint: name the changed sources no test covers; run nothing
  pre=""; [ "$dir" != . ] && pre="${dir%/}/"  # repo-relative, like the file= lines lint compares them with
  grep -v '^$' <<<"$none" | sed "s#^#none: $pre#"; exit 0
fi
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
