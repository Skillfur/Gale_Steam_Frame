#!/bin/bash
# Build the SvelteKit frontend and cross-compile Gale for aarch64-unknown-linux-gnu
# against the arm64 sysroot made by setup-sysroot.sh.
#
# Needs on the host: Rust with the aarch64-unknown-linux-gnu target, Node.js,
# pnpm, pkg-config, and an aarch64-linux-gnu GCC cross toolchain.
#
#   SYSROOT       arm64 sysroot (default: build/sysroot)
#   GALE          Gale source tree (default: the gale/ submodule)
#   CROSS_PREFIX  cross toolchain prefix (default: aarch64-linux-gnu-)
set -euo pipefail

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SYSROOT=$(realpath "${SYSROOT:-$REPO/build/sysroot}")
GALE=$(realpath "${GALE:-$REPO/gale}")
CROSS_PREFIX="${CROSS_PREFIX:-aarch64-linux-gnu-}"
TARGET=aarch64-unknown-linux-gnu

test -f "$GALE/src-tauri/Cargo.toml" || {
  echo "Gale source not found at $GALE (run: git submodule update --init)" >&2
  exit 1
}
test -f "$SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig/webkit2gtk-4.1.pc" || {
  echo "sysroot not ready at $SYSROOT (run scripts/setup-sysroot.sh)" >&2
  exit 1
}

# Compiler wrappers, so every C/C++ compile and link (cc-rs build scripts and
# the final rustc link) uses the sysroot.
BIN="$REPO/build/cross-bin"
mkdir -p "$BIN"
for tool in gcc g++; do
  printf '#!/bin/sh\nexec %s%s --sysroot="%s" "$@"\n' "$CROSS_PREFIX" "$tool" "$SYSROOT" > "$BIN/aarch64-$tool"
  chmod 755 "$BIN/aarch64-$tool"
done

export PKG_CONFIG_ALLOW_CROSS=1
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig:$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
unset PKG_CONFIG_PATH
export CC_aarch64_unknown_linux_gnu="$BIN/aarch64-gcc"
export CXX_aarch64_unknown_linux_gnu="$BIN/aarch64-g++"
export AR_aarch64_unknown_linux_gnu="${CROSS_PREFIX}ar"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="$BIN/aarch64-gcc"

cd "$GALE"
pnpm install --frozen-lockfile
# Same command upstream's release uses (via tauri-action), minus the x86_64
# bundlers: runs `pnpm run build` for the frontend, then cargo with the
# custom-protocol feature so the UI is embedded in the binary.
pnpm tauri build --target "$TARGET" --no-bundle --ci

BINARY="$GALE/src-tauri/target/$TARGET/release/gale"
file "$BINARY"
file -b "$BINARY" | grep -q 'ARM aarch64' || { echo "not an aarch64 binary: $BINARY" >&2; exit 1; }
