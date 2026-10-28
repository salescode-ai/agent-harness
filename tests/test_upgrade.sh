MIG="$PLUGIN/scripts/migrate.py"
_sum() { (cd "$1" && find . -path ./.git -prune -o -type f -print | sort | xargs shasum | shasum); }
_fx() { # _fx <fixture>: mk_repo plus the gitignored .harness/init-state.json that release shape had
  local d; d="$(mk_repo "$1")"; mkdir -p "$d/.harness"
  case "$1" in
    harness-2.0.0) echo '{"layers_done": ["guides", "sensors", "tools", "context", "observability"], "answers": {}}' ;;
    *) echo '{"layers_done": ["guides", "sensors"], "answers": {}, "target": "Functional", "gate_wired": true}' ;;
  esac > "$d/.harness/init-state.json"
  echo "$d"
}
_upgraded() { # _upgraded <fixture>: repo after assets install + auto migrations; echoes path
  local d; d="$(_fx "$1")"
  python3 "$ASSETS_PY" install "$d" >/dev/null; python3 "$MIG" apply "$d" >/dev/null; echo "$d"
}
ASSETS_PY="$PLUGIN/scripts/assets.py"

t_upgrade_2_0_0_repo() {
  local d out before; d="$(_fx harness-2.0.0)"
  before="$(cat "$d/AGENTS.md")"
  out="$(python3 "$MIG" status "$d")"
  assert_contains "$out" "plugin: recorded unknown (before 2.0.2)" "version line"
  for m in "auto     templates" "propose  plan-ticket" "propose  decisions-ticket" "propose  agents-verification" \
           "propose  agents-done-fresh" "propose  agents-parallel" "propose  invariants-red-proof" "propose  env-deny" "propose  harness-base" "auto     init-state-target" "manual   check-fast-tests" \
           "manual   tool-wiring" "manual   gate-wired"; do assert_contains "$out" "$m" "2.0.0 needs $m"; done
  python3 "$ASSETS_PY" install "$d" >/dev/null
  assert_not_contains "$(python3 "$MIG" status "$d")" "harness-mk-test-plan" "refreshed harness.mk has the target"
  out="$(python3 "$MIG" apply "$d")"
  assert_contains "$out" "applied  docs/plans/TEMPLATE.md" "unedited template replaced"
  cmp -s "$d/docs/plans/TEMPLATE.md" "$PLUGIN/skills/harness-init/assets/docs/plans/TEMPLATE.md" || _fail "template current"
  assert_contains "$(cat "$d/.harness/init-state.json")" '"target": "Robust"' "target copied"
  assert_eq "$(cat "$d/AGENTS.md")" "$before" "apply never touches repo-owned files"
  local s; s="$(_sum "$d")"; out="$(python3 "$MIG" diff "$d")"
  assert_eq "$(_sum "$d")" "$s" "diff writes nothing"
  assert_eq "$(grep -c '^--- a/' <<<"$out")" 6 "one diff over six repo-owned files (INVARIANTS.md since 2.0.8)"
  assert_contains "$out" "+**Status**: active · **Owner**: dev · **Spec**: none · **Ticket**: none (no ticket recorded before 2.0.4)" "inline placeholder replaced"
  assert_contains "$out" "+HARNESS_BASE = origin/main" "derived base"
  assert_contains "$out" '"Read(./**/.env.local)"' "narrowed deny"
  python3 "$MIG" accept "$d" >/dev/null
  (cd "$d" && bash scripts/harness/plan-check.sh ticket docs/plans/active/2026-01-05-login.md) || _fail "accepted ticket passes"
  grep -qF -- '- Done = `make check` passes' "$d/AGENTS.md" || _fail "short Verification"
  awk '/^## Verification/{f=1;next} /^## /{f=0} f' "$d/AGENTS.md" | grep -qF 'done only after harness-verify recorded a fresh PASS (`scripts/harness/plan-check.sh fresh`)' \
    || _fail "Verification gains the fresh-PASS line"
  # idempotent: nothing left but the manual items
  assert_contains "$(python3 "$MIG" apply "$d")" "migrations: 0 file(s) applied" "second apply"
  assert_eq "$(python3 "$MIG" diff "$d")" "" "second diff empty"
  out="$(python3 "$MIG" status "$d")"; assert_not_contains "$out" "auto " "no auto left"; assert_not_contains "$out" "propose " "no propose left"
}
t_upgrade_2_0_3_repo_runner_and_edited_template() {
  local d out; d="$(_upgraded harness-2.0.3)"
  out="$(python3 "$MIG" diff "$d")"
  assert_contains "$out" '+- Done = `just check` passes (**harness-verify** before claiming done). Fast loop: `just check-fast`, `just test <path>`. All commands: `just --list`.' "runner equivalents"
  assert_contains "$out" '+  "help": "just --list",' "help recorded"
  assert_contains "$out" "+**Ticket**: SHOP-12" "key from the file name"
  assert_contains "$out" '+**Evidence**: local `.harness/evidence/<this file name>`' "edited template gains Evidence"
  python3 "$MIG" accept "$d" --skip decisions-ticket >/dev/null
  grep -q '## Rollback' "$d/docs/plans/TEMPLATE.md" || _fail "human section kept"
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$d/.agents/harness.json" || _fail "harness.json still JSON"
  assert_contains "$(python3 "$MIG" status "$d")" "propose  decisions-ticket" "skipped stays proposed"
  python3 "$MIG" accept "$d" >/dev/null
  assert_eq "$(python3 "$MIG" diff "$d")" "" "second diff empty"
  assert_contains "$(python3 "$MIG" status "$d")" "manual   gate-red" "gate never proven red"
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["gate_red_proven"]=True; open(p,"w").write(json.dumps(d))' "$d/.harness/init-state.json"  # what gate-proof.sh records
  assert_contains "$(python3 "$MIG" status "$d")" "migrations: 0 needed" "nothing left"
  assert_contains "$(cat "$d/scripts/harness/assets.json")" "\"plugin\": \"$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN/.claude-plugin/plugin.json")\"" "version recorded"
}
t_upgrade_leaves_human_edits() {
  local d out; d="$(_fx harness-2.0.0)"
  printf '# mine\n' >> "$d/harness.mk"; sed -i.bak 's/^- While iterating:.*/- While iterating: run my script./' "$d/AGENTS.md"; rm "$d/AGENTS.md.bak"
  python3 "$ASSETS_PY" install "$d" >/dev/null
  grep -q '# mine' "$d/harness.mk" || _fail "modified harness.mk overwritten"
  out="$(python3 "$MIG" status "$d")"
  assert_contains "$out" "manual   harness-mk-test-plan" "modified harness.mk: merge by hand"
  assert_contains "$out" "manual   agents-verification" "edited long form is not rewritten"
  python3 "$MIG" apply "$d" >/dev/null; python3 "$MIG" accept "$d" >/dev/null
  grep -q 'run my script' "$d/AGENTS.md" || _fail "human Verification line kept"
}
t_upgrade_plan_verification_empty_only() {
  local d; d="$(_upgraded harness-2.0.3)"; python3 "$MIG" accept "$d" >/dev/null
  local dev; dev="$(git -C "$ROOT" show 2ca43c7:plugins/agent-harness/skills/harness-init/assets/docs/plans/TEMPLATE.md 2>/dev/null)" || skip upgrade_dev "no git history"
  printf '%s\n' "$dev" | sed 's/^\*\*Ticket\*\*: .*/**Ticket**: #1/' > "$d/docs/plans/active/a.md"
  { printf '%s\n' "$dev" | sed 's/^\*\*Ticket\*\*: .*/**Ticket**: #2/'; printf '### 2026-10-27 · abc · PASS\n'; } > "$d/docs/plans/active/b.md"
  python3 "$MIG" accept "$d" >/dev/null
  grep -q '^## Verification' "$d/docs/plans/active/a.md" && _fail "empty section left"
  grep -q '^## Verification' "$d/docs/plans/active/b.md" || _fail "section with entries removed"
  assert_eq "$(python3 "$MIG" diff "$d")" "" "idempotent"
}
t_upgrade_workspace_lists_members_never_writes_them() {
  local w m out s; w="$(mktemp -d)"; m="$(_fx harness-2.0.0)"; mv "$m" "$w/api"
  printf '{"repos":[{"name":"api","path":"api"}]}\n' > "$w/harness-workspace.json"
  git -C "$ROOT" show 435c341:plugins/agent-harness/skills/harness-workspace/assets/AGENTS.md > "$w/AGENTS.md" 2>/dev/null || skip upgrade_ws "no git history"
  s="$(_sum "$w/api")"
  out="$(python3 "$MIG" status "$w")"
  assert_contains "$out" "member    api: plugin unknown (before 2.0.2)" "member listed"
  assert_contains "$out" "— run /agent-harness:harness-upgrade api" "exact command"
  assert_contains "$out" "auto     templates (2.0.4, context) plans/TEMPLATE.md" "workspace template"
  assert_contains "$out" "propose  agents-verification" "workspace AGENTS.md"
  python3 "$ASSETS_PY" install "$w" >/dev/null; python3 "$MIG" apply "$w" >/dev/null; python3 "$MIG" accept "$w" >/dev/null
  grep -qF 'Done = `make check` passes here' "$w/AGENTS.md" || _fail "workspace short form"
  [ -f "$w/scripts/harness/plan-check.sh" ] || _fail "workspace plan-check installed"
  assert_eq "$(_sum "$w/api")" "$s" "member untouched"
}
t_upgrade_and_improve_skills() {
  local u="$PLUGIN/skills/harness-upgrade/SKILL.md" i="$PLUGIN/skills/harness-improve/SKILL.md" m
  grep -q '^disable-model-invocation: true' "$u" || _fail "upgrade is user-invoked"
  if grep -q '^disable-model-invocation' "$i"; then _fail "improve must be model-invocable"; fi
  for m in 'migrate.py" status .' 'migrate.py diff .' 'migrate.py accept .' 'assets.py install .' 'ONE unified diff' \
           'Never overwrite human content' 'never write into a member' '/agent-harness:harness-upgrade <name>' \
           'level.py" . --json --run-checks --log' '"gate_wired": true' 'second run must show nothing'; do
    grep -qF -- "$m" "$u" || _fail "upgrade SKILL.md missing '$m'"
  done
  for m in '**Never invent.**' 'cites its evidence' 'At most 5 numbered questions' '➡️' '"defaults" accepts' 'sensor-smith' \
           '**One owner per fact**' 'Team rollout settings missing' 'Before → after' 'level.py" . --json --run-checks --log'; do
    grep -qF -- "$m" "$i" || _fail "improve SKILL.md missing '$m'"
  done
  grep -qF 'enabledPlugins["agent-harness@agent-harness"]' "$i" || _fail "improve: rollout pin check"
  for f in "$PLUGIN/skills/harness-init/SKILL.md" "$PLUGIN/skills/harness-audit/SKILL.md"; do
    grep -qF 'Run /agent-harness:harness-improve to strengthen <top 3 gaps' "$f" || _fail "$f: improve hand-off"
    grep -qF 'whether to start harness-improve now' "$f" || _fail "$f: ask to start now"
  done
  grep -qF 'skills/harness-upgrade/SKILL.md' "$PLUGIN/skills/harness-init/SKILL.md" || _fail "init hands over to upgrade"
  grep -qF 'run /agent-harness:harness-upgrade' "$PLUGIN/scripts/session-context.sh" || _fail "session stale line"
  for m in '/agent-harness:harness-upgrade' '/agent-harness:harness-improve'; do
    grep -qF "$m" "$ROOT/README.md" || _fail "README: $m"; grep -qF "$m" "$ROOT/docs/manual/03-user-guide.md" || _fail "manual: $m"
  done
  python3 - "$PLUGIN" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[1] + "/scripts"); sys.dont_write_bytecode = True; import migrate
doc = open(sys.argv[1] + "/skills/harness-upgrade/references/migrations.md").read()
miss = [m[0] for m in migrate.MIGRATIONS if "`%s`" % m[0] not in doc]
assert not miss, "migrations.md lacks %s" % miss
PY
}
t_upgrade_keeps_valid_ticket_forms() {
  local d t; d="$(_upgraded harness-2.0.3)"; python3 "$MIG" accept "$d" >/dev/null
  for t in '[SHOP-12](https://x.atlassian.net/browse/SHOP-12)' 'SHOP-12, SHOP-13' 'https://github.com/o/r/issues/5' '#5 (gh)'; do
    printf '# Plan: x\n\n**Status**: active\n**Ticket**: %s\n%s\n' "$t" '**Evidence**: local `.harness/evidence/<this file name>` (never committed; shared via the PR description and the tracker comment)' > "$d/docs/plans/active/x.md"
    assert_not_contains "$(python3 "$MIG" status "$d")" "plan-ticket" "valid ticket left alone: $t"
  done
}
t_upgrade_one_shot_banner_template_is_unedited() {
  local d; d="$(_fx harness-2.0.0)"
  { echo '<!-- generated in one pass: verify before trusting -->'; cat "$d/docs/plans/TEMPLATE.md"; } > "$d/t" && mv "$d/t" "$d/docs/plans/TEMPLATE.md"
  assert_contains "$(python3 "$MIG" status "$d")" "auto     templates (2.0.4, context) docs/plans/TEMPLATE.md" "banner ignored when hashing"
}

t_upgrade_agents_parallel_once() {
  local d out; d="$(_fx harness-2.0.0)"; mkdir -p "$d/.agents"
  echo '{"runner":"just","commands":{"check":"just check","check-fast":"just quick","test":"just test {T}","setup":"just bootstrap"}}' > "$d/.agents/harness.json"
  out="$(python3 "$MIG" status "$d")"
  assert_contains "$out" "agents-parallel" "proposed"
  python3 "$MIG" apply "$d" >/dev/null; python3 "$MIG" accept "$d" >/dev/null
  grep -q "Parallel or spec-driven flows" "$d/AGENTS.md" || _fail "rule added"
  bash "$PLUGIN/skills/harness-init/assets/lint.sh" "$d" 2>&1 | grep -q "names 'make setup'" && _fail "no runner mismatch"
  assert_not_contains "$(python3 "$MIG" status "$d")" "agents-parallel" "idempotent"
}

t_upgrade_dev_health_manual() {
  local d; d="$(_upgraded harness-2.0.0)"
  assert_not_contains "$(python3 "$MIG" status "$d")" "dev-health" "no HARNESS_DEV: nothing to do"
  printf 'HARNESS_DEV = ./run-local.sh\n%s' "$(cat "$d/Makefile")" > "$d/Makefile"
  assert_contains "$(python3 "$MIG" status "$d")" "manual   dev-health" "HARNESS_DEV without HARNESS_HEALTH"
  printf 'HARNESS_HEALTH = http://localhost:8080/health\n%s' "$(cat "$d/Makefile")" > "$d/Makefile"
  assert_not_contains "$(python3 "$MIG" status "$d")" "dev-health" "set: done"
}
t_upgrade_invariants_red_proof_once() {
  local d; d="$(_fx harness-2.0.0)"
  python3 "$MIG" apply "$d" >/dev/null; python3 "$MIG" accept "$d" >/dev/null
  awk '/^## Testing/{f=1;next} /^## /{f=0} f' "$d/INVARIANTS.md" | grep -q "red-proof.sh" || _fail "rule under Testing"
  assert_not_contains "$(python3 "$MIG" status "$d")" "invariants-red-proof" "idempotent"
  ( cd "$d" && bash "$PLUGIN/skills/harness-init/assets/lint.sh" ) 2>&1 | grep -q "Red\|red-proof.*FAIL" && _fail "rule lints clean"
  true
}

t_upgrade_test_exit_swallowed_manual() {
  local d; d="$(_upgraded harness-2.0.0)"
  assert_not_contains "$(python3 "$MIG" status "$d")" "test-exit-swallowed" "nothing swallowed"
  printf 'HARNESS_TEST_ONE = mvn -q test \\\n  -Dtest=$(T); :\n%s' "$(cat "$d/Makefile")" > "$d/Makefile"
  assert_contains "$(python3 "$MIG" status "$d")" "manual   test-exit-swallowed (2.0.10, sensors) Makefile — HARNESS_TEST_ONE ends in" "continued value ending in ; :"
  sed -i.bak 's/; :$/ \&\& :/' "$d/Makefile"
  assert_not_contains "$(python3 "$MIG" status "$d")" "test-exit-swallowed" "&& : fixes it"
}
t_upgrade_gate_red_reason_shown() {
  local d; d="$(_upgraded harness-2.0.0)"
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.update(gate_red_proven=False, gate_red_reason="NOT proven (x)"); open(p,"w").write(json.dumps(d))' "$d/.harness/init-state.json"
  assert_contains "$(python3 "$MIG" status "$d")" "gate never proven red (NOT proven (x))" "reason carried"
}
t_upgrade_hand_rolled_diff_sensor_manual() {
  local d; d="$(_upgraded harness-2.0.0)"
  assert_not_contains "$(python3 "$MIG" status "$d")" "diff-sensors" "no diff sensors"
  printf '#!/usr/bin/env bash\ngit diff -U0 "$HARNESS_BASE"...HEAD | grep "^+.*password"\n' > "$d/scripts/harness/sensors/no-pw.sh"
  assert_contains "$(python3 "$MIG" status "$d")" "manual   diff-sensors (2.0.10, sensors) scripts/harness/sensors/no-pw.sh — parses git diff itself" "hand-rolled parser flagged"
  printf '#!/usr/bin/env bash\npython3 scripts/harness/sensors/lib/diffscan.py | grep password\n' > "$d/scripts/harness/sensors/no-pw.sh"
  assert_not_contains "$(python3 "$MIG" status "$d")" "diff-sensors" "diffscan-based sensor is fine"
}
t_upgrade_make_args_literal() {
  local w out; w="$(mktemp -d)"; printf '{"repos":[]}\n' > "$w/harness-workspace.json"
  git -C "$ROOT" show v2.0.10:plugins/agent-harness/skills/harness-workspace/assets/Makefile > "$w/Makefile" 2>/dev/null || skip upgrade_ws "no git history"
  assert_contains "$(python3 "$MIG" status "$w")" "auto     make-args-literal (2.0.11, tools) Makefile" "workspace Makefile fixed automatically"
  python3 "$MIG" apply "$w" >/dev/null
  assert_eq "$(cat "$w/Makefile")" "$(cat "$PLUGIN/skills/harness-workspace/assets/Makefile")" "same as the current template"
  assert_not_contains "$(python3 "$MIG" status "$w")" "make-args-literal" "once"
  printf 'x:\n\t@bash ws.sh test $(R) $(T) --mine\n' > "$w/Makefile"
  assert_contains "$(python3 "$MIG" status "$w")" "manual   make-args-literal (2.0.11, tools) Makefile" "edited: manual"
  local d; d="$(_upgraded harness-2.0.0)"
  assert_not_contains "$(python3 "$MIG" status "$d")" "make-args-literal" "refreshed harness.mk is fine"
  sed -i.bak '/^override T := /d' "$d/harness.mk"
  assert_contains "$(python3 "$MIG" status "$d")" "manual   make-args-literal (2.0.11, tools) harness.mk" "modified harness.mk: manual"
}
