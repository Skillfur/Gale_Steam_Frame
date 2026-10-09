#!/bin/bash
# Install or update Gale (aarch64 AppImage) for the Steam Frame:
#
#   curl -fsSL https://raw.githubusercontent.com/Skillfur/Gale_Steam_Frame/HEAD/install.sh | bash
#
# Downloads the AppImage from the latest release of this repository to
# ~/Applications/Gale-Aarch64.AppImage, makes it executable and adds a Gale
# entry to the application menu. Running it again updates Gale.
set -euo pipefail

REPO="Skillfur/Gale_Steam_Frame"
APPS_DIR="$HOME/Applications"
APPIMAGE="$APPS_DIR/Gale-Aarch64.AppImage"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP_FILE="$DESKTOP_DIR/gale-aarch64.desktop"
ICON="${XDG_DATA_HOME:-$HOME/.local/share}/icons/gale-aarch64.png"

die() {
  echo "error: $*" >&2
  exit 1
}

# Everything runs from main, so a download cut short by `curl | bash` cannot
# execute half a script.
main() {
  [ "$(uname -m)" = aarch64 ] || die "this build of Gale is for aarch64 (ARM64) only, this machine is $(uname -m)"
  command -v curl > /dev/null || die "curl is required"

  echo "Looking up the latest release of $REPO..."
  local release urls url sha_url tag
  release=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest") ||
    die "could not read the latest release of $REPO (is there a published release?)"
  tag=$(grep -o '"tag_name": *"[^"]*"' <<< "$release" | head -n 1 | cut -d'"' -f4)
  urls=$(grep -o '"browser_download_url": *"[^"]*"' <<< "$release" | cut -d'"' -f4)
  url=$(grep -- '-aarch64\.AppImage$' <<< "$urls" | head -n 1) ||
    die "release $tag has no aarch64 AppImage"
  sha_url=$(grep -- '-aarch64\.AppImage\.sha256$' <<< "$urls" | head -n 1) || true

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  echo "Downloading $(basename "$url") ($tag)..."
  curl -fL --progress-bar -o "$tmp/Gale-Aarch64.AppImage" "$url"
  if [ -n "$sha_url" ]; then
    local expected actual
    expected=$(curl -fsSL "$sha_url" | cut -d' ' -f1)
    actual=$(sha256sum "$tmp/Gale-Aarch64.AppImage" | cut -d' ' -f1)
    [ "$expected" = "$actual" ] || die "checksum mismatch for the downloaded AppImage"
    echo "Checksum OK."
  fi
  chmod 755 "$tmp/Gale-Aarch64.AppImage"

  # Move into place instead of overwriting, so a running Gale is not disturbed.
  mkdir -p "$APPS_DIR"
  cp "$tmp/Gale-Aarch64.AppImage" "$APPIMAGE.new"
  mv -f "$APPIMAGE.new" "$APPIMAGE"
  echo "Installed $APPIMAGE"

  # The icon is inside the AppImage.
  local icon_line=""
  if (cd "$tmp" && "$APPIMAGE" --appimage-extract gale.png > /dev/null 2>&1) &&
    [ -f "$tmp/squashfs-root/gale.png" ]; then
    mkdir -p "$(dirname "$ICON")"
    cp "$tmp/squashfs-root/gale.png" "$ICON"
    icon_line="Icon=$ICON"
  fi

  mkdir -p "$DESKTOP_DIR"
  cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=Gale
GenericName=Thunderstore mod manager
Comment=Mod manager for Thunderstore (aarch64 build)
Exec="$APPIMAGE" %u
$icon_line
Terminal=false
Categories=Game;
StartupWMClass=gale
MimeType=x-scheme-handler/ror2mm;x-scheme-handler/gale;
EOF
  if command -v update-desktop-database > /dev/null; then
    update-desktop-database "$DESKTOP_DIR" > /dev/null 2>&1 || true
  fi
  echo "Added menu entry $DESKTOP_FILE"
  echo
  echo "Done. Start Gale from the application menu, or add it to Steam as a non-Steam game."
}

main "$@"
