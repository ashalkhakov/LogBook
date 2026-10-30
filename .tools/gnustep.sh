#!/bin/sh
# Run a command inside Logbook's GNUstep image (logbook-gnustep:
# .tools/gnustep.Dockerfile, on the releases .github/pins.env names), with
# this checkout mounted as it is here.
#
#   .tools/gnustep.sh make check
#
# An unreleased fix to a dependency can be tried by mounting its checkout
# too (GNUSTEP_MOUNTS="-v /path/to/ODataKit:/src/ODataKit") and installing
# it over the released one first, in the same command.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
image=logbook-gnustep:latest
docker image inspect "$image" >/dev/null 2>&1 || {
  echo "$image has not been built: docker build -f .tools/gnustep.Dockerfile -t $image ." >&2
  exit 1
}
exec docker run --rm -t -v "$here":/src/LogBook $GNUSTEP_MOUNTS -w /src/LogBook "$image" \
  sh -c '. /opt/gnustep/System/Library/Makefiles/GNUstep.sh; xvfb-run -a "$@"' -- "$@"
