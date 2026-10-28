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
