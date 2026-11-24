# syntax=docker/dockerfile:1
#
# logbook-server in an image of its own: the server, logbook-import beside
# it, what they read beside them (the model, its tables, the permissions,
# the processes, the forms' contracts), and the shared libraries they run
# on, nothing else (no shell, no package manager). As SimpleNotes' server
# image is (TopoText's Docker/server.Dockerfile), built on the releases
# .github/pins.env names, as CI builds: the GNUstep stack, FreeCoreData with
# its PostgreSQL and MySQL stores, GCDWebServer, ODataKit, ORMKit (its
# ormtool generates from the model), DiagramKit (which ormtool links) and
# WorkflowKit (the processes' engine, and wf-build), each an archive
# unpacked at / (gnustep-release-actions' docker.yml passes their versions
# as build arguments of the same names; built by hand, pins.env's are
# taken); the server from here.
#
#   docker build -f Docker/server.Dockerfile -t logbook-server .
#   docker run -p 8080:8080 -v logbook:/data logbook-server
#
# Its settings are environment variables (LB_ and the setting's name, as
# Server/LBServer.m lists them):
#   LB_STORE_URL     /data/logbook.sqlite (default), or a database's URL
#   LB_STORE_TYPE    SQLite (default), PostgreSQL, MySQL
#   LB_SERVICE_ROOT  the public URL it is reached at (behind a proxy)
#   LB_PORT          8080
#   LB_JWT_ISSUER, LB_TRUSTED_USER_HEADER, LB_ALLOW_ANONYMOUS   signing in
#   ...and every other of HTTPServerKit's (HS_ settings, LB_ here).
# The processes' store is beside a SQLite logbook (/data/Workflow.sqlite),
# else LB_WORKFLOW names it.
#
# logbook-import, another app's export into a user's logbook, runs from the
# same image:
#   docker run --rm -v "$PWD":/in --entrypoint /app/logbook-import logbook-server \
#     -Server https://logbook.example.org/ -Vehicle Golf /in/Drivvo.csv
#
# Not Alpine: GNUstep's runtime (libobjc2, libdispatch, gnustep-base) is
# built and tested on glibc. The final stage is FROM scratch: the libraries
# are glibc's and the stack's, copied from where they were built.

ARG UBUNTU=22.04

FROM ubuntu:${UBUNTU} AS libraries
ARG DEBIAN_FRONTEND=noninteractive
ARG GNUSTEP_PATCHES_VERSION
ARG FREECOREDATA_VERSION
ARG GCDWEBSERVER_VERSION
ARG ODATAKIT_VERSION
ARG ORMKIT_VERSION
ARG DIAGRAMKIT_VERSION
ARG WORKFLOWKIT_VERSION
# Through caching proxies that answer with stale indexes: no pipelining, no
# proxy caches, retries (as ODataKit's images).
RUN printf 'Acquire::http::No-Cache "true";\nAcquire::BrokenProxy "true";\nAcquire::http::Pipeline-Depth "0";\nAcquire::Retries "3";\n' \
      > /etc/apt/apt.conf.d/99-logbook
COPY .github/pins.env /tmp/pins.env
# The archives, the stack first; then the packages building on the stack
# needs (its own list, beside it), and the server's: FreeCoreData's SQLite,
# PostgreSQL and MySQL clients, and the time zones.
RUN set -e; \
    apt-get update; apt-get install -y --no-install-recommends ca-certificates curl xz-utils; \
    for name in GNUSTEP_PATCHES FREECOREDATA GCDWEBSERVER ODATAKIT ORMKIT DIAGRAMKIT WORKFLOWKIT; do \
      eval "version=\${${name}_VERSION:-}"; \
      [ -n "$version" ] || version=$(sed -n "s/^${name}_VERSION=//p" /tmp/pins.env); \
      repo=$(echo "$name" | tr 'A-Z_' 'a-z-'); \
      parts=$(sed -n "s/^${name}_PARTS=\"*\([^\"]*\)\"*$/\1/p" /tmp/pins.env); \
      for archive in "$repo" $(for part in $parts; do echo "$repo-$part"; done); do \
        curl -fsSL "https://github.com/ashalkhakov/$repo/releases/download/v$version/$archive-$version-ubuntu22.04-$(uname -m).tar.xz" \
          | tar -C / -xJ; \
      done; \
    done; \
    grep -v '^#' /opt/gnustep/share/gnustep-patches/packages-ubuntu.txt \
      | xargs apt-get install -y --no-install-recommends libsqlite3-dev libpq-dev libmariadb-dev tzdata; \
    update-alternatives --install /usr/bin/ld ld /usr/bin/ld.gold 10; \
    rm -rf /var/lib/apt/lists/*
ENV CC=clang CXX=clang++ LIBRARY_COMBO=ng-gnu-gnu RUNTIME_VERSION=gnustep-2.0

# The server and logbook-import, alone (LB_SERVER_ONLY: no app, no
# gnustep-gui), with what they read beside them in obj/.
FROM libraries AS build
ARG VERSION=0.0.0
COPY . /usr/src/logbook
WORKDIR /usr/src/logbook
RUN set -e; . /opt/gnustep/System/Library/Makefiles/GNUstep.sh; export LD_LIBRARY_PATH=/opt/gnustep/lib:$LD_LIBRARY_PATH; \
    rm -rf build obj; \
    make -j"$(nproc)" LB_SERVER_ONLY=yes

# What the server needs at run time, at the paths it was built with
# (Docker/collect-server.sh), into /rootfs.
FROM build AS collect
RUN Docker/collect-server.sh /rootfs

FROM scratch AS server
COPY --from=collect /rootfs /
ENV LD_LIBRARY_PATH=/opt/gnustep/lib:/opt/gnustep/Local/Library/Libraries:/opt/gnustep/System/Library/Libraries \
    HOME=/data TZ=UTC \
    LB_PORT=8080 LB_LOCALHOST=NO \
    LB_STORE_URL=/data/logbook.sqlite \
    LB_ACCESS_LOG=json \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
USER 10001:10001
WORKDIR /data
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["/app/logbook-server"]
