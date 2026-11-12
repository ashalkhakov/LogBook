#!/bin/sh
# The model's fill-up form (Tests/LBFormCheck.m) against a store of its own,
# then against a server of its own: a temporary store, on a free port on
# loopback.
#
#   Tests/form-check.sh build/logbook-server build/lb-form-check build/Logbook.momd build/Logbook.ormplans build/Model/Forms
set -e
server=$1
check=$2
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
log=$(mktemp)
"$server" -StoreURL Temporary -Port "$port" -Localhost YES -AccessLog NO >"$log" 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null; wait 2>/dev/null; rm -f "$log"' EXIT
root="http://127.0.0.1:$port/odata/"
# Up to a minute: a CI runner can be slow to start it.
up=no
for i in $(seq 1 600); do
  curl -sf "$root" >/dev/null 2>&1 && { up=yes; break; }
  sleep 0.1
done
[ $up = yes ] || { echo "form-check: the server did not answer in 60 s; its log:"; cat "$log"; exit 1; }
status=0
"$check" "$3" "$4" "$5" "$root" || status=$?
[ $status -eq 0 ] || { echo "the server's log:"; cat "$log"; }
exit $status
