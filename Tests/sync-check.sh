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
# Each waited for up to a minute: a CI runner can be slow to start them.
for i in $(seq 1 600); do
  [ -f "$tokens" ] && break
  sleep 0.1
done
[ -f "$tokens" ] || { echo "sync-check: Tests/issuer.py wrote no tokens in 60 s"; exit 1; }
url=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["url"])' "$tokens")
"$server" -StoreURL Temporary -Port "$port" -Localhost YES -AccessLog NO -JWTIssuer "$url" -AllowAnonymous NO >"$log" 2>&1 &
pid=$!
root="http://127.0.0.1:$port/odata/"
up=no
for i in $(seq 1 600); do
  curl -s -o /dev/null "$root" 2>/dev/null && { up=yes; break; }
  sleep 0.1
done
[ $up = yes ] || { echo "sync-check: the server did not answer in 60 s; its log:"; cat "$log"; exit 1; }
python3 "$here/seed.py" "$root" "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["tokens"]["anna@example.org"])' "$tokens")"
export LB_TOKENS="$tokens"
status=0
"$check" "$root" "$3" "$4" "$here/receipt-photo.jpg" &
checkpid=$!
# DIAGNOSTIC (temporary): on Windows, both processes' stacks mid-stall.
case "$(uname -s)" in MINGW*|MSYS*)
  ( for at in 40 50; do
      sleep 10; [ $at = 40 ] && sleep 30
      kill -0 $checkpid 2>/dev/null || exit 0
      echo "=== DIAG at ${at}s: sockets"; netstat -ano -p tcp | grep -E "127.0.0.1:$port"
      for p in $pid $checkpid; do
        w=$(cat /proc/$p/winpid 2>/dev/null)
        echo "=== DIAG at ${at}s: stacks of $p (win $w)"
        gdb -batch -p "$w" -ex "thread apply all bt 25" 2>&1 | grep -vE "^\[New Thread|^warning:"
      done
    done ) &
  diag=$!
;; esac
wait $checkpid || status=$?
kill ${diag:-} 2>/dev/null || true
[ $status -eq 0 ] || { echo "the server's log:"; cat "$log"; }
exit $status
