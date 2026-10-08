#!/bin/bash
# Start the aarch64 AppImage on an x86_64 host and take a screenshot.
#
# gale.bin runs under qemu user-mode emulation on a virtual X display (Xvfb).
# WebKit starts its helper processes from /tmp/gale-webkit2gtk-4.1 (the path
# patched into libwebkit2gtk), so here that directory holds small wrappers
# that run each helper through qemu as well. The environment is the one
# AppRun sets up. The test fails if Gale exits before the screenshot, e.g.
# when WebKit aborts.
#
#   launch-test.sh <file.AppImage> <screenshot.png>
#   SYSROOT  arm64 sysroot that provides the host libraries (default: build/sysroot)
#   WAIT     seconds to let the UI render after the web process starts (default: 90)
#
# Needs: qemu-user, Xvfb, xwd, xwdtopnm/pnmtopng (netpbm), dbus-run-session, fonts.
set -euo pipefail

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
APPIMAGE=$(realpath "$1")
SHOT=$(realpath -m "$2")
SYSROOT=$(realpath "${SYSROOT:-$REPO/build/sysroot}")
WAIT="${WAIT:-90}"
QEMU="${QEMU:-$(command -v qemu-aarch64-static || command -v qemu-aarch64)}"
DISPLAY_NUM=:97

WORK=$(mktemp -d)
WK=/tmp/gale-webkit2gtk-4.1
cleanup() {
  [ -n "${GALE_PID:-}" ] && kill "$GALE_PID" 2> /dev/null
  pkill -f "$WORK/squashfs-root/" 2> /dev/null || true
  [ -n "${XVFB_PID:-}" ] && kill "$XVFB_PID" 2> /dev/null
  rm -rf "$WORK" "$WK"
}
trap cleanup EXIT

cd "$WORK"
"$QEMU" "$APPIMAGE" --appimage-extract > /dev/null
APP="$WORK/squashfs-root"

rm -rf "$WK"
mkdir -p "$WK/injected-bundle"
for helper in WebKitNetworkProcess WebKitWebProcess WebKitGPUProcess; do
  printf '#!/bin/sh\nexec %s -L %s %s/libexec/%s "$@"\n' "$QEMU" "$SYSROOT" "$APP" "$helper" > "$WK/$helper"
  chmod 755 "$WK/$helper"
done
ln -s "$APP/libexec/injected-bundle/libwebkit2gtkinjectedbundle.so" "$WK/injected-bundle/"

mkdir -p home xdg cache
chmod 700 xdg
sed "s#@PREFIX@#$APP#g" "$APP/share/loaders.cache.in" > cache/loaders.cache

Xvfb "$DISPLAY_NUM" -screen 0 1280x800x24 -nolisten tcp > xvfb.log 2>&1 &
XVFB_PID=$!
sleep 2

env -i PATH=/usr/bin:/bin HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/xdg" \
  DISPLAY="$DISPLAY_NUM" GDK_BACKEND=x11 NO_AT_BRIDGE=1 \
  LD_LIBRARY_PATH="$APP/lib" GIO_MODULE_DIR="$APP/lib/gio/modules" \
  GSETTINGS_SCHEMA_DIR="$APP/share/glib-2.0/schemas" XDG_DATA_DIRS="/usr/share:$APP/share" \
  GDK_PIXBUF_MODULE_FILE="$WORK/cache/loaders.cache" \
  WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 WEBKIT_DISABLE_DMABUF_RENDERER=1 \
  WEBKIT_DISABLE_COMPOSITING_MODE=1 \
  dbus-run-session -- "$QEMU" -L "$SYSROOT" "$APP/gale.bin" > gale.log 2>&1 &
GALE_PID=$!

fail() {
  echo "launch test failed: $1" >&2
  echo "--- gale log (last 40 lines) ---" >&2
  tail -n 40 gale.log >&2
  exit 1
}

for _ in $(seq 300); do
  kill -0 "$GALE_PID" 2> /dev/null || fail "Gale exited during startup"
  pgrep -f "$APP/libexec/WebKitWebProcess" > /dev/null && break
  sleep 1
done
pgrep -f "$APP/libexec/WebKitWebProcess" > /dev/null || fail "WebKit web process did not start"
echo "WebKit web process started; waiting ${WAIT}s for the UI to render"
sleep "$WAIT"
kill -0 "$GALE_PID" 2> /dev/null || fail "Gale exited after starting WebKit"
pgrep -f "$APP/libexec/WebKitWebProcess" > /dev/null || fail "WebKit web process died"

mkdir -p "$(dirname "$SHOT")"
xwd -root -silent -display "$DISPLAY_NUM" | xwdtopnm 2> /dev/null | pnmtopng > "$SHOT"
echo "Gale is running; screenshot: $SHOT"
grep -E 'ERROR|WARN|CRITICAL|EGL' gale.log | tail -n 20 || true
