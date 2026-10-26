#!/usr/bin/env bash
# no-prod-data: flag production-looking data in seeds/fixtures. Usage: no-prod-data.sh <path...>
# Exit 1 on findings (file:line: reason), 0 and silent when clean.
SUFFIX=" — use synthetic data (INVARIANTS.md Data Integrity)"
bad=0
flag() { echo "$1:$2: $3$SUFFIX"; bad=1; }

scan_file() {
  local f="$1" size ln
  case "$f" in *.sql|*.dump)
    size=$(wc -c < "$f" | tr -d ' ')
    [ "$size" -gt 1048576 ] && flag "$f" 1 "${size}-byte dump looks like a production export";;
  esac
  grep -Iq . "$f" 2>/dev/null || return 0   # skip binary/empty
  grep -onE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" | grep -viE '(@example\.(com|org|net)|\.(test|invalid|local))$' |
    while IFS=: read -r ln _; do echo "$ln"; done | while read -r ln; do flag "$f" "$ln" "real-looking email address"; done
  grep -nEi '(^|[^a-z0-9])(prod|production)([^a-z0-9]|$)|rds\.amazonaws\.com' "$f" |
    while IFS=: read -r ln _; do echo "$ln"; done | while read -r ln; do flag "$f" "$ln" "production hostname"; done
  grep -onE '\+[1-9][0-9]{7,14}' "$f" | grep -vE ':\+1555' |
    while IFS=: read -r ln _; do echo "$ln"; done | while read -r ln; do flag "$f" "$ln" "real-looking phone number"; done
}

# findings print from pipeline subshells, so detect them via captured output
out="$(for p in "$@"; do
  if [ -d "$p" ]; then find "$p" -type f -print; elif [ -f "$p" ]; then echo "$p"; fi
done | while IFS= read -r f; do scan_file "$f"; done)"
[ -z "$out" ] && exit 0
echo "$out"; exit 1
