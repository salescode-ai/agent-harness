#!/usr/bin/env bash
# local-guard.sh -- refuse seed/reset unless every DB-ish host is local. Run from the repo root.
# Reads env, .env, .env.local and Spring src/main/resources/application.properties|yml plus the
# local/dev/test profiles (application-local*, -dev*, -test*), plus every profile named in SPRING_PROFILES_ACTIVE
# (env, .env, .env.local): an active prod profile is read, so its non-local hosts are refused.
# HARNESS_ALLOW_SEED=1 overrides with a warning.
bad=""; why=""
local_host() {
  case "$1" in
    127.*) case "$1" in *[!0-9.]*) return 1;; esac; return 0;;  # 127.evil.com is not loopback
    ''|localhost|::1|host.docker.internal|*.local|*.test|*.localhost) return 0;;
    *.*|*:*) return 1;;
  esac
  # bare single-label name: local only when it is a service in a compose file in this repo
  printf '%s\n' "$SERVICES" | grep -qxF "$1"
}
compose_services() { # top-level keys under "services:" in the repo's compose files
  local f
  for f in docker-compose*.yml docker-compose*.yaml compose*.yml compose*.yaml; do
    [ -f "$f" ] || continue
    awk '/^services:/{s=1;next} /^[^[:space:]#]/{s=0}
      s && /^[[:space:]]+[A-Za-z0-9._-]+:[[:space:]]*(#.*)?$/ {
        match($0,/^[[:space:]]+/); if(!ind) ind=RLENGTH
        if(RLENGTH==ind){ sub(/^[[:space:]]+/,""); sub(/:.*/,""); print } }' "$f"
  done
}
SERVICES="$(compose_services)"
hosts_of() { # url or bare host -> one host per line (multi-host URLs: h1:1,h2:2; Oracle thin @host / @//host)
  local v="$1" h; v="${v#*://}"; v="${v#*@//}"; v="${v%%/*}"; v="${v%%\?*}"; v="${v##*@}"
  printf '%s\n' "$v" | tr ',' '\n' | while IFS= read -r h; do
    case "$h" in \[*) h="${h#[}"; h="${h%%]*}";; *) h="${h%%:*}";; esac
    printf '%s\n' "$h"
  done
}
check() { # name value; only DB-scheme URLs count for generic *_URL vars
  local h v="${2#jdbc:}"
  case "$1" in
    DATABASE_URL) ;;
    *_URL) case "${v%%://*}" in postgres*|mysql*|mariadb*|mongodb*|redis*|rediss*|mssql*|sqlserver*|oracle*) ;; *) return;; esac;;
  esac
  for h in $(hosts_of "$v"); do
    local_host "$h" && continue
    bad="$bad $1=$h"
    case "$h" in *.*|*:*) ;; *) why="$why
local-guard: $h is not a localhost name or a service in this repo's compose files";; esac
  done
}
envfile() { # KEY=VALUE lines from a dotenv file; tolerates "export", indentation and spaces around =
  sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$/\2=\3/p' "$1"
}
ACTIVE="$( { printf '%s\n' "${SPRING_PROFILES_ACTIVE:-}"; for f in .env .env.local; do [ -f "$f" ] && envfile "$f"; done | sed -n 's/^SPRING_PROFILES_ACTIVE=//p'; } \
  | tr -d "\"' " | tr ',' '\n' | grep -v '^$')"
local_profile() { # default, local, dev, test and active profile files (an inactive prod profile is not in use)
  [ -f "$1" ] || return 1
  case "${1##*/}" in application.*|application-local*|application-dev*|application-test*) return 0;; esac
  local p="${1##*/application-}"; p="${p%.*}"
  printf '%s\n' "$ACTIVE" | grep -qxF -- "$p"
}
spring() { # Spring datasource settings -> SPRING_DATASOURCE_URL / SPRING_DATASOURCE_HOST lines
  local f
  for f in src/main/resources/application*.properties */src/main/resources/application*.properties; do
    local_profile "$f" || continue
    sed -nE 's/^[[:space:]]*spring\.datasource\.([A-Za-z.-]*)url[[:space:]]*[=:][[:space:]]*(.*)$/SPRING_DATASOURCE_URL=\2/p
s/^[[:space:]]*spring\.datasource\.([A-Za-z.-]*)host[[:space:]]*[=:][[:space:]]*(.*)$/SPRING_DATASOURCE_HOST=\2/p' "$f"
  done
  # shortcut: YAML is read line by line (any "url:" holding a DB/jdbc URL); upgrade if non-datasource DB URLs misfire
  for f in src/main/resources/application*.yml src/main/resources/application*.yaml \
           */src/main/resources/application*.yml */src/main/resources/application*.yaml; do
    local_profile "$f" || continue
    sed -nE 's/^[[:space:]]*(spring\.datasource\.)?url:[[:space:]]*(.*)$/SPRING_DATASOURCE_URL=\2/p' "$f"
  done
}
pairs="$( { env; for f in .env .env.local; do [ -f "$f" ] && envfile "$f"; done; spring; } \
  | sed -E "s/[[:space:]]+#.*$//; s/=[\"']/=/; s/[\"'][[:space:]]*\$//; s/\\$\\{[A-Za-z0-9_.]*:([^}]*)\\}/\\1/g" )"
while IFS='=' read -r k v; do
  case "$k" in
    DATABASE_URL|*_URL|DB_HOST|*_DB_HOST|PGHOST|MYSQL_HOST|MONGO_URL|REDIS_URL|SPRING_DATASOURCE_HOST) [ -n "$v" ] && check "$k" "$v";;
  esac
done <<EOT
$pairs
EOT
[ -z "$bad" ] && exit 0
if [ "${HARNESS_ALLOW_SEED:-}" = 1 ]; then echo "local-guard: WARNING non-local target allowed by HARNESS_ALLOW_SEED=1:$bad" >&2; exit 0; fi
echo "local-guard: refusing, non-local target:$bad -- point these at a local service, or set HARNESS_ALLOW_SEED=1 if you are sure$why" >&2
exit 1
