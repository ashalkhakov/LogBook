#!/bin/sh
# The offline store (Tests/LBSyncCheck.m) against a server of its own: a
# temporary store, no sign-in, on a free port on loopback, an expense kind
# of a user's seeded (Tests/seed.py); a receipt's photo to sync
# (Tests/receipt-photo.jpg).
#
#   Tests/sync-check.sh build/logbook-server build/lb-sync-check build/Logbook.momd build/Logbook.ormplans
set -e
server=$1
check=$2
here=$(cd "$(dirname "$0")" && pwd)
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
log=$(mktemp)
"$server" -StoreURL Temporary -Port "$port" -Localhost YES -AccessLog NO >"$log" 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$log"' EXIT
root="http://127.0.0.1:$port/odata/"
for i in $(seq 1 100); do
  curl -sf "$root" >/dev/null 2>&1 && break
  sleep 0.1
done
python3 "$here/seed.py" "$root"
status=0
"$check" "$root" "$3" "$4" "$here/receipt-photo.jpg" || status=$?
[ $status -eq 0 ] || { echo "the server's log:"; cat "$log"; }
exit $status
