# Logbook's GNUstep box: ORMKit's (ormkit-gnustep, built from
# ../NativeORM2/.tools/gnustep.Dockerfile on the releases its pins name),
# with what Logbook builds on beside it, by the releases .github/pins.env
# names (RDLKit), each an archive unpacked at /.
#
#   docker build -f .tools/gnustep.Dockerfile -t logbook-gnustep .
#   .tools/gnustep.sh make check
FROM ormkit-gnustep
COPY .github/pins.env /tmp/logbook-pins.env
RUN set -e; \
    for name in RDLKIT; do \
      version=$(sed -n "s/^${name}_VERSION=//p" /tmp/logbook-pins.env); \
      repo=$(echo "$name" | tr 'A-Z_' 'a-z-'); \
      curl -fsSL "https://github.com/ashalkhakov/$repo/releases/download/v$version/$repo-$version-ubuntu22.04-$(uname -m).tar.xz" \
        | tar -C / -xJ; \
    done
