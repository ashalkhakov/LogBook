#!/bin/sh
# The desktop app driven from within (LBSelfTest.h) against a server of its
# own: a temporary store, on a free port on loopback.
#
#   Tests/app-check.sh build/logbook-server build/Logbook.app/Contents/MacOS/Logbook
#   xvfb-run -a Tests/app-check.sh obj/logbook-server Logbook.app/Logbook     (GNUstep)
set -e
server=$1
app=$2
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
# Said as it goes (a run that hangs shows where), and stopped after 15
# minutes where timeout(1) is there (GNU coreutils: Linux, MSYS2).
limit=
command -v timeout >/dev/null 2>&1 && limit="timeout 900"
{ $limit "$app" --self-test "http://127.0.0.1:$port/odata/" -NSQuitAlwaysKeepsWindows NO 2>&1; echo $? >"$out.status"; } | tee "$out"
status=$(cat "$out.status")
[ "$status" = 124 ] && echo "FAIL the self-test did not finish in 15 minutes"
rm -f "$out.status"
# Quit before it was done is no pass. LB_STEPS=stock (or logbook) runs that
# part of the self-test alone; LB_SNAPSHOTS=<dir> keeps pictures of windows.
grep -q "^self-test done" "$out" || { echo "FAIL the self-test did not finish"; status=1; }
rm -f "$out"
[ $status -eq 0 ] || { echo "the server's log:"; cat "$log"; }
exit $status
