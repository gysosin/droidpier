#!/usr/bin/env bash
# Automated end-to-end check of the shipped desktop app.
#
# Exists because twice now something passed 150+ widget tests and still did not
# work when launched: auto-connect latched before its first attempt and stranded
# the boot screen, and every window resize handle was unreachable. Widget tests
# assert what the UI *does with* state; nothing was asserting that the real
# binary reaches a connected desk. This does, without a person watching.
#
# Usage:  tool/live_check.sh [seconds] [--restart]
#
# By default it checks whatever is already running and only launches a fresh
# instance if nothing is. Both agents run this now, and an unconditional restart
# would kill the operator's session mid-test — a verification tool must not
# destroy the thing it is verifying. Pass --restart to force a clean launch,
# which is what you want after a rebuild.
#
# Exit 0 = pass. Any failure prints what was expected and what was seen.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP="$ROOT/apps/desktop/build/linux/x64/release/bundle/open_android_dex"
WAIT="45"
RESTART=0
for arg in "$@"; do
  case "$arg" in
    --restart) RESTART=1 ;;
    *[!0-9]*) ;;
    *) WAIT="$arg" ;;
  esac
done
LOG="$(mktemp -t open-dex-live-check-XXXXXX.log)"
FAILURES=0

fail() { printf '  FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf '  ok    %s\n' "$1"; }

# Kill by argv[0] only. `pkill -f` once matched this script's own shell and
# took down three supervisors with it.
stop_app() {
  for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
    [ -r "/proc/$pid/cmdline" ] || continue
    local a0
    a0=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | head -1) || continue
    [ -n "$a0" ] || continue
    [ "$a0" = "$APP" ] && kill "$pid" 2>/dev/null
  done
}

app_pid() {
  for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
    [ -r "/proc/$pid/cmdline" ] || continue
    local a0
    a0=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | head -1) || continue
    [ -n "$a0" ] || continue
    [ "$a0" = "$APP" ] && { echo "$pid"; return; }
  done
}

# Children by name, so we can see how far boot actually got.
child_matching() {
  local parent="$1" needle="$2"
  for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
    [ -r "/proc/$pid/status" ] || continue
    local ppid args
    ppid=$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null) || continue
    [ "$ppid" = "$parent" ] || continue
    args=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    case "$args" in *"$needle"*) echo "$pid"; return ;; esac
  done
}

echo "live check: $APP"
[ -x "$APP" ] || { echo "  FAIL  no release build — run: flutter build linux --release"; exit 1; }

EXISTING="$(app_pid)"
if [ -n "$EXISTING" ] && [ "$RESTART" -eq 0 ]; then
  echo "  info  checking the running instance (pid $EXISTING); --restart to relaunch"
  LOG=/dev/null
else
  [ -n "$EXISTING" ] && echo "  info  restarting (was pid $EXISTING)"
  stop_app
  sleep 3
  # Launched bare from $HOME, with no OPEN_DEX_* overrides: the way a person
  # runs it, and the case that used to fail silently before resources resolved
  # from the executable's own directory.
  cd "$HOME" || exit 1
  setsid "$APP" >> "$LOG" 2>&1 < /dev/null &
  sleep "$WAIT"
fi

PID="$(app_pid)"
if [ -z "$PID" ]; then
  fail "the app exited within ${WAIT}s"
  echo "--- log ---"; tail -20 "$LOG"; exit 1
fi
pass "process alive (pid $PID)"

if [ "$LOG" = /dev/null ]; then
  echo "  info  log check skipped — not this run's process"
elif grep -qiE 'exception|failed assertion|overflowed' "$LOG"; then
  fail "runtime exceptions in the log"
  grep -iE 'exception|failed assertion|overflowed' "$LOG" | head -5
else
  pass "no runtime exceptions"
fi

# The agent proves auto-connect worked: it is only deployed once a device is
# selected and connected.
if [ -n "$(child_matching "$PID" 'openandroiddex.agent.Main')" ]; then
  pass "connected — on-device agent running"
else
  fail "no agent child: the app did not reach a connected desk"
fi

CPU=$(ps -o %cpu= -p "$PID" 2>/dev/null | tr -d ' ')
echo "  info  host CPU ${CPU:-?}%"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "PASS"
else
  echo "$FAILURES check(s) failed; log: $LOG"
fi
exit "$FAILURES"
