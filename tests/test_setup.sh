S="$PLUGIN/skills/harness-init/assets/harness"
# _su <extra-makefile-text>: committed repo "node-app" with setup.sh, cmd.sh, fake setup-* recipes; echoes path
_su() {
  local p d; p="$(mktemp -d)"; d="$p/node-app"; mkdir "$d"; cp -R "$FIXTURES/node-app/." "$d/"
  mkdir -p "$d/scripts/harness"
  cp "$S/setup.sh" "$S/setup-proof.sh" "$d/scripts/harness/"; cp "$PLUGIN/scripts/harness-cmd.sh" "$d/scripts/harness/cmd.sh"
  rm -f "$d/docker-compose.yml"
  printf 'setup:\n\tbash scripts/harness/setup.sh\n%s\n' "${1:-}" > "$d/Makefile"
  ( cd "$d" && git init -q -b main && git config user.email t@e.com && git config user.name t && git add -A \
    && git -c core.hooksPath=/dev/null commit -q -m init ) >/dev/null
  echo "$d"
}
_run() { ( cd "$1" && make -s setup 2>&1 ); }

t_env_created_not_overwritten() {
  local d; d="$(_su)"; printf 'A=1\nSTRIPE_KEY=\n' > "$d/.env.example"
  _run "$d" >/dev/null
  assert_eq "$(cat "$d/.env")" "$(cat "$d/.env.example")" "copied"
  echo "A=mine" > "$d/.env"; _run "$d" >/dev/null
  assert_eq "$(cat "$d/.env")" "A=mine" "not overwritten"
}
t_worktree_project_name() {
  local d w; d="$(_su)"; w="$(dirname "$d")/feat x"
  ( cd "$d" && git worktree add -q "$w" -b feat ) >/dev/null 2>&1
  printf 'API_PORT=\n' > "$w/.env.example"
  out="$(_run "$w")"
  assert_contains "$(cat "$w/.env.local")" "COMPOSE_PROJECT_NAME=node-app-feat-x" "slug"
  assert_contains "$out" "worktree feat-x" "report"
}
t_ports_unique_and_free() {
  local d a b; d="$(_su)"; printf 'API_PORT=3000\nDB_PORT=5432\nDB_NAME=shop\n' > "$d/.env.example"
  _run "$d" >/dev/null
  a="$(sed -n 's/^API_PORT=//p' "$d/.env.local")"; b="$(sed -n 's/^DB_PORT=//p' "$d/.env.local")"
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ]
  assert_contains "$(cat "$d/.env.local")" "DB_NAME=shop_node_app" "db name"
  python3 -c "import socket,sys
for p in sys.argv[1:]:
    s=socket.socket(); s.bind(('',int(p))); s.close()" "$a" "$b"
  _run "$d" >/dev/null   # stable on re-run
  assert_eq "$(sed -n 's/^API_PORT=//p' "$d/.env.local")" "$a" "port kept"
}
t_needs_you_listed() {
  local d out; d="$(_su)"; printf 'STRIPE_KEY=\nTOKEN=changeme\nFINE=1\n' > "$d/.env.example"
  out="$(_run "$d")"; assert_contains "$out" "STRIPE_KEY, TOKEN" "list"
  assert_not_contains "$out" "FINE" "only blanks"
}
t_missing_step_skipped() {
  local d out; d="$(_su 'setup-deps:
	@echo deps')"
  out="$(_run "$d")"; assert_contains "$out" "setup: OK" "ok"
  assert_contains "$out" "deps ✓" "ran"; assert_contains "$out" "migrate skipped" "skipped"
}
t_required_failure_exit1() {
  local d out; d="$(_su 'setup-migrate:
	@false')"
  out="$(_run "$d")" && return 1
  assert_contains "$out" "setup: FAIL" "fail"; assert_contains "$out" "migrate ✗" "named"
}
t_shared_services_flag() {
  local d; d="$(_su)"; printf 'API_PORT=1\nDB_NAME=x\n' > "$d/.env.example"
  printf 'HARNESS_SHARED_SERVICES=1\nMINE=keep\n' > "$d/.env.local"
  _run "$d" >/dev/null
  assert_eq "$(sort "$d/.env.local" | tr '\n' ' ')" "HARNESS_SHARED_SERVICES=1 MINE=keep " "only unmanaged"
}
t_env_local_preserves_unmanaged() {
  local d; d="$(_su)"; printf 'API_PORT=1\n' > "$d/.env.example"; printf 'MINE=keep\nCOMPOSE_PROJECT_NAME=old\n' > "$d/.env.local"
  _run "$d" >/dev/null
  assert_contains "$(cat "$d/.env.local")" "MINE=keep" "kept"
  assert_not_contains "$(cat "$d/.env.local")" "=old" "managed rewritten"
}
t_compose_default_uses_docker_shim() {
  local d bin; d="$(_su)"; bin="$(mktemp -d)"; cp "$FIXTURES/node-app/docker-compose.yml" "$d/"
  printf '#!/bin/sh\necho "$@" >> "%s/args"\n' "$bin" > "$bin/docker"; chmod +x "$bin/docker"
  ( cd "$d" && PATH="$bin:$PATH" make -s setup ) >/dev/null 2>&1
  assert_contains "$(cat "$bin/args")" "compose -f docker-compose.yml -p node-app up -d" "args"
  printf 'HARNESS_SHARED_SERVICES=1\n' > "$d/.env.local"; rm "$bin/args"
  ( cd "$d" && PATH="$bin:$PATH" make -s setup ) >/dev/null 2>&1
  assert_not_contains "$(cat "$bin/args")" " -p " "shared: no project name"
}
t_githooks_dir() {
  local d; d="$(_su)"; mkdir "$d/.githooks"
  _run "$d" >/dev/null
  assert_eq "$(git -C "$d" config core.hooksPath)" ".githooks" "hooksPath"
}
t_proof_runs_in_fresh_clone() {
  local d tmp out; d="$(_su 'setup-deps:
	@echo $$PWD > $(PROOF_OUT)')"; tmp="$(mktemp -d)"
  out="$(cd "$d" && PROOF_OUT="$tmp/where" TMPDIR="$tmp" bash scripts/harness/setup-proof.sh 2>&1)"
  assert_contains "$out" "setup-proof: OK" "ok"
  case "$(cat "$tmp/where")" in "$tmp"/*|"${tmp%/}"/*) ;; *) _fail "ran in $(cat "$tmp/where")";; esac
  [ ! -d "$(cat "$tmp/where")" ] || _fail "tmp not removed"
}
t_proof_fail_names_step() {
  local d out; d="$(_su 'setup-migrate:
	@false')"
  out="$(cd "$d" && bash scripts/harness/setup-proof.sh 2>&1)" && return 1
  assert_contains "$out" "setup-proof: FAIL (migrate)" "step"
}
t_proof_skipped_without_docker() {
  local d out; d="$(_su)"; cp "$FIXTURES/node-app/docker-compose.yml" "$d/"
  ( cd "$d" && git add -A && git -c core.hooksPath=/dev/null commit -qm c ) >/dev/null
  out="$(cd "$d" && PATH="/usr/bin:/bin" bash scripts/harness/setup-proof.sh 2>&1)"
  assert_contains "$out" "SKIPPED (docker not available)" "skip"
}
