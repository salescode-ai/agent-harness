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
  local m d a b; m="$(_su)"; d="$(dirname "$m")/wt"
  printf 'API_PORT=3000\nDB_PORT=5432\nDB_NAME=shop\n' > "$m/.env.example"
  ( cd "$m" && git add -A && git -c core.hooksPath=/dev/null commit -qm e && git worktree add -q "$d" -b wt ) >/dev/null 2>&1
  _run "$d" >/dev/null
  a="$(sed -n 's/^API_PORT=//p' "$d/.env.local")"; b="$(sed -n 's/^DB_PORT=//p' "$d/.env.local")"
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ]
  [ "$a" != 3000 ] || _fail "worktree got a free port"
  assert_contains "$(cat "$d/.env.local")" "DB_NAME=shop_node_app_wt" "db name"
  python3 -c "import socket,sys
for p in sys.argv[1:]:
    s=socket.socket(); s.bind(('',int(p))); s.close()" "$a" "$b"
  _run "$d" >/dev/null   # stable on re-run
  assert_eq "$(sed -n 's/^API_PORT=//p' "$d/.env.local")" "$a" "port kept"
}
t_main_checkout_keeps_example_ports() {
  local d; d="$(_su)"; printf 'API_PORT=3000\nDB_PORT=5432\n' > "$d/.env.example"
  _run "$d" >/dev/null
  assert_contains "$(cat "$d/.env.local")" "API_PORT=3000" "api"
  assert_contains "$(cat "$d/.env.local")" "DB_PORT=5432" "db"
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
  assert_contains "$(cat "$bin/args")" "compose -f docker-compose.yml --env-file .env --env-file .env.local -p node-app up -d" "args"
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
t_proof_resolves_setup() {
  local d out; d="$(_su)"; mkdir "$d/.agents"
  echo '{"commands":{"setup":"echo via-runner"}}' > "$d/.agents/harness.json"
  ( cd "$d" && git add -A && git -c core.hooksPath=/dev/null commit -qm r ) >/dev/null
  out="$(cd "$d" && bash scripts/harness/setup-proof.sh 2>&1)"
  assert_contains "$out" "setup-proof: OK" "registered runner used"
  printf 'other:\n\t@true\n' > "$d/Makefile"; rm -r "$d/.agents"
  ( cd "$d" && git add -A && git -c core.hooksPath=/dev/null commit -qm r2 ) >/dev/null
  out="$(cd "$d" && bash scripts/harness/setup-proof.sh 2>&1)" && return 1
  assert_contains "$out" "setup not wired" "unwired"
}
t_real_harness_mk_setup_without_seed() {
  local d out A="$PLUGIN/skills/harness-init/assets"; d="$(_su)"
  cp "$A/harness.mk" "$d/"; printf 'include harness.mk\n' > "$d/Makefile"
  cp "$A/harness/local-guard.sh" "$d/scripts/harness/"
  out="$(_run "$d")" || _fail "setup failed: $out"
  assert_contains "$out" "setup: OK" "ok"; assert_contains "$out" "seed skipped" "seed skipped"
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

t_proof_uses_distinct_project() {
  local d bin; d="$(_su)"; bin="$(mktemp -d)"; cp "$FIXTURES/node-app/docker-compose.yml" "$d/"
  ( cd "$d" && git add -A && git -c core.hooksPath=/dev/null commit -qm c ) >/dev/null
  printf '#!/bin/sh\necho "$@" >> "%s/args"\n' "$bin" > "$bin/docker"; chmod +x "$bin/docker"
  # even with shared services exported and kept in .env.local, the proof must not use the dev project
  printf 'HARNESS_SHARED_SERVICES=1\n' > "$d/.env.local"
  ( cd "$d" && PATH="$bin:$PATH" HARNESS_SHARED_SERVICES=1 HARNESS_PROOF_KEEP_ENV=1 bash scripts/harness/setup-proof.sh ) >/dev/null 2>&1
  assert_contains "$(grep ' up ' "$bin/args")" "-p node-app-proof" "up project"
  assert_contains "$(grep ' down ' "$bin/args")" "-p node-app-proof down -v" "down project"
  assert_not_contains "$(cat "$bin/args")" "-p node-app " "never the dev project"
}
t_proof_cleans_up_on_failure() {
  local d tmp; d="$(_su 'setup-migrate:
	@false')"; tmp="$(mktemp -d)"
  ( cd "$d" && TMPDIR="$tmp" bash scripts/harness/setup-proof.sh ) >/dev/null 2>&1 && return 1
  [ -z "$(ls "$tmp")" ] || _fail "tmp left behind"
}
t_local_guard() {
  local d g; d="$(mktemp -d)"; g="$S/local-guard.sh"
  run() { ( cd "$d" && env -i PATH="$PATH" "$@" bash "$g" 2>&1 ); }
  assert_exit 1 "prod url" -- bash -c "cd '$d' && env -i PATH=\"\$PATH\" DATABASE_URL=postgres://u:p@db.prod.example.com:5432/x bash '$g'"
  assert_contains "$(run DATABASE_URL=postgres://u:p@db.prod.example.com:5432/x || true)" "DATABASE_URL=db.prod.example.com" "names var and host"
  run DATABASE_URL=postgres://u@localhost/x >/dev/null
  run DATABASE_URL=postgres://u@postgres:5432/x REDIS_URL=redis://[::1]:6379 DB_HOST=127.0.0.1 >/dev/null
  run API_URL=https://api.example.com >/dev/null   # not a db scheme
  printf 'DB_HOST=rds.amazonaws.com\n' > "$d/.env"
  assert_exit 1 ".env checked" -- bash -c "cd '$d' && bash '$g'"
  run HARNESS_ALLOW_SEED=1 | grep -q WARNING
}
t_local_guard_bypasses_closed() {
  local d g; d="$(mktemp -d)"; g="$S/local-guard.sh"
  gr() { ( cd "$d" && env -i PATH="$PATH" "$@" bash "$g" ) >/dev/null 2>&1; }
  gr DB_HOST=127.evil.com && _fail "127.evil.com allowed"
  gr DB_HOST=127.0.0.1 || _fail "127.0.0.1 refused"
  gr DATABASE_URL=postgres://u@localhost:5432,db.prod.example.com:5432/x && _fail "second host unchecked"
  gr MONGO_URL=mongodb://a:1,b:2/x || _fail "local multi-host refused"
  printf 'DB_HOST = rds.amazonaws.com\n' > "$d/.env"
  gr && _fail ".env spaces around = unchecked"
  printf '  export DB_HOST="localhost"  # dev\n' > "$d/.env"
  gr || _fail "local .env refused"
  rm "$d/.env"; mkdir -p "$d/src/main/resources"
  printf 'spring.datasource.url=jdbc:postgresql://db.prod.example.com:5432/x\n' > "$d/src/main/resources/application.properties"
  gr && _fail "spring properties unchecked"
  printf 'spring.datasource.url = jdbc:postgresql://${DB_HOST:localhost}:5432/x\n' > "$d/src/main/resources/application.properties"
  gr || _fail "placeholder default localhost refused"
  rm "$d/src/main/resources/application.properties"
  printf 'spring:\n  datasource:\n    url: jdbc:mysql://prod.example.com/x\n' > "$d/src/main/resources/application-dev.yml"
  gr && _fail "spring yml unchecked"
  printf 'spring:\n  datasource:\n    url: jdbc:mysql://mysql:3306/x\napi:\n  url: https://api.example.com\n' > "$d/src/main/resources/application-dev.yml"
  gr || _fail "local yml refused"
}
t_make_seed_guarded() {
  local d; d="$(mktemp -d)"; mkdir -p "$d/scripts/harness"; cp "$S/local-guard.sh" "$d/scripts/harness/"; cp "$S/../harness.mk" "$d/"
  printf 'HARNESS_SEED = @echo seeded\ninclude harness.mk\n' > "$d/Makefile"
  assert_exit 2 "prod refused" -- bash -c "cd '$d' && DATABASE_URL=postgres://u@prod.example.com/x make seed"
  assert_exit 2 "reset refused" -- bash -c "cd '$d' && DATABASE_URL=postgres://u@prod.example.com/x make reset"
  assert_contains "$(cd "$d" && DATABASE_URL=postgres://u@localhost/x make -s seed)" seeded "local ok"
}
t_make_seed_refuses_without_guard() {
  local d out; d="$(mktemp -d)"; cp "$S/../harness.mk" "$d/"
  printf 'HARNESS_SEED = @echo seeded\nHARNESS_RESET = @echo wiped\ninclude harness.mk\n' > "$d/Makefile"
  out="$(cd "$d" && make seed 2>&1)" && return 1
  assert_contains "$out" "seed: scripts/harness/local-guard.sh missing — refusing" "seed msg"
  assert_not_contains "$out" "seeded" "did not run"
  out="$(cd "$d" && make reset 2>&1)" && return 1
  assert_contains "$out" "reset: scripts/harness/local-guard.sh missing — refusing" "reset msg"
  assert_contains "$(cd "$d" && HARNESS_ALLOW_SEED=1 make -s seed 2>&1)" seeded "override"
}
