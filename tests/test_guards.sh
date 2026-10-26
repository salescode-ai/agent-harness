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
