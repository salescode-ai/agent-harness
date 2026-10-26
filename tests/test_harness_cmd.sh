CMD="$PLUGIN/scripts/harness-cmd.sh"
_mk() { local d; d="$(mktemp -d)"; mkdir -p "$d/$1"; printf 'check:\n\t@true\n' > "$d/$1/Makefile"; echo "$d/$1"; }

t_make_default() {
  local d; d="$(_mk repo)"
  assert_eq "$("$CMD" "$d" check)" "make -s -C $d check" "plain"
  assert_eq "$("$CMD" "$d" check a.py)" "make -s -C $d check T=a.py" "with T"
}
t_make_quotes_spaces() {
  local d; d="$(_mk 'a b')"
  assert_eq "$("$CMD" "$d" check)" "make -s -C '$d' check" "quoted"
  assert_eq "$(eval "$("$CMD" "$d" check)" && echo ran)" "ran" "eval-able"
}
t_registered() {
  local d; d="$(_mk repo)"; mkdir "$d/.agents"
  echo '{"commands":{"test":"just test {T}","lint":"just lint {T}"}}' > "$d/.agents/harness.json"
  assert_eq "$("$CMD" "$d" test a.py)" "just test a.py" "T"
  assert_eq "$("$CMD" "$d" lint)" "just lint" "no T"
  assert_eq "$("$CMD" "$d" check)" "make -s -C $d check" "other target falls to make"
}
t_unresolvable_exit3() {
  local d out rc=0; d="$(_mk repo)"
  out="$("$CMD" "$d" nope 2>/dev/null)" || rc=$?
  assert_eq "$rc" 3 "exit"; assert_eq "$out" "" "silent"
}
t_bad_json_falls_back() {
  local d out err; d="$(_mk repo)"; mkdir "$d/.agents"; echo '{oops' > "$d/.agents/harness.json"
  out="$("$CMD" "$d" check 2>"$d/err")"; err="$(cat "$d/err")"
  assert_eq "$out" "make -s -C $d check" "fallback"
  assert_contains "$err" "harness-cmd: .agents/harness.json unreadable, using make" "warn"
}
t_no_make_exit4() {
  local d b t rc=0 err; d="$(_mk repo)"; b="$(mktemp -d)"
  for t in bash python3 dirname cat; do ln -s "$(command -v $t)" "$b/$t"; done
  PATH="$b" "$(command -v bash)" "$CMD" "$d" check >/dev/null 2>"$d/err" || rc=$?
  assert_eq "$rc" 4 "exit"; assert_contains "$(cat "$d/err")" "harness-cmd: make not found" "msg"
}
t_registered_T_quoted() {
  local d; d="$(_mk repo)"; mkdir "$d/.agents"
  printf '{"commands":{"test":"printf \\"%%s\\\\n\\" {T}"}}' > "$d/.agents/harness.json"
  local out; out="$(cd "$d" && eval "$("$CMD" "$d" test 'a b;touch PWNED')")"
  assert_eq "$out" "a b;touch PWNED" "one argument"
  [ ! -e "$d/PWNED" ] || _fail "injected command ran"
}
t_registered_no_T_keeps_spacing() {
  local d; d="$(_mk repo)"; mkdir "$d/.agents"
  echo '{"commands":{"test":"echo \"a  b\" {T}"}}' > "$d/.agents/harness.json"
  assert_eq "$("$CMD" "$d" test)" 'echo "a  b"' "spacing"
}
