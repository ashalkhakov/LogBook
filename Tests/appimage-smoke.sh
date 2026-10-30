#!/bin/bash
# The AppImage on a clean Ubuntu (no GNUstep, no fonts), as
# gnustep-release-actions' appimage-test runs it (.github/release/appimage.conf,
# SMOKE_SCRIPT), from the repository's root: the image's own server started,
# and the app's self-test driving its windows against it.
#   Tests/appimage-smoke.sh <Logbook AppImage>
set -euo pipefail
image=$1
"$image" --server -StoreURL Temporary -Port 18090 -Localhost YES > /tmp/server.log 2>&1 &
for i in $(seq 1 60); do python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:18090/odata/')" 2>/dev/null && break; sleep 1; done
out=$(mktemp)
status=0
# The whole self-test: over five minutes on a CI runner, from the image.
timeout -k 15 900 xvfb-run -a "$image" --self-test http://127.0.0.1:18090/odata/ -NSQuitAlwaysKeepsWindows NO >"$out" 2>&1 || status=$?
cat "$out"
grep -q "^self-test done" "$out" || { echo "FAIL the self-test did not finish"; status=1; }
[ $status -eq 0 ] || { echo "the server's log:"; cat /tmp/server.log; }
exit $status
