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
