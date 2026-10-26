H="$PLUGIN/skills/harness-init/assets/harness"
# _sr: temp repo with the proof runner, no-prod-data sensor and an empty registry; echoes path
_sr() {
  local d; d="$(mktemp -d)"; mkdir -p "$d/scripts/harness"
  cp -R "$H/sensors" "$H/sensor-proof.sh" "$d/scripts/harness/"
  ( cd "$d" && git init -q -b main ) >/dev/null
  echo "$d"
}
# _add <repo> <json-entry>
_add() { python3 -c '
import json,sys
p=sys.argv[1]+"/scripts/harness/sensors/registry.json"; r=json.load(open(p)); r["sensors"].append(json.loads(sys.argv[2])); json.dump(r,open(p,"w"))' "$1" "$2"; }
_proof() { ( cd "$1" && bash scripts/harness/sensor-proof.sh "$2" 2>&1 ); }
_npd='{"name":"no-prod-data","severity":"Critical","invariant":"Data Integrity","run":"bash scripts/harness/sensors/no-prod-data.sh {paths}","mode":"paths","clean":"db/seeds","fixture":"scripts/harness/sensors/fixtures/no-prod-data/","dest":""}'

t_proof_ok() {
  local d out; d="$(_sr)"; mkdir -p "$d/db/seeds"
  echo "INSERT INTO users VALUES ('a@example.com');" > "$d/db/seeds/seed.sql"
  _add "$d" "$_npd"
  out="$(_proof "$d" no-prod-data)"
  assert_eq "$out" "proof no-prod-data: OK" "proof output"
  assert_exit 0 "recheck" -- bash -c "cd '$d' && bash scripts/harness/sensor-proof.sh --recheck"
}
t_proof_fails_when_sensor_silent() {
  local d out; d="$(_sr)"; mkdir -p "$d/scripts/harness/sensors/fixtures/x" "$d/c"
  echo bad > "$d/scripts/harness/sensors/fixtures/x/f.txt"
  _add "$d" '{"name":"silent","severity":"Important","invariant":"X","run":"true","mode":"paths","clean":"c","fixture":"scripts/harness/sensors/fixtures/x/","dest":""}'
  out="$(_proof "$d" silent)" && return 1
  assert_contains "$out" "FAIL step 2" "names step"
}
t_copy_mode_cleans_up() {
  local d dest; d="$(_sr)"; dest="$d/src"; mkdir -p "$dest/sub" "$d/scripts/harness/sensors/fixtures/c/sub"
  echo keep > "$dest/existing.txt"
  echo v > "$d/scripts/harness/sensors/fixtures/c/planted.txt"; echo v > "$d/scripts/harness/sensors/fixtures/c/sub/deep.txt"
  # fails (exit 1) whenever planted.txt exists; prints a message
  _add "$d" '{"name":"cp","severity":"Important","invariant":"X","run":"test ! -e src/planted.txt || { echo found; exit 1; }","mode":"copy","clean":"","fixture":"scripts/harness/sensors/fixtures/c/","dest":"src"}'
  _proof "$d" cp | grep -q 'proof cp: OK'
  [ ! -e "$dest/planted.txt" ] && [ ! -e "$dest/sub/deep.txt" ] && [ -f "$dest/existing.txt" ]
  # sensor that always fails: proof fails at step 1 and still leaves no files; recheck with silent sensor too
  _add "$d" '{"name":"cp2","severity":"Important","invariant":"X","run":"true","mode":"copy","clean":"","fixture":"scripts/harness/sensors/fixtures/c/","dest":"src"}'
  ( cd "$d" && bash scripts/harness/sensor-proof.sh --recheck ) >/dev/null 2>&1 && return 1
  [ ! -e "$dest/planted.txt" ] && [ ! -e "$dest/sub/deep.txt" ] && [ -f "$dest/existing.txt" ]
  # refuses to overwrite a pre-existing file
  echo mine > "$dest/planted.txt"
  ( cd "$d" && bash scripts/harness/sensor-proof.sh --recheck 2>&1 ) | grep -q 'refusing to overwrite'
  assert_eq "$(cat "$dest/planted.txt")" mine "pre-existing file untouched"
}
t_paths_with_spaces() {
  local d; d="$(_sr)"; mkdir -p "$d/my seeds" "$d/scripts/harness/sensors/fixtures/s p"
  echo ok > "$d/my seeds/a.txt"; echo 'x@acme.com' > "$d/scripts/harness/sensors/fixtures/s p/f.txt"
  _add "$d" '{"name":"sp","severity":"Critical","invariant":"X","run":"bash scripts/harness/sensors/no-prod-data.sh {paths}","mode":"paths","clean":"my seeds","fixture":"scripts/harness/sensors/fixtures/s p/","dest":""}'
  _proof "$d" sp | grep -q 'proof sp: OK'
}
t_no_prod_data_allows_example_com() {
  local d; d="$(mktemp -d)"
  printf "a@example.com\nb@mail.test\nc@x.invalid\nd@host.local\n+15550100123\n+0044123\nhost.dev.internal\n" > "$d/ok.txt"
  assert_exit 0 "clean" -- bash "$H/sensors/no-prod-data.sh" "$d"
  [ -z "$(bash "$H/sensors/no-prod-data.sh" "$d")" ]
}
t_no_prod_data_flags() {
  local d out; d="$(mktemp -d)"
  printf "ok\nu@acme.com\nhost db.prod.corp.net\nx.rds.amazonaws.com\ncall +14155550123\n" > "$d/s.sql"
  head -c 1100000 /dev/zero | tr '\0' 'a' > "$d/big.dump"
  out="$(bash "$H/sensors/no-prod-data.sh" "$d")" && return 1
  assert_contains "$out" "s.sql:2: real-looking email address — use synthetic data (INVARIANTS.md Data Integrity)" "email"
  assert_contains "$out" "s.sql:3: production hostname" "prod host"
  assert_contains "$out" "s.sql:4: production hostname" "rds"
  assert_contains "$out" "s.sql:5: real-looking phone number" "phone"
  assert_contains "$out" "big.dump:1:" "big dump"
}
t_missing_python_exits_2() {
  local d rc=0; d="$(_sr)"
  ( cd "$d" && PATH=/nonexistent /bin/bash scripts/harness/sensor-proof.sh --recheck ) >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" 2 "exit code"
}
t_empty_registry_recheck_ok() { local d; d="$(_sr)"; assert_exit 0 "empty" -- bash -c "cd '$d' && bash scripts/harness/sensor-proof.sh --recheck"; }
t_corrupt_registry_fails() {
  local d out rc=0; d="$(_sr)"; echo '{nope' > "$d/scripts/harness/sensors/registry.json"
  out="$(cd "$d" && bash scripts/harness/sensor-proof.sh --recheck 2>&1)" || rc=$?
  assert_eq "$rc" 2 "exit"; assert_contains "$out" "cannot parse" "msg"
}
t_copy_nested_missing_dest_cleaned() {
  local d; d="$(_sr)"; mkdir -p "$d/scripts/harness/sensors/fixtures/n/a/b"
  echo v > "$d/scripts/harness/sensors/fixtures/n/a/b/f.txt"
  _add "$d" '{"name":"nn","severity":"Important","invariant":"X","run":"test ! -e out/x/a/b/f.txt || { echo found; exit 1; }","mode":"copy","clean":"","fixture":"scripts/harness/sensors/fixtures/n/","dest":"out/x"}'
  _proof "$d" nn | grep -q 'proof nn: OK'
  [ ! -e "$d/out" ]
}
t_rejects_unsafe_paths() {
  local d out; d="$(_sr)"
  _add "$d" '{"name":"bad","severity":"Important","invariant":"X","run":"true","mode":"copy","clean":"","fixture":"scripts/harness/sensors/fixtures/n/","dest":"../escape"}'
  out="$(cd "$d" && bash scripts/harness/sensor-proof.sh --recheck 2>&1)" && return 1
  assert_contains "$out" "must be relative" "msg"
}
t_no_prod_data_allows_org_net_case() {
  local d; d="$(mktemp -d)"; printf "a@Example.COM\nb@example.org\nc@example.net\n" > "$d/o.txt"
  assert_exit 0 "allowed" -- bash "$H/sensors/no-prod-data.sh" "$d"
}
