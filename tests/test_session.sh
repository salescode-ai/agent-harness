SESSION="$PLUGIN/scripts/session-context.sh"
_sess() { printf '{"cwd":"%s"}' "$1" | "$SESSION" 2>&1; }
_sess_repo() { local d; d="$(mktemp -d)"; ( cd "$d"; git init -q -b main; printf '# a\n' > AGENTS.md ) >/dev/null; echo "$d"; }

t_session_warns_hooks_off() {
  local d out; d="$(_sess_repo)"; mkdir "$d/.githooks"
  assert_contains "$(_sess "$d")" "git hooks not installed — run: make setup" "warn"
  git -C "$d" config core.hooksPath .githooks
  assert_not_contains "$(_sess "$d")" "git hooks not installed" "hooksPath set"
  git -C "$d" config --unset core.hooksPath; mkdir "$d/.husky"
  assert_not_contains "$(_sess "$d")" "git hooks not installed" "manager"
}
t_session_audit_age() {
  local d old; d="$(_sess_repo)"; mkdir -p "$d/docs/harness"
  old="$(python3 -c "import datetime;print(datetime.date.today()-datetime.timedelta(days=40))")"
  printf '| %s | Functional | g=1 s=1 c=1 t=1 o=1 | health=- | tokens=100 |\n' "$old" > "$d/docs/harness/AUDIT-LOG.md"
  assert_contains "$(_sess "$d")" "harness audit is 40 days old — run /harness-audit" "old"
  printf 'quick audit: every 60 days\n' >> "$d/AGENTS.md"
  assert_not_contains "$(_sess "$d")" "harness audit is" "cadence"
}
t_session_init_in_progress() {
  local d; d="$(_sess_repo)"; mkdir "$d/.harness"
  echo '{"layers_done":["guides","sensors"]}' > "$d/.harness/init-state.json"
  assert_contains "$(_sess "$d")" "harness setup in progress — resume with /harness-init" "in progress"
  echo '{"layers_done":["guides","sensors","context","tools","observability"]}' > "$d/.harness/init-state.json"
  assert_not_contains "$(_sess "$d")" "setup in progress" "done"
  echo '{"target":"Functional","layers_done":["guides","sensors"]}' > "$d/.harness/init-state.json"
  assert_not_contains "$(_sess "$d")" "setup in progress" "Functional needs guides+sensors only"
  echo '{"target":"Functional","layers_done":["guides"]}' > "$d/.harness/init-state.json"
  assert_contains "$(_sess "$d")" "setup in progress" "Functional missing sensors"
  echo '{"target":"Robust","layers_done":["guides","sensors"]}' > "$d/.harness/init-state.json"
  assert_contains "$(_sess "$d")" "setup in progress" "Robust needs all five"
  echo '{oops' > "$d/.harness/init-state.json"
  assert_not_contains "$(_sess "$d")" "setup in progress" "bad json"
  assert_eq "$(_sess "$d" | grep -c 'init-state.json is unreadable')" 1 "bad json warned once"
}
t_session_silent_outside_repo() {
  assert_eq "$(_sess "$(mktemp -d)")" "" "silent"
}
