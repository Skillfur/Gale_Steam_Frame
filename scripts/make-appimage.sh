#!/bin/bash
# Turn the portable tree from pack_gale.py into a single-file aarch64 AppImage:
# the vendored AppImage type2 runtime followed by a zstd squashfs of the tree.
# Can run on any host architecture.
#
#   APPDIR   portable tree (default: build/AppDir)
#   OUT      output file (default: dist/Gale-<version>-aarch64.AppImage)
set -euo pipefail

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
APPDIR="${APPDIR:-$REPO/build/AppDir}"
RUNTIME_DIR="$REPO/vendor/appimage-runtime"
RUNTIME="$RUNTIME_DIR/runtime-aarch64"

for f in AppRun gale.bin gale.desktop gale.png share/build-id; do
  test -e "$APPDIR/$f" || { echo "$APPDIR is missing $f (run packaging/pack_gale.py)" >&2; exit 1; }
done
VERSION=$(sed -n 's/^X-AppImage-Version=//p' "$APPDIR/gale.desktop")
OUT="${OUT:-$REPO/dist/Gale-$VERSION-aarch64.AppImage}"

(cd "$RUNTIME_DIR" && sha256sum --quiet --strict -c SHA256SUMS)
file -b "$RUNTIME" | grep -q 'ARM aarch64'

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
rm -rf "$APPDIR/cache"
mksquashfs "$APPDIR" "$WORK/app.squashfs" \
  -root-owned -noappend -no-xattrs -comp zstd -Xcompression-level 19 -b 1M -quiet

mkdir -p "$(dirname "$OUT")"
cat "$RUNTIME" "$WORK/app.squashfs" > "$OUT"
chmod 755 "$OUT"
(cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
ls -lh "$OUT"
echo "built $OUT"
