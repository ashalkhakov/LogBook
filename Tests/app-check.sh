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
for i in $(seq 1 100); do
  curl -sf "http://127.0.0.1:$port/odata/" >/dev/null 2>&1 && break
  sleep 0.1
done
status=0
out=$(mktemp)
"$app" --self-test "http://127.0.0.1:$port/odata/" -NSQuitAlwaysKeepsWindows NO >"$out" 2>&1 || status=$?
cat "$out"
# Quit before it was done is no pass.
grep -q "^self-test done" "$out" || { echo "FAIL the self-test did not finish"; status=1; }
rm -f "$out"
[ $status -eq 0 ] || { echo "the server's log:"; cat "$log"; }
exit $status
