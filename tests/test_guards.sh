# Bash guard: feed a command, echo the guard's stdout (empty = allow).
guard() {
  python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$PWD" \
    | python3 "$PLUGIN/scripts/guard_bash.py"
}

t_claude_md_writes_denied() {
  local c
  for c in 'echo hi >> CLAUDE.md' 'curl -s https://x/y.md >>CLAUDE.md' 'curl -o CLAUDE.md https://x' \
           'cat a | tee -a sub/CLAUDE.md' 'cp /tmp/g.md CLAUDE.md' "sed -i '' s/a/b/ CLAUDE.md"; do
    assert_contains "$(guard "$c")" '"deny"' "deny: $c"
  done
}

t_claude_md_reads_allowed() {
  local c
  for c in 'cat CLAUDE.md' 'grep x CLAUDE.md > out.txt' 'git commit -m "edit CLAUDE.md >> later"'; do
    assert_eq "$(guard "$c")" "" "allow: $c"
  done
}

t_hookspath_githooks_allowed_only() {
  local c
  for c in 'git config core.hooksPath .githooks' 'git config --local core.hooksPath ./.githooks/' \
           'git config set core.hooksPath .githooks' 'git config core.hooksPath' 'git config --get core.hooksPath' \
           'git config get core.hooksPath' 'git config --local --get core.hooksPath'; do
    assert_eq "$(guard "$c")" "" "allow: $c"
  done
  for c in 'git config core.hooksPath /dev/null' 'git config --unset core.hooksPath' 'git config unset core.hooksPath' 'git config --unset-all core.hooksPath' \
           'git config --global --unset core.hooksPath' 'git config set core.hooksPath' 'git config unset core.hooksPath .githooks' \
           'git config --global core.hooksPath .githooks' 'git config core.hooksPath ../.githooks' \
           'git -c core.hooksPath=.githooks commit -m x' 'git -c core.hooksPath=/dev/null commit -m x'; do
    assert_contains "$(guard "$c")" '"deny"' "deny: $c"
  done
}
t_env_writes_via_bash_denied() {
  local c
  for c in 'printf "A=1\n" > .env' 'echo K=v >> .env.local' 'echo x > ".env"' 'cp prod.env .env' 'mv /tmp/e config/.env.production' \
           'cat x | tee .env' 'curl -o .env https://x' "sed -i '' s/a/b/ .env" 'bash -c "echo A=1 > .env"'; do
    assert_contains "$(guard "$c")" 'Writing to .env is blocked' "deny: $c"
  done
  for c in 'cat .env' 'cp .env.example .env.sample' 'echo A= > .env.example' 'echo x > .env.template' 'grep A .env > out.txt' \
           'git commit -m "write > .env later"' 'ls > .envrc.txt' 'echo ok >/dev/null 2>&1'; do
    assert_eq "$(guard "$c")" "" "allow: $c"
  done
}
t_indirect_shell_payloads_checked() {
  local c
  for c in 'bash -c "git push --force"' "sh -c 'git commit --no-verify -m x'" 'zsh -lc "git reset --hard"' \
           'eval "git push -f origin feat"' 'sudo bash -c "rm -rf /"' "bash -c \"sh -c 'git clean -fd'\"" \
           "sh -c 'echo hi >> CLAUDE.md'"; do
    assert_contains "$(guard "$c")" '"deny"' "deny: $c"
  done
  for c in 'bash -c "make check"' 'sh -c "echo --force"' 'bash script.sh -c' 'eval "$(ssh-agent -s)"'; do
    assert_eq "$(guard "$c")" "" "allow: $c"
  done
}
t_git_long_option_abbreviations() {
  local c
  for c in 'git commit --no-veri -m x' 'git push --no-ve' 'git push --forc origin feat' 'git push --for origin feat' \
           'git reset --har' 'git clean --forc' 'git branch --del --forc feat'; do
    assert_contains "$(guard "$c")" '"deny"' "deny: $c"
  done
  assert_contains "$(guard 'git push --force-w origin feat')" '"ask"' "force-with-lease abbreviation asks"
  for c in 'git push --follow-tags origin feat' 'git commit --no-edit -m x' 'git push --force-if-includes origin feat' \
           'git commit --verbose -m x' 'git branch --delete feat'; do
    assert_eq "$(guard "$c")" "" "allow: $c"
  done
}
t_infra_destroy_asks() {
  local c
  for c in 'kubectl delete pod x' 'kubectl -n prod delete deploy/api' 'terraform destroy' 'terraform -chdir=infra destroy -auto-approve' \
           'terraform apply -auto-approve' 'terraform apply --auto-approve=true' 'helm uninstall api' 'cd x && helm -n prod uninstall api' \
           'bash -c "kubectl delete ns dev"'; do
    assert_contains "$(guard "$c")" '"ask"' "ask: $c"
  done
  for c in 'kubectl get pods' 'kubectl logs delete-me' 'kubectl describe pod x' 'terraform plan' 'terraform apply' 'terraform apply plan.out' 'terraform apply -auto-approve=false' \
           'helm list' 'helm status api' 'grep "kubectl delete" notes.md' 'git commit -m "terraform destroy docs"'; do
    assert_eq "$(guard "$c")" "" "allow: $c"
  done
  assert_contains "$(guard 'kubectl delete pod x; git push --force')" '"deny"' "a deny later in the command still wins"
}
t_invariants_writes_via_bash_ask() {
  local c
  for c in 'echo "- rule" >> INVARIANTS.md' 'printf x > docs/../INVARIANTS.md' 'cat x | tee -a INVARIANTS.md' "sed -i '' s/a/b/ INVARIANTS.md" \
           'cp /tmp/i.md INVARIANTS.md' 'perl -pi -e s/a/b/ INVARIANTS.md'; do
    assert_contains "$(guard "$c")" '"ask"' "ask: $c"
  done
  for c in 'cat INVARIANTS.md' 'grep Severity INVARIANTS.md > out.txt' 'sed -n 1,5p INVARIANTS.md' 'git diff INVARIANTS.md' 'cp INVARIANTS.md /tmp/x'; do
    assert_eq "$(guard "$c")" "" "allow: $c"
  done
}

t_merge_of_red_implementer_branch_denied() {
  local d out; d="$(mktemp -d)"; ( cd "$d" && git init -q -b main ) >/dev/null
  mkdir -p "$d/.git/harness-red"; printf 'KEY-2-fee\t/wt/KEY-2\t2026-10-27\n' > "$d/.git/harness-red/KEY-2-fee"
  out="$(cd "$d" && guard 'git merge --no-ff KEY-2-fee -m "merge KEY-2"')"
  assert_contains "$out" '"deny"' "red branch merge denied"; assert_contains "$out" "/wt/KEY-2" "names worktree"
  assert_contains "$(cd "$d" && guard 'git cherry-pick main..KEY-2-fee')" '"deny"' "cherry-pick range denied"
  assert_eq "$(cd "$d" && guard 'git merge KEY-3-other')" "" "green branch allowed"
  rm "$d/.git/harness-red/KEY-2-fee"
  assert_eq "$(cd "$d" && guard 'git merge KEY-2-fee')" "" "allowed once cleared"
}
t_long_lived_dev_denied() {
  local d c; d="$(mktemp -d)"; cp "$PLUGIN/skills/harness-init/assets/harness.mk" "$d/"
  printf 'HARNESS_DEV = ./run-local.sh\nHARNESS_HEALTH = http://localhost:8080/health\nHARNESS_DEV_BLOCK = run-local.sh spring-boot:run\ninclude harness.mk\n' > "$d/Makefile"
  for c in 'make dev' "make dev ARGS='-P 9090' &" 'nohup make dev > x.log 2>&1 &' 'cd . && make -s dev' 'FOO=1 make dev' \
           "bash -c 'make dev'" './run-local.sh -d' 'bash run-local.sh' 'mvn -s settings.xml spring-boot:run'; do
    assert_contains "$(cd "$d" && guard "$c")" 'dev-check' "deny: $c"
  done
  for c in "make dev-check RUN='curl x'" 'make dev-stop' 'make check' 'grep run-local.sh Makefile' 'echo make dev' 'git diff Makefile'; do
    assert_eq "$(cd "$d" && guard "$c")" "" "allow: $c"
  done
  printf 'HARNESS_DEV = ./run-local.sh\ninclude harness.mk\n' > "$d/Makefile"
  assert_eq "$(cd "$d" && guard 'make dev')" "" "no HARNESS_HEALTH, so no dev-check: allowed"
  d="$(mktemp -d)"; assert_eq "$(cd "$d" && guard 'make dev')" "" "no harness: allowed"
}
t_make_variable_overrides_ask() {
  # an allowed `make <target>:*` rule would otherwise run any command put in a variable
  local c
  for c in "make test HARNESS_TEST_ONE='touch x'" "make check-fast HARNESS_BASE='x; touch y'" 'make test --eval=X' \
           'make -f /tmp/evil.mk test' 'HARNESS_TEST_CHANGED=evil make check-fast' 'MAKEFLAGS=-e make test' \
           "bash -c \"make test SHELL='/bin/sh -c id'\"" 'make test T:=x CC=y'; do
    assert_contains "$(guard "$c")" '"ask"' "ask: $c"
  done
  for c in 'make test' 'make test T=FooTest' 'make -s check-fast' 'make -C api test T=a.py' 'make -j4 check' 'echo HARNESS_X=1 make' "make dev-check RUN='curl x'"; do
    assert_eq "$(guard "$c")" "" "allow: $c"
  done
}
t_skip_hooks_set_any_way_denied() {
  # the hooks skip on SKIP_HOOKS=1 from the environment, however it got there
  local c
  for c in 'export SKIP_HOOKS=1 && git commit -m x' 'export SKIP_HOOKS=1; git push' 'env SKIP_HOOKS=1 git commit -m x' \
           'SKIP_HOOKS=1 git commit -m x' 'declare -x SKIP_HOOKS=1; git merge f' 'SKIP_HOOKS=1; export SKIP_HOOKS; git push' \
           'export SKIP_HOOKS=1' 'SKIP_HOOKS=1 make release' 'export HUSKY=0 && git commit -m x' 'export SKIP=lint; git commit -m x'; do
    assert_contains "$(guard "$c")" '"deny"' "deny: $c"
  done
  for c in 'git commit -m "export SKIP_HOOKS=1 is refused"' 'echo SKIP_HOOKS' 'grep -rn SKIP_HOOKS= scripts' 'export FOO=1; git status'; do
    assert_eq "$(guard "$c")" "" "allow: $c"
  done
}
t_guard_fails_closed_on_internal_error() {
  # a parser crash must not turn into "allow": the command could be anything
  local out
  out="$(printf '{"tool_input":{"command":"git push"},"cwd":"/"}' | python3 -c '
import runpy, shlex, sys
def boom(*a, **k): raise RuntimeError("boom")
shlex.shlex = boom
runpy.run_path(sys.argv[1], run_name="__main__")' "$PLUGIN/scripts/guard_bash.py" 2>/dev/null)" || true
  assert_contains "$out" '"ask"' "an internal error asks instead of allowing"
}
# File guard: fguard <file> <content> (Write) or fguard <file> <old> <new> (Edit); echoes its stdout (empty = allow)
fguard() {
  python3 -c 'import json,sys
a=sys.argv[1:]; ti={"file_path":a[0]}
if len(a)==2: ti["content"]=a[1]
else: ti["old_string"],ti["new_string"]=a[1],a[2]
print(json.dumps({"cwd":"/","tool_input":ti}))' "$@" | bash "$PLUGIN/scripts/guard-files.sh"
}
t_init_state_gate_cannot_be_switched_off() {
  # the git hooks skip while init-state.json lacks "gate_wired": true; once wired, an agent must not unwire it
  local d f out; d="$(mktemp -d)"; mkdir "$d/.harness"; f="$d/.harness/init-state.json"
  out="$(fguard "$f" '{"gate_wired": false}')"; assert_eq "$out" "" "fresh setup may write it"
  printf '{"layers_done": ["guides"], "gate_wired": false}\n' > "$f"
  out="$(fguard "$f" '{"gate_wired": true}')"; assert_eq "$out" "" "init may wire the gate"
  printf '{\n  "layers_done": ["guides"],\n  "gate_wired": true\n}\n' > "$f"
  out="$(fguard "$f" '{}')"; assert_contains "$out" '"deny"' "Write {} over a wired gate"
  out="$(fguard "$f" '"gate_wired": true' '"gate_wired": false')"; assert_contains "$out" '"deny"' "Edit unwires"
  out="$(fguard "$f" '["guides"]' '["guides", "tools"]')"; assert_eq "$out" "" "other keys may change"
  ( cd "$d" && git init -q )
  local c
  for c in "echo '{}' > .harness/init-state.json" "printf x | tee .harness/init-state.json" "sed -i '' s/true/false/ .harness/init-state.json" \
           "cp /tmp/x .harness/init-state.json"; do
    assert_contains "$(cd "$d" && guard "$c")" '"deny"' "deny: $c"
  done
  assert_contains "$(cd "$d" && guard "python3 -c \"open('.harness/init-state.json','w').write('{}')\"")" '"ask"' "inline write asks"
  assert_eq "$(cd "$d" && guard 'cat .harness/init-state.json')" "" "reading is fine"
  printf '{"gate_wired": false}\n' > "$f"
  assert_eq "$(cd "$d" && guard "echo '{}' > .harness/init-state.json")" "" "not wired yet: nothing to protect"
}
t_init_state_reads_allowed() {
  # reading a wired gate's state is ordinary; only a write to the file is refused, and a guessed one only asks
  local d c; d="$(mktemp -d)"; mkdir "$d/.harness"; ( cd "$d" && git init -q ); echo '{"gate_wired": true}' > "$d/.harness/init-state.json"
  for c in 'jq .gate_wired .harness/init-state.json 2>/dev/null' 'cat .harness/init-state.json | jq . 2>&1' \
           'jq -r .gate_wired .harness/init-state.json > /tmp/out' \
           "python3 -c \"import json; print(json.dumps(json.load(open('.harness/init-state.json'))))\""; do
    assert_eq "$(cd "$d" && guard "$c")" "" "allow: $c"
  done
  assert_contains "$(cd "$d" && guard "node -e \"require('fs').writeFileSync('.harness/init-state.json','{}')\"")" '"ask"' "inline write asks"
}
t_init_state_bypasses_closed() {
  # the hooks read gate_wired with a line grep: a guard that parses JSON, or ignores a cd, lets an agent unwire them
  local d f; d="$(mktemp -d)"; mkdir "$d/.harness"; f="$d/.harness/init-state.json"; ( cd "$d" && git init -q )
  echo '{"gate_wired": true}' > "$f"
  assert_contains "$(fguard "$f" "$(printf '{"gate_wired":\n true}')")" '"deny"' "Write the hooks' grep reads as unwired"
  assert_eq "$(fguard "$f" '{"gate_wired": true, "layers_done": []}')" "" "a Write that keeps it wired"
  assert_contains "$(cd "$d" && guard "cd .harness && echo '{}' > init-state.json")" '"deny"' "write after cd"
  assert_contains "$(cd "$d" && guard 'f=.harness/init-state.json; echo "{}" > $f')" '"ask"' "write through a variable"
  assert_contains "$(cd "$d" && guard 'echo e30= | base64 -d > .harness/init-stat?.json')" '"ask"' "write through a glob"
  assert_eq "$(cd "$d" && guard 'npm test > $LOG 2>&1')" "" "an unrelated variable target"
}
t_hooks_off_prefix_on_other_command_allowed() {
  # HUSKY=0 / SKIP=x before npm only affects npm; a later git in the same line still runs its hooks
  local c
  for c in 'HUSKY=0 npm ci && git status' 'SKIP=flake8 npm run lint; git diff'; do assert_eq "$(guard "$c")" "" "allow: $c"; done
  for c in 'HUSKY=0 git commit -m x' 'npm ci && HUSKY=0 git push' 'SKIP=lint git commit -m x' 'HUSKY=0; git commit -m x'; do
    assert_contains "$(guard "$c")" '"deny"' "deny: $c"
  done
}
t_bash_guard_without_python3_asks_for_risky() {
  # no python3 (and an empty PATH): commands the guard exists for must ask, not pass, and the session is told once
  local bin t out sid c; bin="$(mktemp -d)"; t="$(mktemp -d)"; sid="nopy-$$-$RANDOM"
  _nopy() { python3 -c 'import json,sys;print(json.dumps({"session_id":sys.argv[2],"tool_input":{"command":sys.argv[1]},"cwd":"/"}))' "$1" "$sid" \
    | PATH="$bin" TMPDIR="$t" /bin/bash "$PLUGIN/scripts/guard-bash.sh"; }
  out="$(_nopy 'ls -la')"; assert_contains "$out" "python3 not found" "told once"; assert_not_contains "$out" '"ask"' "ls allowed"
  assert_eq "$(_nopy 'npm test')" "" "allowed, not told again"
  for c in 'git push --no-verify' 'SKIP_HOOKS=1 git commit -m x' 'git push -f origin main' 'rm -rf build' \
           "echo '{}' > .harness/init-state.json" 'git reset --hard HEAD~3' 'psql -c "DROP TABLE users"'; do
    assert_contains "$(_nopy "$c")" '"ask"' "asks: $c"
  done
  for c in 'git status' 'git log --oneline' 'git diff' 'make check-fast'; do assert_eq "$(_nopy "$c")" "" "allow: $c"; done
}
t_file_guard_without_python3_asks_for_protected() {
  # no python3: the file guard can't parse its input; a write to a file it protects asks instead of passing
  local bin f; bin="$(mktemp -d)"; ln -s "$(command -v cat)" "$bin/cat"; ln -s "$(command -v dirname)" "$bin/dirname"
  _nopyf() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$1" | PATH="$bin" /bin/bash "$PLUGIN/scripts/guard-files.sh"; }
  for f in /r/.env /r/.env.local /r/CLAUDE.md /r/INVARIANTS.md /r/.harness/init-state.json; do
    assert_contains "$(_nopyf "$f")" '"ask"' "asks: $f"
  done
  assert_eq "$(_nopyf /r/src/app.py)" "" "other files allowed"
}
t_init_state_script_file_asks() {
  # a script file that names init-state.json may unwire the gate: running it asks once the gate is wired
  local d c; d="$(mktemp -d)"; mkdir -p "$d/.harness" "$d/scripts/harness"; ( cd "$d" && git init -q )
  echo '{"gate_wired": true}' > "$d/.harness/init-state.json"
  printf '#!/bin/sh\necho {} > .harness/init-state.json\n' > "$d/fix.sh"; chmod +x "$d/fix.sh"
  printf 'open(".harness/init-state.json", "w").write("{}")\n' > "$d/tool.py"; printf 'echo hi\n' > "$d/other.sh"
  printf 'f=.harness/init-state.json\n' > "$d/scripts/harness/gate-proof.sh"
  for c in 'bash fix.sh' './fix.sh' 'sh ./fix.sh arg' 'python3 tool.py' 'cd . && bash fix.sh'; do
    assert_contains "$(cd "$d" && guard "$c")" '"ask"' "asks: $c"
  done
  for c in 'bash other.sh' 'bash scripts/harness/gate-proof.sh' 'python3 -c "print(1)"' 'bash -c "echo hi"'; do
    assert_eq "$(cd "$d" && guard "$c")" "" "allow: $c"
  done
  echo '{"gate_wired": false}' > "$d/.harness/init-state.json"
  assert_eq "$(cd "$d" && guard 'bash fix.sh')" "" "not wired yet: nothing to protect"
}
