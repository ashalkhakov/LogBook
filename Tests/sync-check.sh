#!/bin/sh
# The offline store (Tests/LBSyncCheck.m) against a server of its own: a
# temporary store, on a free port on loopback, signed in to as the
# devices' users are (JWT access tokens of Tests/issuer.py's, LB_TOKENS),
# so that what they send is kept to the permissions; an expense kind of a
# user's seeded (Tests/seed.py); a receipt's photo to sync
# (Tests/receipt-photo.jpg).
#
#   Tests/sync-check.sh build/logbook-server build/lb-sync-check build/Logbook.momd build/Logbook.ormplans
set -e
server=$1
check=$2
here=$(cd "$(dirname "$0")" && pwd)
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
log=$(mktemp)
tokens=$(mktemp -u)
python3 "$here/issuer.py" "$tokens" anna@example.org ben@example.org &
issuer=$!
trap 'kill $issuer $pid 2>/dev/null; wait 2>/dev/null; rm -f "$log" "$tokens"' EXIT
for i in $(seq 1 100); do
  [ -f "$tokens" ] && break
  sleep 0.1
done
url=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["url"])' "$tokens")
"$server" -StoreURL Temporary -Port "$port" -Localhost YES -AccessLog NO -JWTIssuer "$url" -AllowAnonymous NO >"$log" 2>&1 &
pid=$!
root="http://127.0.0.1:$port/odata/"
for i in $(seq 1 100); do
  curl -s -o /dev/null "$root" 2>/dev/null && break
  sleep 0.1
done
python3 "$here/seed.py" "$root" "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["tokens"]["anna@example.org"])' "$tokens")"
export LB_TOKENS="$tokens"
status=0
"$check" "$root" "$3" "$4" "$here/receipt-photo.jpg" || status=$?
[ $status -eq 0 ] || { echo "the server's log:"; cat "$log"; }
exit $status
