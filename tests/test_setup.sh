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
  local d a b; d="$(_su)"  # free ports: since 2.0.9 a busy example port (a local 5432) is replaced
  read -r a b <<<"$(python3 -c 'import socket; s=[socket.socket() for _ in range(2)]; [x.bind(("127.0.0.1",0)) for x in s]; print(*[x.getsockname()[1] for x in s])')"
  printf 'API_PORT=%s\nDB_PORT=%s\n' "$a" "$b" > "$d/.env.example"
  _run "$d" >/dev/null
  assert_contains "$(cat "$d/.env.local")" "API_PORT=$a" "api"
  assert_contains "$(cat "$d/.env.local")" "DB_PORT=$b" "db"
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
  printf '#!/bin/sh\n[ "$2" = version ] && { echo v2.24.6; exit 0; }\necho "$@" >> "%s/args"\n' "$bin" > "$bin/docker"; chmod +x "$bin/docker"
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
  printf 'services:\n  postgres:\n    image: postgres\n  a:\n    image: x\n  b:\n    image: x\n  mysql:\n    image: mysql\n' > "$d/docker-compose.yml"
  run DATABASE_URL=postgres://u@postgres:5432/x REDIS_URL=redis://[::1]:6379 DB_HOST=127.0.0.1 >/dev/null
  run API_URL=https://api.example.com >/dev/null   # not a db scheme
  printf 'DB_HOST=rds.amazonaws.com\n' > "$d/.env"
  assert_exit 1 ".env checked" -- bash -c "cd '$d' && bash '$g'"
  run HARNESS_ALLOW_SEED=1 | grep -q WARNING
}
t_local_guard_explains_bare_host() {
  local d out; d="$(mktemp -d)"
  out="$( ( cd "$d" && env -i PATH="$PATH" DB_HOST=dbserver bash "$S/local-guard.sh" ) 2>&1 || true)"
  assert_contains "$out" "dbserver is not a localhost name or a service in this repo's compose files" "why"
  out="$( ( cd "$d" && env -i PATH="$PATH" DB_HOST=db.prod.example.com bash "$S/local-guard.sh" ) 2>&1 || true)"
  assert_not_contains "$out" "is not a localhost name" "dotted host needs no hint"
}
t_local_guard_bypasses_closed() {
  local d g; d="$(mktemp -d)"; g="$S/local-guard.sh"
  printf 'services:\n  a:\n    image: x\n  b:\n    image: x\n  mysql:\n    image: mysql\n' > "$d/compose.yml"
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
t_local_guard_skips_prod_profiles() {
  local d g; d="$(mktemp -d)"; g="$S/local-guard.sh"; mkdir -p "$d/src/main/resources"
  gr() { ( cd "$d" && env -i PATH="$PATH" "$@" bash "$g" ) >/dev/null 2>&1; }
  printf 'spring.datasource.url=jdbc:postgresql://db.prod.example.com/x\n' > "$d/src/main/resources/application-prod.properties"
  printf 'spring:\n  datasource:\n    url: jdbc:postgresql://db.prod.example.com/x\n' > "$d/src/main/resources/application-production.yml"
  printf 'spring.datasource.url=jdbc:postgresql://localhost/x\n' > "$d/src/main/resources/application.properties"
  gr || _fail "prod profile files must not be read"
  printf 'spring.datasource.url=jdbc:postgresql://db.prod.example.com/x\n' > "$d/src/main/resources/application-test.properties"
  gr && _fail "test profile must be read"
  true
}
t_local_guard_single_label_needs_compose_service() {
  local d g; d="$(mktemp -d)"; g="$S/local-guard.sh"
  gr() { ( cd "$d" && env -i PATH="$PATH" "$@" bash "$g" ) >/dev/null 2>&1; }
  gr SPRING_DATASOURCE_URL=jdbc:oracle:thin:@prod:1521/X && _fail "oracle thin single-label host allowed"
  gr SPRING_DATASOURCE_URL=jdbc:oracle:thin:@//prod:1521/X && _fail "oracle thin @// host allowed"
  gr DB_HOST=db && _fail "single-label without compose allowed"
  printf 'services:\n  db:  # local\n    image: postgres\n    environment:\n      oracle: x\n' > "$d/docker-compose.yml"
  gr DB_HOST=db || _fail "compose service refused"
  gr SPRING_DATASOURCE_URL=jdbc:oracle:thin:@db:1521/X || _fail "oracle thin compose service refused"
  gr DB_HOST=oracle && _fail "nested key is not a service"
  gr SPRING_DATASOURCE_URL=jdbc:oracle:thin:@localhost:1521/X || _fail "localhost refused"
}
t_old_compose_gets_merged_env_file() {
  local d bin; d="$(_su)"; bin="$(mktemp -d)"; cp "$FIXTURES/node-app/docker-compose.yml" "$d/"
  printf '#!/bin/sh\n[ "$2" = version ] && { echo 2.12.2; exit 0; }\necho "$@" >> "%s/args"\nf=$(echo "$@" | sed -n "s/.*--env-file \\([^ ]*\\).*/\\1/p"); cat "$f" > "%s/merged"\n' "$bin" "$bin" > "$bin/docker"; chmod +x "$bin/docker"
  ( cd "$d" && PATH="$bin:$PATH" make -s setup ) >/dev/null 2>&1
  assert_eq "$(grep -o -- '--env-file' "$bin/args" | wc -l | tr -d ' ')" 1 "one env file"
  assert_contains "$(cat "$bin/merged")" "COMPOSE_PROJECT_NAME=node-app" ".env.local merged"
  assert_contains "$(cat "$bin/merged")" "$(head -1 "$d/.env")" ".env merged"
}
t_first_run_label() {
  local d; d="$(_su)"; rm -f "$d/.env.example"
  assert_contains "$(_run "$d")" "setup: OK  (first run" "first"
  assert_contains "$(_run "$d")" "setup: OK  (re-run" "second"
}
t_local_guard_reads_active_profiles() {
  local d g; d="$(mktemp -d)"; g="$S/local-guard.sh"; mkdir -p "$d/src/main/resources"
  gr() { ( cd "$d" && env -i PATH="$PATH" "$@" bash "$g" ) >/dev/null 2>&1; }
  printf 'spring.datasource.url=jdbc:postgresql://db.prod.example.com/x\n' > "$d/src/main/resources/application-prod.properties"
  printf 'spring:\n  datasource:\n    url: jdbc:postgresql://localhost/x\n' > "$d/src/main/resources/application-qa.yml"
  gr || _fail "inactive prod profile read"
  gr SPRING_PROFILES_ACTIVE=prod && _fail "active prod profile (env) allowed"
  gr SPRING_PROFILES_ACTIVE=qa || _fail "active local-host profile refused"
  printf 'SPRING_PROFILES_ACTIVE="qa, prod"\n' > "$d/.env"
  gr && _fail "active prod profile (.env list) allowed"
  rm "$d/.env"; printf 'export SPRING_PROFILES_ACTIVE=prod\n' > "$d/.env.local"
  gr && _fail "active prod profile (.env.local) allowed"
  rm "$d/.env.local"; printf 'SPRING_PROFILES_ACTIVE=prod # main\n' > "$d/.env"
  gr && _fail "active prod profile with an inline comment allowed"
  printf "SPRING_PROFILES_ACTIVE='qa' # local\n" > "$d/.env"
  gr || _fail "quoted profile with an inline comment refused"
  true
}
t_maven_hint_only_when_deps_not_ok() {
  local d h out; h="$(mktemp -d)"
  d="$(_su 'setup-deps:
	@true')"; echo '<settings/>' > "$d/settings.xml"
  out="$(cd "$d" && HOME="$h" make -s setup 2>&1)"
  assert_not_contains "$out" "maven credentials" "deps passed with -s settings.xml: no hint"
  d="$(_su 'setup-deps:
	@false')"; echo '<settings/>' > "$d/settings.xml"
  out="$(cd "$d" && HOME="$h" make -s setup 2>&1)" && return 1
  assert_contains "$out" "maven credentials" "deps failed: hint"
}
_hold_port() { # _hold_port <file>: listens on a free port in the background, writes "<port> <pid>" to <file>
  python3 -c 'import socket,time,sys
s=socket.socket(); s.bind(("",0)); s.listen(1); print(s.getsockname()[1], flush=True); time.sleep(60)' > "$1.p" &
  local i=0; while [ ! -s "$1.p" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  echo "$(cat "$1.p") $!" > "$1"
}
t_main_checkout_busy_port_gets_free_one() {
  local d port pid p; d="$(_su)"; _hold_port "$d/.hold"; read -r port pid < "$d/.hold"
  printf 'API_PORT=%s\nDB_PORT=5432\n' "$port" > "$d/.env.example"
  _run "$d" >/dev/null
  p="$(sed -n 's/^API_PORT=//p' "$d/.env.local")"
  [ -n "$p" ] && [ "$p" != "$port" ] || { kill "$pid"; _fail "busy example port $port reused ($p)"; }
  _run "$d" >/dev/null; kill "$pid"
  assert_eq "$(sed -n 's/^API_PORT=//p' "$d/.env.local")" "$p" ".env.local value kept on re-run"
}
t_main_checkout_port_held_by_own_project_kept() {
  local d bin port pid; d="$(_su)"; bin="$(mktemp -d)"; _hold_port "$d/.hold"; read -r port pid < "$d/.hold"
  printf '#!/bin/sh\n[ "$1" = ps ] && case "$*" in *com.docker.compose.project=node-app*) echo "0.0.0.0:%s->3000/tcp";; esac\nexit 0\n' "$port" > "$bin/docker"; chmod +x "$bin/docker"
  printf 'API_PORT=%s\n' "$port" > "$d/.env.example"
  ( cd "$d" && PATH="$bin:$PATH" make -s setup ) >/dev/null 2>&1; kill "$pid"
  assert_contains "$(cat "$d/.env.local")" "API_PORT=$port" "our own compose container holds it: kept"
}
t_smoke_default_reports_na() {
  local d out A="$PLUGIN/skills/harness-init/assets"; d="$(_su)"
  cp "$A/harness.mk" "$d/"; printf 'include harness.mk\n' > "$d/Makefile"; cp "$A/harness/local-guard.sh" "$d/scripts/harness/"
  rm -f "$d/.nvmrc" "$d/.env.example"   # no "needs you" items, so smoke runs
  out="$(_run "$d")" || _fail "setup failed: $out"
  assert_contains "$out" "smoke n/a" "unset HARNESS_SMOKE is not a pass"
  assert_not_contains "$out" "smoke ✓" "no false tick"
}
t_setup_smoke_opt_out() {
  local d out A="$PLUGIN/skills/harness-init/assets"; d="$(_su)"
  cp "$A/harness.mk" "$d/"; printf 'HARNESS_SMOKE = @echo booting-app && false\nHARNESS_SETUP_SMOKE = 0\ninclude harness.mk\n' > "$d/Makefile"
  out="$(_run "$d")" || _fail "setup failed: $out"
  assert_not_contains "$out" "booting-app" "smoke not run inside setup"
  assert_contains "$out" "smoke skipped" "reported"
}
t_smoke_skipped_while_needs_you() {
  local d out; d="$(_su 'smoke:
	@echo booting-app')"; printf 'DB_PASSWORD=\n' > "$d/.env.example"
  out="$(_run "$d")"
  assert_not_contains "$out" "booting-app" "setup incomplete: smoke waits"
  assert_contains "$out" "smoke skipped" "reported"
}
t_custom_services_not_given_exported_ports() {
  # compose prefers shell vars over --env-file: a repo's own services step must not inherit the ports setup.sh picked,
  # and migrate/seed must see the port that step wrote to .env.local
  local d; d="$(_su 'setup-services:
	@echo "svc=[$$API_PORT]" > seen; sed -i.bak "s/^API_PORT=.*/API_PORT=17777/" .env.local
setup-migrate:
	@echo "mig=[$$API_PORT]" >> seen')"
  printf 'API_PORT=3000\n' > "$d/.env.example"
  _run "$d" >/dev/null
  assert_eq "$(cat "$d/seen" | tr '\n' ' ')" "svc=[] mig=[17777] " "services clean, migrate re-reads .env.local"
}
t_compose_only_ports_per_worktree() {
  # no .env.example: ports come from ${NAME_PORT:-default} in the compose file, else every worktree binds the same one
  local m w1 w2 bin a b; m="$(_su)"; w1="$(dirname "$m")/w1"; w2="$(dirname "$m")/w2"; bin="$(mktemp -d)"
  printf '#!/bin/sh\n[ "$2" = version ] && { echo v2.24.6; exit 0; }\nexit 0\n' > "$bin/docker"; chmod +x "$bin/docker"
  rm -f "$m/.env.example"; printf 'services:\n  db:\n    image: postgres:16\n    ports: ["${LOCAL_PG_PORT:-5442}:5432"]\n' > "$m/docker-compose.yml"
  ( cd "$m" && git add -A && git -c core.hooksPath=/dev/null commit -qm c && git worktree add -q "$w1" -b w1 && git worktree add -q "$w2" -b w2 ) >/dev/null 2>&1
  ( cd "$w1" && PATH="$bin:$PATH" make -s setup ) >/dev/null 2>&1; ( cd "$w2" && PATH="$bin:$PATH" make -s setup ) >/dev/null 2>&1
  a="$(sed -n 's/^LOCAL_PG_PORT=//p' "$w1/.env.local")"; b="$(sed -n 's/^LOCAL_PG_PORT=//p' "$w2/.env.local")"
  [ -n "$a" ] && [ -n "$b" ] || _fail "LOCAL_PG_PORT not assigned ('$a' '$b')"
  [ "$a" != "$b" ] || _fail "same port in both worktrees ($a)"
}
t_compose_ports_main_checkout_keeps_env() {
  # main checkout: a compose key without a default is not ours to assign, and a value in .env beats the compose default
  local m bin; m="$(_su)"; bin="$(mktemp -d)"
  printf '#!/bin/sh\n[ "$2" = version ] && { echo v2.24.6; exit 0; }\nexit 0\n' > "$bin/docker"; chmod +x "$bin/docker"
  printf 'services:\n  db:\n    image: postgres:16\n    ports: ["${DB_PORT}:5432"]\n  cache:\n    image: redis:7\n    ports: ["${CACHE_PORT:-47391}:6379"]\n' > "$m/docker-compose.yml"
  printf 'DB_PORT=5432\nCACHE_PORT=47392\n' > "$m/.env"
  ( cd "$m" && PATH="$bin:$PATH" make -s setup ) >/dev/null 2>&1
  assert_not_contains "$(cat "$m/.env.local")" "DB_PORT=" "no default in the compose file: left to .env"
  assert_contains "$(cat "$m/.env.local")" "CACHE_PORT=47392" ".env beats the compose default"
}
t_target_reports_needs_you() {
  # a step that can't finish without a person exits 0 (setup-proof must pass) but must not look done
  local d out rc=0; d="$(_su 'setup-services:
	@echo "x: needs you: set FOO"; echo "plain output kept"')"
  out="$(_run "$d")" || rc=$?
  assert_eq "$rc" 0 "exit 0"; assert_contains "$out" "plain output kept" "target output still shown"
  assert_contains "$out" "services ✓ (needs you)" "step marked"
  assert_contains "$out" "needs you: " "summary line"; assert_contains "$(grep '^needs you:' <<<"$out")" "setup-services: set FOO" "item named with its target"
}
t_step_background_process_does_not_block() {
  # a step may leave a process running (a dev server, a watcher) that keeps its stdout open: setup must go on and
  # finish without waiting for it (whoever reads setup's output may still see that process's lines afterwards)
  local d got; d="$(_su 'setup-services:
	@sleep 6 & echo "needs you: start the VPN"')"
  got="$( (cd "$d" && t0="$(date +%s)"; make -s setup 2>&1 | while IFS= read -r l; do
    case "$l" in ("needs you: "*"setup-services: "*) echo "$(( $(date +%s) - t0 )) $l"; break;; esac; done) )"
  pkill -f 'sleep 6' 2>/dev/null || true
  [ -n "$got" ] && [ "${got%% *}" -lt 4 ] || _fail "setup's summary came after ${got%% *}s: $got"
  assert_contains "$got" "setup-services: start the VPN" "needs you still read"
}
t_step_output_streams() {
  # a long step's lines must show as they happen, not at its end (python block-buffers a pipe)
  local d first; d="$(_su 'setup-migrate:
	@python3 -c "import time; print(\"step1\"); time.sleep(3); print(\"step2\")"')"
  first="$( (cd "$d" && t0="$(date +%s)"; make -s setup 2>&1 | while IFS= read -r l; do
    [ "$l" = step1 ] && { echo $(( $(date +%s) - t0 )); break; }; done) )"
  [ -n "$first" ] && [ "$first" -lt 2 ] || _fail "step1 shown after ${first:-?}s"
}
t_deps_needs_you_is_not_a_failed_deps() {
  # "✓ (needs you)" is a deps step that ran: no maven-credentials hint for it
  local d h out; h="$(mktemp -d)"; d="$(_su 'setup-deps:
	@echo "needs you: accept the licence"')"; touch "$d/settings.xml"
  out="$(cd "$d" && HOME="$h" make -s setup 2>&1)"
  assert_contains "$out" "deps ✓ (needs you)" "marked"; assert_not_contains "$out" "maven credentials" "no hint"
}
