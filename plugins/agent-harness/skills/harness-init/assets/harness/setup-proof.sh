#!/usr/bin/env bash
# setup-proof.sh -- run `make setup` in a fresh local clone (committed HEAD only), tear down, print the verdict.
# Usage: scripts/harness/setup-proof.sh   (from the repo root). HARNESS_PROOF_KEEP_ENV=1 copies .env.local in.
# The proof always uses its own compose project (<repo>-proof, never shared) so it cannot touch the dev stack.
src="$PWD"; name="$(basename "$src")"
compose=""; for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml compose.harness.yml; do [ -f "$f" ] && compose=1; done
if [ -n "$compose" ] && ! command -v docker >/dev/null 2>&1; then echo "setup-proof: SKIPPED (docker not available)"; exit 0; fi
unset HARNESS_SHARED_SERVICES COMPOSE_PROJECT_NAME
tmp="$(mktemp -d "${TMPDIR:-/tmp}/setup-proof.XXXXXX")"; dir="$tmp/$name-proof"
cleanup() {
  trap - EXIT INT TERM
  p="$(sed -n "s/^COMPOSE_PROJECT_NAME=//p" "$dir/.env.local" 2>/dev/null | head -1)"
  [ -n "$compose" ] && [ -n "$p" ] && ( cd "$dir" && docker compose -p "$p" down -v >/dev/null 2>&1 )
  rm -rf "$tmp"
}
trap cleanup EXIT; trap 'exit 130' INT TERM
git clone -q --local "$src" "$dir" || { echo "setup-proof: FAIL (clone)"; exit 1; }
# keep-env copies .env.local minus the shared flag and any project name (the clone computes its own)
[ "${HARNESS_PROOF_KEEP_ENV:-}" = 1 ] && [ -f .env.local ] && grep -v '^\(export \)\{0,1\}\(HARNESS_SHARED_SERVICES\|COMPOSE_PROJECT_NAME\)=' .env.local > "$dir/.env.local"
rc=0; out="$(cd "$dir" && make setup 2>&1)" || rc=$?
if [ "$rc" = 0 ]; then echo "setup-proof: OK"; exit 0; fi
step="$(printf '%s\n' "$out" | grep -E '^(steps|data):' | grep -o '[a-z]* ✗' | head -1 | cut -d' ' -f1)"
printf '%s\n' "$out" >&2
echo "setup-proof: FAIL (${step:-setup})"; exit 1
