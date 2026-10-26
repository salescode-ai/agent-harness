# Workspace v2 tests. Builds the workspace at test time from tests/fixtures/workspace.
mk_ws() { # echoes workspace path: api (harnessed), portal (AGENTS.md only), app (plain); all git repos with origin/main
  local ws; ws="$(mktemp -d)"
  cp "$FIXTURES/workspace/harness-workspace.json" "$ws/"
  cp "$PLUGIN/skills/harness-workspace/assets/ws.sh" "$ws/"
  mkdir -p "$ws/scripts/harness"; cp "$PLUGIN/scripts/harness-cmd.sh" "$ws/scripts/harness/cmd.sh"
  printf '# ws\n- api\n- portal\n- app\n' > "$ws/AGENTS.md"; echo "# inv" > "$ws/INVARIANTS.md"
  local r
  for r in api portal app; do
    mkdir "$ws/$r"; echo "# $r" > "$ws/$r/README.md"
    case $r in
      api) echo "# api" > "$ws/api/AGENTS.md"; echo "# inv" > "$ws/api/INVARIANTS.md"
        printf 'check:\n\t@echo ok\ncheck-fast:\n\t@echo ok\nsetup:\n\t@echo api >> "$(WSLOG)"\n' > "$ws/api/Makefile";;
      portal) echo "# portal" > "$ws/portal/AGENTS.md";;
    esac
    ( cd "$ws/$r"; git init -q -b main; git config user.email t@e.c; git config user.name t; git add -A
      git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m init; git update-ref refs/remotes/origin/main HEAD ) >/dev/null
  done
  echo "$ws"
}
ws() { ( cd "$WS_T" && bash ws.sh "$@" ); }

t_states() {
  WS_T="$(mk_ws)"
  assert_contains "$(ws state api 2>&1)" "present" "api"
  out="$(ws status)"
  assert_contains "$(grep '^api ' <<<"$out")" "present" "status api"
  assert_contains "$(grep '^portal ' <<<"$out")" "partial" "status portal"
  assert_contains "$(grep '^app ' <<<"$out")" "none" "status app"
}

t_check_skips_with_warning() {
  WS_T="$(mk_ws)"; echo x > "$WS_T/app/new.txt"; echo x > "$WS_T/api/new.txt"
  out="$(ws check)"; rc=$?
  assert_eq "$rc" 0 "exit"
  assert_contains "$out" "warn  app: harness none — gate skipped" "app warn"
  assert_contains "$out" "ok    api: check" "api ran"
}

t_no_writes_in_members() {
  WS_T="$(mk_ws)"; echo x > "$WS_T/app/new.txt"; echo x > "$WS_T/portal/new.txt"; echo x > "$WS_T/api/new.txt"
  sleep 1; touch "$WS_T/marker"; sleep 1
  ws status >/dev/null; ws lint >/dev/null || true; ws check >/dev/null; ws check-fast >/dev/null; ws claude-md >/dev/null; WSLOG="$WS_T/log" ws setup >/dev/null
  for m in portal app; do
    n="$(find "$WS_T/$m" -newer "$WS_T/marker" -not -name .git -not -path '*/.git/*' -not -path "$WS_T/$m" | wc -l | tr -d ' ')"
    assert_eq "$n" 0 "$m untouched"
  done
}

t_claude_md_imports_and_budget_fallback() {
  WS_T="$(mk_ws)"; ws claude-md >/dev/null
  c="$(cat "$WS_T/CLAUDE.md")"
  assert_contains "$c" "@AGENTS.md" "agents"; assert_contains "$c" "@INVARIANTS.md" "inv"
  assert_contains "$c" "@api/INVARIANTS.md" "api"; assert_not_contains "$c" "@portal/INVARIANTS.md" "portal not present"
  head -c 21000 /dev/zero | tr '\0' a > "$WS_T/api/INVARIANTS.md"
  out="$(ws claude-md 2>&1)"
  assert_contains "$out" "warn  member invariants exceed budget — linked from AGENTS.md instead" "warn"
  assert_not_contains "$(cat "$WS_T/CLAUDE.md")" "@api/INVARIANTS.md" "dropped"
  assert_contains "$(cat "$WS_T/CLAUDE.md")" "@INVARIANTS.md" "kept"
}

t_setup_merge_order() {
  WS_T="$(mk_ws)"; : > "$WS_T/log"
  # make portal present too, with its own setup; reverse the manifest order to prove mergeOrder rules
  echo "# inv" > "$WS_T/portal/INVARIANTS.md"
  printf 'check:\n\t@true\nsetup:\n\t@echo portal >> "$(WSLOG)"\n' > "$WS_T/portal/Makefile"
  sed -i.bak 's/"mergeOrder": \[.*\]/"mergeOrder": ["portal", "api", "app"]/' "$WS_T/harness-workspace.json"
  out="$(WSLOG="$WS_T/log" ws setup 2>&1)"; rc=$?
  assert_eq "$rc" 0 "exit"
  assert_eq "$(tr '\n' ' ' < "$WS_T/log")" "portal api " "order"
  assert_contains "$out" "warn  app: harness none" "app skipped"
  printf 'check:\n\t@true\nsetup:\n\t@exit 1\n' > "$WS_T/api/Makefile"
  rc=0; WSLOG="$WS_T/log" ws setup >/dev/null 2>&1 || rc=$?
  [ "$rc" != 0 ] || _fail "failing setup must exit non-zero"
}

t_missing_member_warns() {
  WS_T="$(mk_ws)"; rm -rf "$WS_T/portal"
  assert_contains "$(ws status)" "not checked out" "status"
  out="$(ws check)"; rc=$?; assert_eq "$rc" 0 "check exit"
  assert_contains "$out" "warn  portal: not checked out" "check warn"
  out="$(WSLOG="$WS_T/log" ws setup 2>&1)"; rc=$?; assert_eq "$rc" 0 "setup exit"
  assert_contains "$out" "warn  portal: not checked out" "setup warn"
}

t_fallback_without_resolver() {
  WS_T="$(mk_ws)"; rm -rf "$WS_T/scripts"
  assert_contains "$(ws state api)" "present" "make fallback"
}
