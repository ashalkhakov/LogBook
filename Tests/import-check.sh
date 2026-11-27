#!/bin/sh
# logbook-import (Server/LBImportTool.m) against a server of its own: a
# temporary store on a free port on loopback, no sign-in asked for. Anna,
# Ben who drives her Golf, and the Golf made over OData; then Drivvo's
# export (Tests/drivvo-export.csv) imported into it:
#
# - without -LeaveOut: what Logbook has no place for said, nothing made, 1;
# - with it: its fill-ups and service made, synced, on the server;
# - again: nothing made, each passed over, 0;
# - no -Vehicle: her Golf found (by its name), nothing made, 0;
# - into a vehicle she does not own: refused, by name, 1.
#
#   Tests/import-check.sh build/logbook-server build/logbook-import Tests/drivvo-export.csv
set -e
server=$1
tool=$2
export_file=$3
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
log=$(mktemp)
out=$(mktemp)
"$server" -StoreURL Temporary -Port "$port" -Localhost YES -AccessLog NO >"$log" 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null || true; rm -f "$log" "$out"' EXIT
root="http://127.0.0.1:$port/odata"
up=no
for i in $(seq 1 600); do
  curl -sf "$root/" >/dev/null 2>&1 && { up=yes; break; }
  sleep 0.1
done
[ $up = yes ] || { echo "import-check: the server did not answer in 60 s; its log:"; cat "$log"; exit 1; }
failed=0
check() {
  if [ "$2" = yes ]; then echo "ok   $1"; else echo "FAIL $1: $3"; failed=$((failed + 1)); fi
}
post() {
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' "$root/$1" -d "$2")
  [ "$code" = 201 ] || { echo "FAIL $1 made: $code"; exit 1; }
}
count() {
  curl -s "$root/$1?\$count=true&\$top=0" | python3 -c 'import json, sys; print(json.load(sys.stdin)["@odata.count"])'
}
post Users '{"Email":"anna@example.org","PersonName":"Anna Driver","Currency":"EUR","TimeZone":"Europe/Berlin"}'
post Users '{"Email":"ben@example.org","PersonName":"Ben Driver"}'
# Anna's Golf, made as Stock makes an asset (her MakeAsset action).
golf=$(curl -s -X POST -H 'Content-Type: application/json' "$root/Users('anna@example.org')/Default.MakeAsset" \
  -d '{"Name":"Golf","Make":"Volkswagen","Model":"Golf","Kind":"Car","Year":2016,"Fuel":"Petrol","Day":"2000-01-01T00:00:00Z"}' \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["Id"].lower())')
[ -n "$golf" ] || { echo "FAIL the Golf made"; exit 1; }
post VehicleDrivers "{\"Id\":\"$(python3 -c 'import uuid; print(uuid.uuid4())')\",\"Vehicle@odata.bind\":\"Assets($golf)\",\"User@odata.bind\":\"Users('ben@example.org')\"}"
items_before=$(count ServiceItems)

status=0
"$tool" -Server "http://127.0.0.1:$port/" -Email anna@example.org -Vehicle Golf "$export_file" >"$out" 2>&1 || status=$?
said=no
grep -q "payment method 'Card'" "$out" && grep -q "nothing imported" "$out" && said=yes
check "without -LeaveOut: what has no place said, nothing made, 1" \
  "$([ $status = 1 ] && [ $said = yes ] && [ "$(count ServiceItems)" = "$items_before" ] && echo yes)" "$(cat "$out")"

status=0
"$tool" -Server "http://127.0.0.1:$port/" -Email anna@example.org -Vehicle Golf -LeaveOut YES "$export_file" >"$out" 2>&1 || status=$?
check "with it: 4 made, synced, the service's 2 tasks on the server" \
  "$([ $status = 0 ] && grep -q '^4 made, 0 there already' "$out" && grep -q 'on the server now' "$out" \
     && [ "$(count ServiceItems)" = $((items_before + 2)) ] && echo yes)" "$(cat "$out")"

status=0
"$tool" -Server "http://127.0.0.1:$port/" -Email anna@example.org -Vehicle Golf -LeaveOut YES "$export_file" >"$out" 2>&1 || status=$?
check "again: nothing made, the 4 passed over, 0" \
  "$([ $status = 0 ] && grep -q '^0 made, 4 there already' "$out" && [ "$(count ServiceItems)" = $((items_before + 2)) ] && echo yes)" \
  "$(cat "$out")"

status=0
"$tool" -Server "http://127.0.0.1:$port/" -Email anna@example.org -LeaveOut YES "$export_file" >"$out" 2>&1 || status=$?
check "no -Vehicle: her Golf found by its name, nothing made, 0" \
  "$([ $status = 0 ] && grep -q 'into Golf (by its name)' "$out" && grep -q '^0 made, 4 there already' "$out" && echo yes)" "$(cat "$out")"

status=0
"$tool" -Server "http://127.0.0.1:$port/" -Email anna@example.org -Vehicle Polo -LeaveOut YES "$export_file" >"$out" 2>&1 || status=$?
check "a vehicle she does not own: refused, by name, 1" \
  "$([ $status = 1 ] && grep -q 'no vehicle named Polo (Golf)' "$out" && echo yes)" "$(cat "$out")"

echo "import tool: $failed failed"
[ $failed = 0 ] || { echo "the server's log:"; cat "$log"; exit 1; }
