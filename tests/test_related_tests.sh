# related-tests.sh: changed source files select their tests (check-fast). The runner is faked with printf.
RT="$PLUGIN/skills/harness-init/assets/harness/related-tests.sh"
_rt_repo() { # _rt_repo <file>...: git repo holding empty files at those paths; echoes path
  local d f; d="$(mktemp -d)"
  ( cd "$d"; git init -q -b main; for f in "$@"; do mkdir -p "$(dirname "$f")"; : > "$f"; done ) >/dev/null
  echo "$d"
}
_rt() { (cd "$1" && shift && bash "$RT" "$@" 2>/dev/null); }

t_maven_maps_source_to_tests() {
  local d out; d="$(_rt_repo src/main/java/a/Foo.java src/test/java/a/FooTest.java src/test/java/a/FooIT.java \
    src/test/java/b/UsesFoo.java src/test/java/b/Other.java README.md)"
  echo 'new Foo();' > "$d/src/test/java/b/UsesFoo.java"
  out="$(_rt "$d" maven "printf %s\\\\n" src/main/java/a/Foo.java README.md)"
  assert_contains "$out" "-Dtest=FooIT,FooTest,UsesFoo" "name + reference selection"
  assert_contains "$out" "-Dsurefire.failIfNoSpecifiedTests=false" "no-match tolerant"
  assert_not_contains "$out" "Other" "unrelated test not run"
}
t_gradle_uses_tests_filter() {
  local d out; d="$(_rt_repo src/main/kotlin/Bar.kt src/test/kotlin/BarTests.kt)"
  out="$(_rt "$d" gradle "printf %s\\\\n" src/main/kotlin/Bar.kt)"
  assert_contains "$out" "--tests
BarTests" "gradle --tests"
}
t_go_tests_changed_packages() {
  local d out; d="$(_rt_repo go.mod internal/m/m.go internal/m/m_test.go cmd/x/main.go)"
  out="$(_rt "$d" go "printf %s\\\\n" internal/m/m.go internal/m/m_test.go main.go)"
  assert_eq "$out" "./internal/m" "one package, existing files only"
}
t_pytest_name_reference_and_package() {
  local d out; d="$(_rt_repo src/calc/__init__.py src/calc/ops.py tests/test_ops.py tests/test_api.py tests/test_misc.py)"
  echo 'from calc import add' > "$d/tests/test_api.py"
  out="$(_rt "$d" pytest "printf %s\\\\n" src/calc/ops.py)"
  assert_contains "$out" "tests/test_ops.py" "name match"
  out="$(_rt "$d" pytest "printf %s\\\\n" src/calc/__init__.py)"
  assert_eq "$out" "tests/test_api.py" "package __init__ → tests mentioning the package"
  out="$(_rt "$d" pytest "printf %s\\\\n" tests/test_misc.py)"
  assert_eq "$out" "tests/test_misc.py" "changed test runs itself"
}
t_js_runners() {
  local d out; d="$(_rt_repo src/sum.js src/sum.test.js)"
  assert_eq "$(_rt "$d" node "printf %s\\\\n" src/sum.js)" "src/sum.test.js" "node --test name match"
  out="$(_rt "$d" jest "printf %s\\\\n" src/sum.js)"
  assert_eq "$out" "$(printf -- '--findRelatedTests\n--passWithNoTests\nsrc/sum.js')" "jest native related"
  out="$(_rt "$d" vitest "printf %s\\\\n" src/sum.js)"
  assert_contains "$out" "related" "vitest related"
}
t_monorepo_dir_and_nothing_related() {
  local d out; d="$(_rt_repo backend/src/main/java/A.java backend/src/test/java/ATest.java ui/x.java)"
  out="$(_rt "$d" -C backend maven "printf %s\\\\n" backend/src/main/java/A.java ui/x.java)"
  assert_contains "$out" "-Dtest=ATest" "paths made relative to -C dir"
  out="$(_rt "$d" maven "false" docs/x.md)"
  assert_eq "$out" "tests: no changed maven files" "nothing to run is green"
  assert_exit 2 "unknown stack" -- bash "$RT" cobol "" a
}
t_check_fast_full_suite_when_fast() {
  local d; d="$(mktemp -d)"; cp "$PLUGIN/skills/harness-init/assets/harness.mk" "$d/"
  ( cd "$d" && git init -q -b main ) >/dev/null
  printf 'HARNESS_LINT = @true\nHARNESS_TEST_ALL = @echo FULL && false\nHARNESS_TEST_SECS = 12\ninclude harness.mk\n' > "$d/Makefile"
  assert_exit 2 "fast suite runs in check-fast" -- make -s -C "$d" check-fast
  sed -i.bak 's/= 12/= 90/' "$d/Makefile"
  assert_exit 0 "slow suite skipped" -- make -s -C "$d" check-fast
  printf 'HARNESS_TEST_CHANGED = @echo CHANGED\n' | cat - "$d/Makefile.bak" > "$d/Makefile"
  assert_exit 0 "explicit HARNESS_TEST_CHANGED wins" -- make -s -C "$d" check-fast
}
t_many_changed_sources_one_grep_pass() {
  local d i out s e; d="$(mktemp -d)"
  ( cd "$d"; git init -q -b main; mkdir -p src/main/java/a src/test/java/a
    i=0; while [ $i -lt 400 ]; do printf 'class T%s { Cls%s x; }\n' $i $((i % 200)) > src/test/java/a/T$i.java; i=$((i+1)); done
    i=0; while [ $i -lt 200 ]; do : > src/main/java/a/Cls$i.java; i=$((i+1)); done ) >/dev/null
  s=$(date +%s)
  out="$(cd "$d" && bash "$RT" maven "printf %s\\\\n" src/main/java/a/Cls*.java 2>/dev/null)"
  e=$(( $(date +%s) - s ))
  [ "$e" -lt 30 ] || _fail "200 changed sources x 400 tests took ${e}s (want < 30)"
  assert_contains "$out" "T0,T1,T10," "every referencing test selected"
  assert_contains "$out" "T399" "last test selected"
}
t_dry_run_names_untested_sources() {
  local d out; d="$(_rt_repo src/main/java/a/Foo.java src/main/java/a/Bar.java src/test/java/a/FooTest.java)"
  out="$(cd "$d" && RELATED_TESTS_DRY=1 bash "$RT" maven "false" src/main/java/a/Foo.java src/main/java/a/Bar.java)"
  assert_eq "$out" "none: src/main/java/a/Bar.java" "only the untested source, nothing run"
  out="$(cd "$d" && RELATED_TESTS_DRY=1 bash "$RT" jest "false" src/main/java/a/Foo.java)"
  assert_eq "$out" "tests: no changed jest files" "other stack untouched"
  d="$(_rt_repo api/src/main/java/a/Foo.java api/src/main/java/a/Bar.java api/src/test/java/a/FooTest.java)"
  out="$(cd "$d" && RELATED_TESTS_DRY=1 bash "$RT" -C api maven "false" api/src/main/java/a/Foo.java api/src/main/java/a/Bar.java)"
  assert_eq "$out" "none: api/src/main/java/a/Bar.java" "-C module: path stays repo-relative"
}
