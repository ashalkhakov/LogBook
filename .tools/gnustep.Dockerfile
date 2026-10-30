# Logbook's GNUstep box: Ubuntu 22.04 with what Logbook builds on, by the
# releases .github/pins.env names -- the GNUstep stack, FreeCoreData (and the
# parts pins.env names of it), GCDWebServer, ODataKit, ORMKit and RDLKit --
# each an archive unpacked at /, as gnustep-release-actions' scripts/deps.sh
# unpacks them for CI; the packages the stack lists, and Xvfb for the app's
# check.
#
#   docker build -f .tools/gnustep.Dockerfile -t logbook-gnustep .
#   .tools/gnustep.sh make check
FROM ubuntu:22.04
ARG DEBIAN_FRONTEND=noninteractive
COPY .github/pins.env /tmp/pins.env
RUN set -e; \
    apt-get update; apt-get install -y --no-install-recommends ca-certificates curl xz-utils; \
    for name in GNUSTEP_PATCHES FREECOREDATA GCDWEBSERVER ODATAKIT ORMKIT RDLKIT; do \
      version=$(sed -n "s/^${name}_VERSION=//p" /tmp/pins.env); \
      repo=$(echo "$name" | tr 'A-Z_' 'a-z-'); \
      parts=$(sed -n "s/^${name}_PARTS=\"*\([^\"]*\)\"*$/\1/p" /tmp/pins.env); \
      for archive in "$repo" $(for part in $parts; do echo "$repo-$part"; done); do \
        curl -fsSL --retry 5 --retry-all-errors \
          "https://github.com/ashalkhakov/$repo/releases/download/v$version/$archive-$version-ubuntu22.04-$(uname -m).tar.xz" \
          | tar -C / -xJ; \
      done; \
    done; \
    grep -v '^#' /opt/gnustep/share/gnustep-patches/packages-ubuntu.txt \
      | xargs apt-get install -y --no-install-recommends libsqlite3-dev libpq-dev libmariadb-dev \
          python3 xvfb xauth make; \
    update-alternatives --install /usr/bin/ld ld /usr/bin/ld.gold 10; \
    rm -rf /var/lib/apt/lists/*
ENV CC=clang CXX=clang++ LIBRARY_COMBO=ng-gnu-gnu RUNTIME_VERSION=gnustep-2.0
