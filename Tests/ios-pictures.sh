#!/bin/bash
# The README's iOS pictures: a server of its own on this Mac filled with the
# sample logbook (Tests/sample-logbook.py), the simulator's app in its
# self-test's pictures steps, and the simulator's screen taken as each tab
# is said ("picture <name>"), into <out>/ios-<name>.png.
#
#   Tests/ios-pictures.sh build/logbook-server build/ios/iphonesimulator/Logbook.app out [device name]
set -u
server=$1; app=$2; out=$3; device=${4:-}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"; out=$(cd "$out" && pwd)
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
root="http://127.0.0.1:$port/odata/"
[ -n "$device" ] || device=$(xcrun simctl list devices available | grep -E '^\s+iPhone' | head -1 | sed -E 's/^ +//; s/ \(.*//')
udid=$(xcrun simctl list devices available | grep -F "    $device (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$udid" ] || { echo "no simulator named $device"; exit 1; }
echo "simulator: $device ($udid)"
xcrun simctl boot "$udid" 2>/dev/null
for i in $(seq 1 120); do
  xcrun simctl list devices | grep -F "($udid) (Booted)" >/dev/null && xcrun simctl spawn "$udid" launchctl print system >/dev/null 2>&1 && break
  sleep 1
done
# The status bar as Apple's own pictures have it.
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null
log=$(mktemp)
"$server" -StoreURL Temporary -Port "$port" -Localhost YES -AccessLog NO > "$log" 2>&1 &
pid=$!
stop() { kill $pid 2>/dev/null; wait $pid 2>/dev/null; rm -f "$log"; xcrun simctl status_bar "$udid" clear 2>/dev/null; }
trap stop EXIT
# Up to a minute: a CI runner can be slow to start it.
up=no
for i in $(seq 1 300); do
  curl -sf "$root" >/dev/null 2>&1 && { up=yes; break; }
  sleep 0.2
done
[ $up = yes ] || { echo "ios-pictures: the server did not answer in 60 s; its log:"; cat "$log"; exit 1; }
python3 "$here/sample-logbook.py" "$root" alex@example.org || exit 1
xcrun simctl install "$udid" "$app" || exit 1
id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
status=1
while IFS= read -r line; do
  line=${line%$'\r'}
  case "$line" in
    "picture "*) xcrun simctl io "$udid" screenshot "$out/ios-${line#picture }.png" >/dev/null 2>&1 && echo "took ios-${line#picture }.png" ;;
    "self-test: passed"*) status=0; echo "$line" ;;
    PASS*|FAIL*|self-test*) echo "$line" ;;
  esac
done < <(SIMCTL_CHILD_LB_STEPS=pictures xcrun simctl launch --console-pty --terminate-running-process "$udid" "$id" --self-test "$root" 2>&1)
exit $status
