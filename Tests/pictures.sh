#!/bin/sh
# The README's pictures: a server of its own filled with the sample logbook
# (Tests/sample-logbook.py), and the desktop app's self-test, in its
# pictures steps, writing the main window's tabs into a folder: on macOS
# <name>.png (screencapture, the window alone) beside <name>.tiff; on
# GNUstep <name>.tiff.
#
#   Tests/pictures.sh build/logbook-server build/Logbook.app/Contents/MacOS/Logbook out [app arguments]
#   xvfb-run -a Tests/pictures.sh obj/logbook-server Logbook.app/Logbook out     (GNUstep)
#
# A light Mac's look on any Mac: -NSRequiresAquaSystemAppearance YES.
set -e
server=$1; app=$2; out=$3
shift 3
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"; out=$(cd "$out" && pwd)
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
log=$(mktemp)
"$server" -StoreURL Temporary -Port "$port" -Localhost YES >"$log" 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$log"' EXIT
up=no
for i in $(seq 1 600); do
  curl -sf "http://127.0.0.1:$port/odata/" >/dev/null 2>&1 && { up=yes; break; }
  sleep 0.1
done
[ $up = yes ] || { echo "pictures: the server did not answer in 60 s"; cat "$log"; exit 1; }
python3 "$here/sample-logbook.py" "http://127.0.0.1:$port/odata/" alex@example.org
LB_STEPS=pictures LB_SNAPSHOTS="$out" "$app" --self-test "http://127.0.0.1:$port/odata/" -NSQuitAlwaysKeepsWindows NO "$@"
ls "$out"
