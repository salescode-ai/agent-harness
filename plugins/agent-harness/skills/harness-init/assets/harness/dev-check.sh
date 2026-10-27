#!/usr/bin/env bash
# dev-check.sh -- agents check a running app without leaving it running (make dev-check / make dev-stop).
#   dev-check.sh start <health> [secs] [run-cmd]  start `make dev` in its own process group, wait until <health>
#                                                 (a URL answering 2xx/3xx, or a command exiting 0), run <run-cmd>,
#                                                 then always stop it. Exit: run-cmd's status; 1 if never healthy.
#   dev-check.sh stop                             stop the server dev-check started from this checkout
PIDF=.harness/dev.pid; LOG=.harness/dev-check.log
stop() {
  local g; g="$(cat "$PIDF" 2>/dev/null)"
  [ -n "$g" ] || { echo "dev-stop: nothing started by dev-check here"; return 0; }
  kill -TERM -- "-$g" 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 -- "-$g" 2>/dev/null || { rm -f "$PIDF"; echo "dev-stop: stopped"; return 0; }; sleep 1
  done
  kill -KILL -- "-$g" 2>/dev/null; rm -f "$PIDF"; echo "dev-stop: killed"
}
healthy() {
  case "$1" in http://*|https://*) curl -fsS -o /dev/null --max-time 5 "$1";; *) bash -c "$1";; esac >/dev/null 2>&1
}
case "${1:-}" in
  stop) stop; exit 0;;
  start) [ -n "${2:-}" ] || { echo "dev-check: HARNESS_HEALTH is not set" >&2; exit 2; };;
  *) echo "usage: dev-check.sh start <health> [secs] [run-cmd] | stop" >&2; exit 2;;
esac
health="$2"; secs="${3:-120}"; run="${4:-}"
mkdir -p .harness; [ -f "$PIDF" ] && stop >/dev/null
set -m  # job control: the dev server gets its own process group, so stop() reaches its children too
${HARNESS_MAKE:-make} -s dev > "$LOG" 2>&1 &
echo $! > "$PIDF"; set +m
trap 'stop >/dev/null' EXIT; trap 'exit 130' INT TERM
end=$((SECONDS + secs))
until healthy "$health"; do
  kill -0 "$(cat "$PIDF")" 2>/dev/null || { echo "dev-check: dev exited before it was healthy; last log lines:"; tail -20 "$LOG"; exit 1; }
  [ "$SECONDS" -ge "$end" ] && { echo "dev-check: not healthy after ${secs}s ($health); last log lines:"; tail -20 "$LOG"; exit 1; }
  sleep 1
done
echo "dev-check: healthy ($health)"
[ -z "$run" ] || bash -c "$run"
