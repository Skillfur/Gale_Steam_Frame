#!/bin/bash
# Smoke-test an aarch64 AppImage on any host through qemu user-mode emulation:
#   1. the embedded runtime runs and can extract its squashfs,
#   2. the extracted tree has the expected layout,
#   3. gale.bin and the WebKit helpers load, with every library and every
#      symbol resolved against the bundled libraries plus the libraries the
#      AppImage expects from the host (EGL, Wayland, libc, ... as listed in
#      share/doc/REQUIREMENTS.txt). The host is simulated by a root that
#      holds only those libraries, copied from the sysroot.
#
#   check-appimage.sh <file.AppImage>
#   SYSROOT  arm64 sysroot (default: build/sysroot)
#   QEMU     qemu user-mode emulator (default: qemu-aarch64-static or qemu-aarch64)
set -euo pipefail

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
APPIMAGE=$(realpath "$1")
SYSROOT=$(realpath "${SYSROOT:-$REPO/build/sysroot}")
QEMU="${QEMU:-$(command -v qemu-aarch64-static || command -v qemu-aarch64)}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
"$QEMU" "$APPIMAGE" --appimage-extract > /dev/null
ROOT="$WORK/squashfs-root"

for f in AppRun gale gale.bin gale.desktop gale.png .DirIcon \
  lib/libwebkit2gtk-4.1.so.0 libexec/WebKitWebProcess libexec/WebKitNetworkProcess \
  libexec/injected-bundle/libwebkit2gtkinjectedbundle.so \
  share/glib-2.0/schemas/gschemas.compiled share/loaders.cache.in share/build-id; do
  test -e "$ROOT/$f" || { echo "AppImage is missing $f" >&2; exit 1; }
done
if grep -aq '/usr/lib/aarch64-linux-gnu/webkit2gtk-4.1' "$ROOT/lib/libwebkit2gtk-4.1.so.0"; then
  echo "libwebkit2gtk-4.1.so.0 still points at the Debian helper directory" >&2
  exit 1
fi

# Fake host root: the host-provided libraries and what they depend on.
HOST="$WORK/host"
HOST_LIBDIR="$HOST/usr/lib/aarch64-linux-gnu"
mkdir -p "$HOST_LIBDIR"
ln -s usr/lib "$HOST/lib"
cp -L "$SYSROOT/usr/lib/ld-linux-aarch64.so.1" "$HOST/usr/lib/"
mapfile -t queue < <(sed -n 's/^  \(lib.*\|ld-linux.*\)$/\1/p' "$ROOT/share/doc/REQUIREMENTS.txt")
test "${#queue[@]}" -gt 0 || { echo "no host libraries listed in REQUIREMENTS.txt" >&2; exit 1; }
while [ "${#queue[@]}" -gt 0 ]; do
  lib=${queue[0]}
  queue=("${queue[@]:1}")
  [ -e "$HOST_LIBDIR/$lib" ] && continue
  src="$SYSROOT/usr/lib/aarch64-linux-gnu/$lib"
  [ -e "$src" ] || continue
  cp -L "$src" "$HOST_LIBDIR/$lib"
  mapfile -t -O "${#queue[@]}" queue < <(readelf -d "$src" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
done
echo "simulated host: $(find "$HOST_LIBDIR" -type f | wc -l) libraries"

status=0
for exe in gale.bin libexec/WebKitWebProcess libexec/WebKitNetworkProcess libexec/WebKitGPUProcess; do
  [ -e "$ROOT/$exe" ] || continue
  # Same as `ldd -r`: list every library and report unresolved symbols.
  out=$(env -i LD_LIBRARY_PATH="$ROOT/lib" LD_TRACE_LOADED_OBJECTS=1 LD_WARN=1 LD_BIND_NOW=1 \
    "$QEMU" -L "$HOST" "$ROOT/$exe" 2>&1) || true
  bundled=$(grep -c "$ROOT/lib/" <<< "$out" || true)
  problems=$(grep -E 'not found|undefined symbol|error while loading' <<< "$out" || true)
  if [ -n "$problems" ]; then
    head -n 20 <<< "$problems"
    echo "FAIL $exe ($(wc -l <<< "$problems") problems)" >&2
    status=1
  else
    echo "ok   $exe ($bundled bundled libraries)"
  fi
done
exit "$status"
