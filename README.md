# Gale for Steam Frame (aarch64 AppImage)

The [Gale](https://github.com/Kesomannen/gale) mod manager built as an
**aarch64 AppImage** for the Steam Frame (SteamOS on ARM). Upstream Gale only
publishes x86_64 builds.

Gale is unmodified: it is the `gale/` git submodule, pinned to an upstream
release tag. This repository only holds the packaging around it.

## Install

On the Steam Frame, in Desktop Mode, open a terminal and run:

    curl -fsSL https://raw.githubusercontent.com/Skillfur/Gale_Steam_Frame/HEAD/install.sh | bash

[`install.sh`](install.sh) downloads the latest release to
`~/Applications/Gale-Aarch64.AppImage`, makes it executable and adds Gale to
the application menu. Run it again to update.

To add Gale to Steam, open `~/Applications` in Thunar, click the analog on
the AppImage to open the context menu and choose **Add to Steam**. It appears
in the *Non-Steam* category.

**Manual install:** download the AppImage from *Releases* into a folder such
as `~/Applications`, then in Thunar open its **Properties → Permissions →
Allow Execution** and add it to Steam as above.

Don't use Gale's built-in updater, it only knows about the official x86_64
builds.

To uninstall:

    rm ~/Applications/Gale-Aarch64.AppImage ~/.local/share/applications/gale-aarch64.desktop ~/.local/share/icons/gale-aarch64.png

## Steam Frame specific fixes

Applied by `packaging/` when the AppImage is built:

- **WebKit helper path.** Debian's WebKitGTK always starts its helpers from
  `/usr/lib/aarch64-linux-gnu/webkit2gtk-4.1/`, which SteamOS lacks (WebKit
  dies with *Trace/breakpoint trap*). The path is rewritten to
  `/tmp/gale-webkit2gtk-4.1`, where `AppRun` links the bundled helpers.
- **Shared-memory rendering.** `WEBKIT_DISABLE_DMABUF_RENDERER=1` and
  `WEBKIT_DISABLE_COMPOSITING_MODE=1`, because the dma-buf path draws a blank
  window on this GPU.
- **No WebKit sandbox.** bubblewrap cannot see the relocated helpers.

## Building

| Workflow | Runs on | What it does |
| --- | --- | --- |
| `Build AppImage (aarch64)` | pushes, tags, PRs, manual | Builds and tests the AppImage. A tag also publishes a release, which `install.sh` picks up. |
| `Vendor Debian libraries` | manual | Refreshes the Debian arm64 libraries in `vendor/` (e.g. WebKitGTK security updates) and starts a build. |

**New Gale release**

    git -C gale fetch --tags origin
    git -C gale checkout 1.22.4        # the new upstream tag
    git commit -am "Gale 1.22.4" && git push
    git tag 1.22.4 && git push origin 1.22.4

**Local build** (x86_64 Debian 13, as root): see the packages installed in
`.github/workflows/build-appimage.yml`, then

    git submodule update --init
    scripts/build-appimage.sh          # result in dist/

## Licenses

Gale is GPL-3.0 (see `gale/LICENSE.md`). The bundled libraries are Debian
builds, mostly LGPL, unmodified except for the WebKit path string above. Their
copyright files are in `share/doc/` inside the AppImage. The AppImage runtime
is MIT licensed.
