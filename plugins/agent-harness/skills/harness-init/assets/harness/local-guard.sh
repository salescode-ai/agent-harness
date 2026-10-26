#!/usr/bin/env bash
# local-guard.sh -- refuse seed/reset unless every DB-ish host is local. Run from the repo root.
# Reads env, .env, .env.local. HARNESS_ALLOW_SEED=1 overrides with a warning.
bad=""
local_host() {
  case "$1" in
    ''|localhost|::1|host.docker.internal|*.local|*.test|*.localhost|127.*) return 0;;
    *.*|*:*) return 1;;
  esac
  return 0  # bare single-label name = compose service
}
host_of() { # url or bare host -> host
  local v="$1"; v="${v#*://}"; v="${v#*@}"; v="${v%%/*}"; v="${v%%\?*}"
  case "$v" in \[*) v="${v#[}"; v="${v%%]*}";; *) v="${v%%:*}";; esac
  printf %s "$v"
}
check() { # name value; only DB-scheme URLs count for generic *_URL vars
  local h
  case "$1" in
    DATABASE_URL) ;;
    *_URL) case "${2%%://*}" in postgres*|mysql*|mariadb*|mongodb*|redis*|rediss*|jdbc*|mssql*|sqlserver*|oracle*) ;; *) return;; esac;;
  esac
  h="$(host_of "${2#jdbc:}")"
  local_host "$h" || bad="$bad $1=$h"
}
pairs="$( { env; for f in .env .env.local; do [ -f "$f" ] && sed -n 's/^\(export \)\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)=\(.*\)/\2=\3/p' "$f"; done; } | sed "s/=[\"']/=/; s/[\"']\$//" )"
while IFS='=' read -r k v; do
  case "$k" in DATABASE_URL|*_URL|DB_HOST|*_DB_HOST|PGHOST|MYSQL_HOST|MONGO_URL|REDIS_URL) [ -n "$v" ] && check "$k" "$v";; esac
done <<EOT
$pairs
EOT
[ -z "$bad" ] && exit 0
if [ "${HARNESS_ALLOW_SEED:-}" = 1 ]; then echo "local-guard: WARNING non-local target allowed by HARNESS_ALLOW_SEED=1:$bad" >&2; exit 0; fi
echo "local-guard: refusing, non-local target:$bad -- point these at a local service, or set HARNESS_ALLOW_SEED=1 if you are sure" >&2
exit 1
