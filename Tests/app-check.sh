#!/bin/sh
# The desktop app driven from within (LBSelfTest.h) against a server of its
# own: a temporary store, on a free port on loopback.
#
#   Tests/app-check.sh build/logbook-server build/Logbook.app/Contents/MacOS/Logbook
#   xvfb-run -a Tests/app-check.sh obj/logbook-server Logbook.app/Logbook     (GNUstep)
set -e
server=$1
app=$2
# A store of MainTrack's to import, as SQL (the self-test makes it a file).
LB_MAINTRACK_SQL="$(cd "$(dirname "$0")" && pwd)/maintrack-store.sql"
export LB_MAINTRACK_SQL
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
log=$(mktemp)
"$server" -StoreURL Temporary -Port "$port" -Localhost YES >"$log" 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$log"' EXIT
# Up to a minute: a CI runner can be slow to start it.
up=no
for i in $(seq 1 600); do
  curl -sf "http://127.0.0.1:$port/odata/" >/dev/null 2>&1 && { up=yes; break; }
  sleep 0.1
done
[ $up = yes ] || { echo "app-check: the server did not answer in 60 s; its log:"; cat "$log"; exit 1; }
status=0
out=$(mktemp)
# Into a file, followed as it goes (a run that hangs shows where): no pipe
# a process it starts (gpbs, gdnc) can hold open. Stopped after 15
# minutes, or a minute after it said it was done and has not quit.
"$app" --self-test "http://127.0.0.1:$port/odata/" -NSQuitAlwaysKeepsWindows NO >"$out" 2>&1 &
app_pid=$!
tail -f "$out" &
tail_pid=$!
trap 'kill $pid $app_pid $tail_pid 2>/dev/null || true; rm -f "$log" "$out"' EXIT
waited=0
done_at=
while kill -0 $app_pid 2>/dev/null; do
  sleep 1
  waited=$((waited + 1))
  [ -z "$done_at" ] && grep -q "^self-test done" "$out" && done_at=$waited
  if [ -n "$done_at" ] && [ $((waited - done_at)) -ge 60 ]; then
    echo "FAIL the app did not quit in a minute after the self-test was done"
    kill $app_pid 2>/dev/null || true
    status=1
    break
  fi
  if [ $waited -ge 900 ]; then
    echo "FAIL the self-test did not finish in 15 minutes"
    kill $app_pid 2>/dev/null || true
    status=1
    break
  fi
done
quit=0
wait $app_pid || quit=$?
[ $status -ne 0 ] || status=$quit
sleep 1
{ kill $tail_pid; wait $tail_pid; } 2>/dev/null || true
# Quit before it was done is no pass. LB_STEPS=stock (or logbook) runs that
# part of the self-test alone; LB_SNAPSHOTS=<dir> keeps pictures of windows.
grep -q "^self-test done" "$out" || { echo "FAIL the self-test did not finish"; status=1; }
rm -f "$out"
[ $status -eq 0 ] || { echo "the server's log:"; cat "$log"; }
exit $status
