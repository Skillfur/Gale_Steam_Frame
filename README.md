# Gale for Steam Frame

The [Gale](https://github.com/Kesomannen/gale) mod manager built as an
**aarch64 AppImage** for the Steam Frame (may work on other platforms as well).
Gale itself is unmodified, this repository only packages it.

## Install

On the Steam Frame, in Desktop Mode, open a terminal and run (run it again to update):

    curl -fsSL https://raw.githubusercontent.com/Skillfur/Gale_Steam_Frame/HEAD/install.sh | bash

Then in Thunar open `~/Applications`, click the analog on the AppImage and choose **Add to Steam**.

**Manual install:** download the AppImage from *Releases* into `~/Applications`, open its
**Properties → Permissions → Allow Execution** in Thunar and add it to Steam as above.

Don't use Gale's built-in updater as it's only aware of the official x86_64 builds.

To uninstall:

    rm ~/Applications/Gale-Aarch64.AppImage ~/.local/share/applications/gale-aarch64.desktop ~/.local/share/icons/gale-aarch64.png

## Steam Frame specific fixes

- **WebKit helper path.** Debian's WebKitGTK starts its helpers from a path SteamOS lacks,
  so it is rewritten to `/tmp/gale-webkit2gtk-4.1`, where `AppRun` links the bundled helpers.
- **Shared-memory rendering.** The dma-buf path draws a blank window on this GPU.
- **No WebKit sandbox.** bubblewrap cannot see the relocated helpers.

## Building

| Workflow | What it does |
| --- | --- |
| `Build AppImage (aarch64)` | Runs on every push and uploads the AppImage. *Run workflow* with a *release* tag publishes a release with the notes from `RELEASE_NOTES.md`. |
| `Vendor Debian libraries` | Manual. Refreshes the Debian arm64 libraries in `vendor/`. |

**New Gale release**

    git -C gale fetch --tags origin && git -C gale checkout <tag>
    git commit -am "Gale <tag>" && git push

**Local build** (x86_64 Debian 13, as root, with the packages from `.github/workflows/build-appimage.yml`):

    git submodule update --init && scripts/build-appimage.sh

## Licenses

Gale is GPL-3.0. The bundled libraries are Debian builds, mostly LGPL; their copyright
files are in `share/doc/` inside the AppImage. The AppImage runtime is MIT licensed.
