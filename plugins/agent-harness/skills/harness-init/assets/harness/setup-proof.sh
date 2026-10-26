#!/usr/bin/env bash
# setup-proof.sh -- run `make setup` in a fresh local clone (committed HEAD only), tear down, print the verdict.
# Usage: scripts/harness/setup-proof.sh   (from the repo root). HARNESS_PROOF_KEEP_ENV=1 copies .env.local in.
src="$PWD"; name="$(basename "$src")"
compose=""; for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml compose.harness.yml; do [ -f "$f" ] && compose=1; done
if [ -n "$compose" ] && ! command -v docker >/dev/null 2>&1; then echo "setup-proof: SKIPPED (docker not available)"; exit 0; fi
tmp="$(mktemp -d "${TMPDIR:-/tmp}/setup-proof.XXXXXX")"; dir="$tmp/$name"
git clone -q --local "$src" "$dir" || { echo "setup-proof: FAIL (clone)"; rm -rf "$tmp"; exit 1; }
[ "${HARNESS_PROOF_KEEP_ENV:-}" = 1 ] && [ -f .env.local ] && cp .env.local "$dir/"
rc=0; out="$(cd "$dir" && make setup 2>&1)" || rc=$?
project="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' "$dir/.env.local" 2>/dev/null | head -1)"
[ -n "$compose" ] && [ -n "$project" ] && ( cd "$dir" && docker compose -p "$project" down -v >/dev/null 2>&1 )
rm -rf "$tmp"
if [ "$rc" = 0 ]; then echo "setup-proof: OK"; exit 0; fi
step="$(printf '%s\n' "$out" | grep -o '[a-z]* ✗' | head -1 | cut -d' ' -f1)"
printf '%s\n' "$out" >&2
echo "setup-proof: FAIL (${step:-setup})"; exit 1
