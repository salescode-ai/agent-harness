#!/usr/bin/env bash
# setup.sh -- one-command dev setup (run from the repo root via `make setup`). Safe to re-run, never sudo,
# never fetches secrets, never overwrites .env. Repo steps run only if they resolve; `setup` itself is never resolved (recursion).
# Exit 1 only when a resolved step failed; "needs you" items alone exit 0.
# A repo step that can't finish without a person exits 0 and prints a line `needs you: <what>` (optionally
# `<target>: needs you: <what>`): it is listed under "needs you" and the step shows "✓ (needs you)".
NEEDS=""; ST_deps="skipped"; ST_services="skipped"; ST_migrate="skipped"; ST_seed="skipped"; ST_smoke="skipped"; FAILED=""; RT_UNSET=""
need() { NEEDS="${NEEDS:+$NEEDS, }$1"; }
has() { command -v "$1" >/dev/null 2>&1; }
major() { printf %s "$1" | sed 's/^v//; s/[^0-9].*//'; }
slug() { printf %s "$1" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//'; }

# --- worktree identity: <main repo dir>-<this dir>; plain checkout -> just the dir name
top="$(basename "$PWD")"
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
main="$top"; [ -n "$common" ] && main="$(basename "$(dirname "$common")")"
WT=""; [ -f .git ] && WT="$(slug "$top")"
PROJECT="$(slug "$main")"; [ "$top" != "$main" ] && PROJECT="$PROJECT-$(slug "$top")"

# --- 1. prereqs: versions from .nvmrc/.tool-versions/.sdkmanrc/.python-version; compares majors only
# shortcut: major-version compare, upgrade if teams pin minors
check_tool() { # <label> <wanted> <have> <manager-cmd...>
  local label="$1" want="$2" have="$3"; shift 3
  [ -n "$(major "$want")" ] || return 0
  [ "$(major "$want")" = "$(major "$have")" ] && return 0
  [ -n "$*" ] && "$@" >/dev/null 2>&1
  case "$(uname)" in Darwin) hint="brew install ${label}";; *) hint="your package manager: ${label}";; esac
  need "$label $want (found ${have:-none}; activate it via your version manager or: $hint)"
}
have_node() { node -v 2>/dev/null; }
have_py() { python3 -V 2>/dev/null | awk '{print $2}'; }
have_java() { java -version 2>&1 | sed -n '1s/.*"\([0-9][0-9.]*\).*/\1/p'; }
vm_run() { # <init-script> <cmd...>
  [ -s "$1" ] || return 1; local i="$1"; shift; bash -c ". '$i'; $*"
}
mgr=""; has mise && mgr="mise install"; [ -z "$mgr" ] && has asdf && mgr="asdf install"
[ -f .nvmrc ] && check_tool node "$(head -1 .nvmrc)" "$(have_node)" vm_run "${NVM_DIR:-$HOME/.nvm}/nvm.sh" "nvm install"
[ -f .python-version ] && check_tool python "$(head -1 .python-version)" "$(have_py)" $(has pyenv && echo pyenv install -s)
[ -f .sdkmanrc ] && check_tool java "$(sed -n 's/^java=//p' .sdkmanrc | head -1)" "$(have_java)" vm_run "$HOME/.sdkman/bin/sdkman-init.sh" "sdk env install"
if [ -f .tool-versions ]; then
  while read -r t v _; do
    case "$t" in nodejs|node) check_tool node "$v" "$(have_node)" $mgr;; python) check_tool python "$v" "$(have_py)" $mgr;; java) check_tool java "${v#*-}" "$(have_java)" $mgr;; esac
  done < .tool-versions
fi

# --- 2. registry sign-in hints (never stores credentials)
for r in $(grep -hs 'registry *= *http' .npmrc | sed 's/.*= *//' | grep -v 'registry.npmjs.org'); do
  has npm && ! npm whoami --registry "$r" >/dev/null 2>&1 && need "npm login --registry $r"
done
COMPOSE=""; for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml compose.harness.yml; do [ -f "$f" ] && { COMPOSE="$f"; break; }; done
if [ -n "$COMPOSE" ]; then
  for h in $(sed -n 's/^ *image: *\([^/ ]*\.[^/ ]*\)\/.*/\1/p' "$COMPOSE" | sort -u); do
    grep -qs "$h" "$HOME/.docker/config.json" || need "docker login $h"
  done
fi

# --- 3. env: .env from example if missing; .env.local = worktree values (unmanaged lines kept)
FRESH=""; PORTS=""
port_free() { # free: nothing listens and it can be bound (no python3: assume free)
  has python3 || return 0
  python3 -c 'import socket,sys
p=int(sys.argv[1]); s=socket.socket()
try: s.bind(("",p))
except OSError: sys.exit(1)
s.close(); c=socket.socket(); c.settimeout(0.5); sys.exit(c.connect_ex(("127.0.0.1",p))==0)' "$1" 2>/dev/null
}
port_ours() { has docker && docker ps --filter "label=com.docker.compose.project=$PROJECT" --format '{{.Ports}}' 2>/dev/null | grep -q ":$1->"; }
ev() { sed -n "s/^\(export \)\{0,1\}$2=//p" "$1" 2>/dev/null | head -1 | sed "s/^[\"']//; s/[\"']\$//"; }
cdef() { [ -n "$COMPOSE" ] && sed -n "s/.*\${$1:-\([0-9]*\)}.*/\1/p" "$COMPOSE" | head -1; }  # ${NAME_PORT:-5442} -> 5442
if [ -f .env.example ]; then
  [ -f .env ] || { cp .env.example .env; FRESH=1; }
  keys="$(sed -n 's/^\(export \)\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)=.*/\2/p' .env.example)"
  for k in $keys; do
    case "$k" in DB_NAME|COMPOSE_PROJECT_NAME|*_PORT) continue;; esac
    v="$(ev .env "$k")"; [ -z "$v" ] && ! grep -q "^\(export \)\{0,1\}$k=" .env 2>/dev/null && v="$(ev .env.example "$k")"
    case "$v" in ''|changeme) need "$k";; esac
  done
fi
SHARED="${HARNESS_SHARED_SERVICES:-$(ev .env.local HARNESS_SHARED_SERVICES)}"
if [ -f .env.example ] || [ -n "$COMPOSE" ]; then
  # port keys from .env.example and from ${NAME_PORT:-<port>} in the compose file (a repo may have only the latter);
  # a ${NAME_PORT} without a default is set elsewhere (.env, the shell) and left alone
  pk="$( { [ -f .env.example ] && printf '%s\n' $keys | grep '_PORT$'
    [ -n "$COMPOSE" ] && grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*_PORT:-[0-9]+\}' "$COMPOSE" | sed -E 's/^\$\{([A-Za-z0-9_]+).*/\1/'; } | awk 'NF && !s[$0]++')"
  managed="COMPOSE_PROJECT_NAME DB_NAME $pk"
  new="$(mktemp)"; : > "$new"
  if [ "$SHARED" != 1 ]; then
    echo "COMPOSE_PROJECT_NAME=$PROJECT" >> "$new"
    n=0; for k in $pk; do n=$((n+1)); done
    if [ "$n" -gt 0 ]; then
      free="$(python3 -c '
import socket,sys
s=[socket.socket() for _ in range(int(sys.argv[1]))]
for x in s: x.bind(("",0))
print(*[x.getsockname()[1] for x in s])' "$n" 2>/dev/null)"
      [ -z "$free" ] && need "python3 missing: set $(printf '%s ' $pk)in .env.local yourself"
      set -- $free
      for k in $pk; do
        # main checkout keeps the example's port while it is free or held by this compose project; otherwise,
        # and in linked worktrees (.git is a file), a free one. A value already in .env.local always wins; for a key
        # only the compose file names, the main checkout takes .env's value before the compose default.
        p="$(ev .env.local "$k")"
        if [ -z "$p" ] && [ -z "$WT" ]; then p="$(ev .env.example "$k")"; [ -z "$p" ] && ! grep -qs "^\(export \)\{0,1\}$k=" .env.example && { p="$(ev .env "$k")"; [ -z "$p" ] && p="$(cdef "$k")"; }; [ -n "$p" ] && ! port_free "$p" && ! port_ours "$p" && p=""; fi
        [ -z "$p" ] && p="${1:-}"; shift 2>/dev/null
        [ -n "$p" ] && { echo "$k=$p" >> "$new"; PORTS="$PORTS ${k%_PORT}=$p"; export "$k=$p"; }
      done
    fi
    b="$(ev .env.example DB_NAME)"; [ -n "$b" ] && echo "DB_NAME=${b}_$(slug "$PROJECT" | tr - _)" >> "$new"
  fi
  if [ -f .env.local ]; then
    while IFS= read -r l || [ -n "$l" ]; do
      k="${l%%=*}"; k="${k#export }"; skip=""
      for m in $managed; do [ "$k" = "$m" ] && skip=1; done
      [ -z "$skip" ] && printf '%s\n' "$l" >> "$new"
    done < .env.local
  fi
  mv "$new" .env.local
  [ "$SHARED" != 1 ] && export COMPOSE_PROJECT_NAME="$PROJECT" && DBN="$(ev .env.local DB_NAME)" && [ -n "$DBN" ] && export DB_NAME="$DBN"
  git check-ignore -q .env.local 2>/dev/null || need "add .env.local to .gitignore"
fi

# --- repo steps: only when the target resolves; a failing resolved step is required-failed
run_target() { # <var-suffix> <target> [fallback-cmd...]
  local v="$1" t="$2" cmd rc=0; shift 2
  [ -n "$FAILED" ] && { eval "ST_$v=-"; return; }
  cmd="$(bash scripts/harness/cmd.sh . "$t" 2>/dev/null)" || rc=$?
  if [ "$rc" = 0 ] && [ -n "$cmd" ]; then :
  elif [ $# -gt 0 ]; then cmd="$*"
  else return 0; fi
  local log n i z=-1; log="$(mktemp)"
  # stdout is copied to $log by a tee in a process substitution, not a pipe: the step's exit code is its own, and a
  # process it leaves running (a server, a watcher) holding stdout doesn't make setup wait. PYTHONUNBUFFERED: python
  # would block-buffer the pipe and show a long step's lines only at its end.
  if ( [ -n "$RT_UNSET" ] && unset $RT_UNSET; export PYTHONUNBUFFERED=1; eval "$cmd" ) > >(tee "$log"); then eval "ST_$v='✓'"; else eval "ST_$v='✗'"; FAILED="$v"; fi
  # tee may lag the step's exit: read the log once it stops growing (at most ~2 s)
  for i in 1 2 3 4 5 6 7 8 9 10; do n="$(wc -c < "$log")"; [ "$n" = "$z" ] && break; z="$n"; sleep 0.2; done
  n="$(sed -n 's/^\([A-Za-z0-9_.-]*: \)\{0,1\}needs you: //p' "$log")"; rm -f "$log"
  if [ -n "$n" ]; then
    while IFS= read -r l; do need "$t: $l"; done <<<"$n"
    eval "[ \"\$ST_$v\" = '✓' ] && ST_$v='✓ (needs you)'"
  fi
}
run_target deps setup-deps
# only when deps did not succeed: a repo passing `-s settings.xml` (or a registry extension) needs no ~/.m2 copy
if [ "${ST_deps#✓}" = "$ST_deps" ] && [ -f settings.xml ] && [ ! -f "$HOME/.m2/settings.xml" ]; then need "maven credentials: copy settings.xml to ~/.m2 and add your server login"; fi
dc=""
if [ -n "$COMPOSE" ]; then
  if has docker; then
    dc="docker compose -f '$COMPOSE'"
    if [ -f .env.local ] && [ -f .env ]; then
      # two --env-file flags need Compose >= 2.17; otherwise (or unknown) pass one merged temp file (later wins)
      cv="$(docker compose version --short 2>/dev/null | sed 's/^v//')"
      cmaj="${cv%%.*}"; cmin="${cv#*.}"; cmin="${cmin%%.*}"
      case "$cmaj$cmin" in *[!0-9]*|'') cmaj=0; cmin=0;; esac
      if [ "$cmaj" -gt 2 ] || { [ "$cmaj" -eq 2 ] && [ "$cmin" -ge 17 ]; }; then dc="$dc --env-file .env --env-file .env.local"
      else MERGED="$(mktemp)"; trap 'rm -f "$MERGED"' EXIT; cat .env .env.local > "$MERGED"; dc="$dc --env-file '$MERGED'"; fi
    elif [ -f .env.local ]; then dc="$dc --env-file .env.local"; fi
    [ "$SHARED" != 1 ] && dc="$dc -p '$PROJECT'"; dc="$dc up -d"
  else need "install Docker (https://docs.docker.com/get-docker/) to start $COMPOSE"; fi
fi
# compose prefers shell variables over --env-file, so the services step must not inherit the exported ports (a repo's own
# setup-services may pick others and write them to .env.local); later steps re-read .env.local
RT_UNSET="${pk:-}"; run_target services setup-services $dc; RT_UNSET=""
for k in ${pk:-}; do p="$(ev .env.local "$k")"; [ -n "$p" ] && export "$k=$p"; done
run_target migrate setup-migrate
run_target seed seed

# --- githooks
if [ -d .husky ]; then
  if [ -d node_modules ]; then npx --no-install husky >/dev/null 2>&1 || need "run npx husky"; else need "run your package install, then npx husky"; fi
elif [ -f lefthook.yml ] || [ -f lefthook.yaml ]; then has lefthook && lefthook install >/dev/null 2>&1 || need "install lefthook, then lefthook install"
elif [ -f .pre-commit-config.yaml ]; then has pre-commit && pre-commit install >/dev/null 2>&1 || need "install pre-commit, then pre-commit install"
elif [ -d .githooks ]; then git config core.hooksPath .githooks
fi

# smoke boots the app: only once setup is otherwise complete, and not at all with HARNESS_SETUP_SMOKE=0
SMOKE_ON="${HARNESS_SETUP_SMOKE:-$(ev .env.local HARNESS_SETUP_SMOKE)}"
if [ "$SMOKE_ON" = 0 ]; then ST_smoke="skipped (HARNESS_SETUP_SMOKE=0)"
elif [ -n "$NEEDS" ]; then ST_smoke="skipped (needs you first)"
else
  SMOKE_LOG="$(mktemp)"; run_target smoke smoke > "$SMOKE_LOG" 2>&1; cat "$SMOKE_LOG"
  # harness.mk's default when HARNESS_SMOKE is unset: nothing ran, so not a pass
  grep -q '^smoke: no runnable surface' "$SMOKE_LOG" && ST_smoke="n/a"; rm -f "$SMOKE_LOG"
fi

# --- report
ok=OK; [ -n "$FAILED" ] && ok=FAIL
where="re-run"; [ -f .harness/setup-ran ] || where="first run"; [ -n "$FRESH" ] && where="fresh clone"
[ -z "$FAILED" ] && mkdir -p .harness 2>/dev/null && : > .harness/setup-ran 2>/dev/null
[ -n "$WT" ] && where="$where · worktree $WT"
[ -n "$PORTS" ] && where="$where · ports${PORTS}"
echo "setup: $ok  ($where)"
echo "steps: deps $ST_deps · services $ST_services"
echo "data: migrate $ST_migrate · seed $ST_seed · smoke $ST_smoke"
echo "needs you: ${NEEDS:-none}"
[ -z "$FAILED" ]
