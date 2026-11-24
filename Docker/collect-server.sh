#!/bin/bash
# What logbook-server (and logbook-import beside it) needs at run time,
# copied into a root of its own at the paths it was built with, for an
# image FROM scratch (Docker/server.Dockerfile), as SimpleNotes' server's
# is (TopoText's Docker/collect-server.sh):
#
#   * the two executables, and what they read beside them (the GNUmakefile's
#     LB_SERVER_FILES: the model, its tables, the permissions, the processes,
#     the forms' contracts), in /app;
#   * every library ldd finds for them, and for the SQL stores the server
#     loads by name (FreeCoreData's PostgreSQL and MySQL ones, -StoreType);
#   * the framework bundles, which gnustep-base looks for;
#   * glibc's UTF-16 and UTF-32 converters (gnustep-base's strings use them
#     through iconv: a character past 16 bits, an emoji, needs them);
#   * gnustep-base's resources, the time zones (a user's, each record's:
#     what day a moment falls on), and a user to run as;
#   * the CA certificates, which every HTTPS request the server makes needs
#     (an identity provider's discovery document and keys: without them
#     each signed-in request is answered 503), and logbook-import's too.
#
# Debug information is stripped, symbol tables kept: Objective-C methods are
# named only there, and a crash's backtrace is worth them.
#
#   Docker/collect-server.sh /rootfs   (in the build stage, from the source)
set -euo pipefail

root=${1:?the root to fill}
set +u
. /opt/gnustep/System/Library/Makefiles/GNUstep.sh
set -u
export LD_LIBRARY_PATH="/opt/gnustep/lib:${LD_LIBRARY_PATH:-}"

mkdir -p "$root/app" "$root/data" "$root/tmp" "$root/etc"
chmod 1777 "$root/tmp"
tools="logbook-server logbook-import"
for tool in $tools; do cp "obj/$tool" "$root/app/"; done
files=$(sed -n 's/^LB_SERVER_FILES = //p' GNUmakefile)
[ -n "$files" ] || { echo "no LB_SERVER_FILES in the GNUmakefile" >&2; exit 1; }
for f in $files; do
  [ -e "obj/$f" ] || { echo "obj/$f was not built" >&2; exit 1; }
  cp -R "obj/$f" "$root/app/"
done

# A library and what it links: the stack's as they are (links into the
# framework bundles stay links), the system's resolved.
libraries_of() {
  ldd "$1" | awk '/=> \//{print $3} /^\t\/.*ld-linux/{print $1}'
}
copy_library() {
  case "$1" in
    /opt/gnustep/*) cp --parents -a "$1" "$root/"; cp --parents -a "$(readlink -f "$1")" "$root/" ;;
    *) cp --parents -L "$1" "$root/" ;;
  esac
}

stores=$(find /opt/gnustep -name 'libCD*Store.so' | sort)
[ -n "$stores" ] || { echo "no SQL stores (libCD*Store.so) in /opt/gnustep" >&2; exit 1; }
for f in $(for tool in $tools; do echo "$root/app/$tool"; done) $stores; do
  case "$f" in
    "$root"/app/*) ;;
    *) for link in "${f}"*; do copy_library "$link"; done ;;
  esac
  for lib in $(libraries_of "$f"); do copy_library "$lib"; done
done
for tool in $tools; do
  if ldd "$root/app/$tool" | grep -q 'not found'; then
    ldd "$root/app/$tool" >&2
    exit 1
  fi
done

for fw in $(find /opt/gnustep -maxdepth 4 -name '*.framework' -type d); do
  cp --parents -a "$fw" "$root/"
  rm -rf "$root$fw/Headers" "$root$fw"/Versions/*/Headers
done

gconv=$(dirname "$(find /usr/lib -path '*gconv*' -name UTF-16.so | head -n 1)")
mkdir -p "$root$gconv"
cp -a "$gconv/gconv-modules" "$gconv/UTF-16.so" "$gconv/UTF-32.so" "$gconv/UNICODE.so" "$root$gconv/"
[ ! -d "$gconv/gconv-modules.d" ] || cp -a "$gconv/gconv-modules.d" "$root$gconv/"

# The libraries' resources, beside them (Libraries/<library>): gnustep-base's,
# and WorkflowKit's model (WorkflowKit.momd), which it opens its store with.
# gnustep-gui's and opal's are no server's; pkg-config's are a build's.
for dir in $(find /opt/gnustep -path '*/Library/Libraries/*' -mindepth 1 -maxdepth 4 -type d -prune 2>/dev/null \
               | grep -E '/Library/Libraries/[^/]+$' | grep -v -E '/(gnustep-gui|opal|pkgconfig)$'); do
  cp --parents -a "$dir" "$root/"
done
[ -e "$(find "$root/opt/gnustep" -name WorkflowKit.momd | head -n 1)" ] || { echo "no WorkflowKit.momd collected" >&2; exit 1; }
[ ! -d /opt/gnustep/etc ] || cp --parents -a /opt/gnustep/etc "$root/"

bundle=/etc/ssl/certs/ca-certificates.crt
[ -s "$bundle" ] || { echo "no CA certificates at $bundle (ca-certificates)" >&2; exit 1; }
mkdir -p "$root/etc/ssl/certs"
cp -L "$bundle" "$root$bundle"

# Every zone, not only UTC: a record's day is taken in its time zone, or
# its vehicle's owner's ("Asia/Almaty"), and a rule compares days.
mkdir -p "$root/usr/share"
cp -a /usr/share/zoneinfo "$root/usr/share/"
ln -sf /usr/share/zoneinfo/UTC "$root/etc/localtime"
echo 'logbook:x:10001:10001:logbook:/data:/nonexistent' > "$root/etc/passwd"
echo 'logbook:x:10001:' > "$root/etc/group"
chown 10001:10001 "$root/data"

find "$root" -type f \( -name '*.so*' -o -path '*/app/logbook-server' -o -path '*/app/logbook-import' \) -exec strip --strip-debug {} \;
du -sh "$root"
