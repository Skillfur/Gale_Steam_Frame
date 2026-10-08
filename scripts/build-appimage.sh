#!/bin/bash
# Full local build, same steps as .github/workflows/build-appimage.yml:
# vendored .debs -> sysroot -> cross-compiled Gale -> portable tree -> AppImage.
set -euo pipefail
REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
"$REPO/scripts/setup-sysroot.sh"
"$REPO/scripts/build-gale.sh"
python3 "$REPO/packaging/pack_gale.py"
"$REPO/scripts/make-appimage.sh"
