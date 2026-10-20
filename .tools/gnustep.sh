#!/bin/sh
# Run a command inside Logbook's GNUstep image (logbook-gnustep: ORMKit's,
# ormkit-gnustep, with RDLKit; .tools/gnustep.Dockerfile), with this
# checkout and ORMKit's beside it mounted as they are here.
#
#   .tools/gnustep.sh make check
#
# An unreleased fix to a dependency can be tried by mounting its checkout
# too (GNUSTEP_MOUNTS="-v /path/to/ODataKit:/src/ODataKit") and installing
# it over the released one first, in the same command.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
ormkit=$(cd "$here/../NativeORM2" && pwd)
image=logbook-gnustep:latest
docker image inspect "$image" >/dev/null 2>&1 || {
  echo "$image has not been built: in ../NativeORM2, docker build -f .tools/gnustep.Dockerfile -t ormkit-gnustep ." >&2
  echo "then here, docker build -f .tools/gnustep.Dockerfile -t $image ." >&2
  exit 1
}
exec docker run --rm -t -v "$here":/src/LogBook -v "$ormkit":/src/NativeORM2 $GNUSTEP_MOUNTS -w /src/LogBook "$image" \
  sh -c '. /opt/gnustep/System/Library/Makefiles/GNUstep.sh; xvfb-run -a "$@"' -- "$@"
