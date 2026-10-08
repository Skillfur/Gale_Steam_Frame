#!/bin/bash
# shellcheck disable=SC2016 # dpkg-deb --showformat strings are literal
# Unpack the vendored arm64 .deb files into a sysroot. Works offline: nothing
# is downloaded, and every .deb is checked against SHA256SUMS first.
#
#   SYSROOT  where to unpack (default: build/sysroot)
#   VENDOR   vendored package directory (default: vendor/debian-trixie-arm64)
set -euo pipefail

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
VENDOR="${VENDOR:-$REPO/vendor/debian-trixie-arm64}"
SYSROOT=$(realpath -m "${SYSROOT:-$REPO/build/sysroot}")

shopt -s nullglob
debs=("$VENDOR/debs"/*.deb)
if [ "${#debs[@]}" -eq 0 ]; then
  echo "no vendored packages in $VENDOR/debs" >&2
  echo "run the 'Vendor Debian libraries' workflow or scripts/vendor-debs.sh" >&2
  exit 1
fi

(cd "$VENDOR/debs" && sha256sum --quiet --strict -c ../SHA256SUMS)
listed=$(grep -c . "$VENDOR/SHA256SUMS")
if [ "$listed" -ne "${#debs[@]}" ]; then
  echo "SHA256SUMS lists $listed files but debs/ has ${#debs[@]}" >&2
  exit 1
fi

rm -rf "$SYSROOT"
# Debian 13 is merged-/usr. Create the top-level links first so that both
# /lib/... and /usr/lib/... paths (as used in libc.so) land in the same place.
mkdir -p "$SYSROOT/usr/lib" "$SYSROOT/usr/bin" "$SYSROOT/usr/sbin"
ln -s usr/lib "$SYSROOT/lib"
ln -s usr/bin "$SYSROOT/bin"
ln -s usr/sbin "$SYSROOT/sbin"

# File lists per package, like /var/lib/dpkg/info/*.list. pack_gale.py uses
# them to ship the copyright file of every package it bundles files from.
mkdir -p "$SYSROOT/.vendor"
for deb in "${debs[@]}"; do
  id=$(dpkg-deb --show --showformat='${Package}=${Version}' "$deb")
  dpkg-deb --fsys-tarfile "$deb" |
    tar -C "$SYSROOT" --keep-directory-symlink --no-same-owner --no-same-permissions -xvf - \
      > "$SYSROOT/.vendor/$id.list"
done

# Absolute symlinks would point into the build host's own /usr. Make them
# relative so the linker and pack_gale.py stay inside the sysroot.
while IFS= read -r -d '' link; do
  target=$(readlink "$link")
  ln -sfn "$(realpath -m -s --relative-to="$(dirname "$link")" "$SYSROOT$target")" "$link"
done < <(find "$SYSROOT" -type l -lname '/*' -print0)

for f in \
  usr/lib/aarch64-linux-gnu/pkgconfig/webkit2gtk-4.1.pc \
  usr/lib/aarch64-linux-gnu/pkgconfig/gtk+-3.0.pc \
  usr/lib/aarch64-linux-gnu/webkit2gtk-4.1/WebKitNetworkProcess \
  usr/lib/aarch64-linux-gnu/libc.so; do
  test -e "$SYSROOT/$f" || { echo "sysroot is missing $f" >&2; exit 1; }
done
echo "sysroot ready at $SYSROOT (${#debs[@]} packages)"
