# Gale for Steam Frame (aarch64 AppImage)

GitHub Actions build of the [Gale](https://github.com/Kesomannen/gale) mod
manager as an **aarch64 AppImage** that runs on the Steam Frame (SteamOS on
ARM). Upstream Gale only publishes x86_64 builds.

Gale itself is not copied into this repository. It is the `gale/` git
submodule, pinned to an upstream release tag, and is built without any source
changes. Everything in this repository is packaging around it.

## Download

- **Releases**: every pushed tag publishes `Gale-<version>-aarch64.AppImage`
  on the Releases page.
- **Any build**: open the *Build AppImage (aarch64)* workflow run under
  *Actions* and download the artifact.

On the Steam Frame, in Desktop Mode:

    chmod +x Gale-1.22.3-aarch64.AppImage
    ./Gale-1.22.3-aarch64.AppImage

If FUSE is not available:

    ./Gale-1.22.3-aarch64.AppImage --appimage-extract-and-run

Do not use Gale's built-in updater. Official updates are x86_64 builds and
would not run.

## How the build works

Gale is a Tauri 2 app (Rust + SvelteKit) on GTK 3 and WebKitGTK 4.1.
SteamOS ships neither of those, so the AppImage carries its own copy from
Debian 13 (trixie) arm64.

1. **Vendored libraries.** `vendor/debian-trixie-arm64/debs/` holds the Debian
   arm64 `.deb` files (GTK, WebKitGTK, their dependencies and the matching
   `-dev` packages), with `SHA256SUMS` and a readable `MANIFEST.txt`. The
   build never downloads libraries: it checks the checksums and unpacks these
   files into a sysroot (`scripts/setup-sysroot.sh`).
2. **Cross-compile.** On an x86_64 runner, inside a `debian:trixie`
   container, the SvelteKit frontend is built and Gale is cross-compiled for
   `aarch64-unknown-linux-gnu` against that sysroot with Debian's
   `aarch64-linux-gnu-gcc` (`scripts/build-gale.sh`, which runs
   `tauri build --no-bundle` like upstream's release).
3. **Portable tree.** `packaging/pack_gale.py` copies the binary, the WebKit
   helper processes, and every library they need from the sysroot into an
   AppDir.
4. **AppImage.** `scripts/make-appimage.sh` appends a zstd squashfs of the
   AppDir to the vendored aarch64 AppImage runtime
   (`vendor/appimage-runtime/`).
5. **Smoke test.** `scripts/check-appimage.sh` runs the AppImage under qemu,
   extracts it, and checks that `gale.bin` and the WebKit helpers resolve
   every library and symbol.

### Steam Frame specific fixes

These live in `packaging/` and are applied at packaging time, not in Gale's
code:

- **WebKit helper path.** Debian's release WebKitGTK ignores
  `WEBKIT_EXEC_PATH` and always starts its helpers from
  `/usr/lib/aarch64-linux-gnu/webkit2gtk-4.1/`, which does not exist on
  SteamOS (WebKit then dies with *Trace/breakpoint trap*). `pack_gale.py`
  rewrites that string in `libwebkit2gtk-4.1.so.0` to `/tmp/gale-webkit2gtk-4.1`,
  and `AppRun` points symlinks there at the bundled helpers.
- **Graphics stack from the host.** libwayland, libxkbcommon, libEGL, libGL,
  libgbm, libdrm, libc and libstdc++ are *not* bundled. Bundling libwayland
  next to SteamOS's Mesa fails with *Could not create default EGL display:
  EGL_BAD_PARAMETER*. The full list is in `HOST_LIBS` in `pack_gale.py`.
- **Shared-memory rendering.** `AppRun` sets `WEBKIT_DISABLE_DMABUF_RENDERER=1`
  and `WEBKIT_DISABLE_COMPOSITING_MODE=1`, because the dma-buf path draws a
  blank window on this GPU.
- **No WebKit sandbox.** bubblewrap cannot see the relocated helpers, so
  `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` is set.
- **GSettings schemas and image loaders.** Debian creates
  `gschemas.compiled` and the gdk-pixbuf `loaders.cache` in install hooks, so
  they are not inside the `.deb` files. The build compiles the schemas and
  generates the loader cache (under qemu) itself.

The AppImage needs glibc 2.41 or newer on the host, which SteamOS provides.
Each build writes the exact requirement to `share/doc/REQUIREMENTS.txt`
inside the AppImage.

## Workflows

| Workflow | Runs on | What it does |
| --- | --- | --- |
| `Build AppImage (aarch64)` | pushes that touch the build, tags, PRs, manual | Builds, tests and uploads the AppImage. On a tag, also publishes a release. |
| `Vendor Debian libraries` | manual only | Downloads the current Debian trixie arm64 packages, commits them to the branch, then starts a build. |

## Common tasks

**Update to a new Gale release**

    git -C gale fetch --tags origin
    git -C gale checkout 1.22.4        # the new upstream tag
    git add gale
    git commit -m "Gale 1.22.4"
    git tag 1.22.4 && git push --follow-tags

If the new release needs more system libraries, add them to
`vendor/debian-trixie-arm64/packages.txt` and run *Vendor Debian libraries*.

**Pick up Debian security updates (e.g. WebKitGTK)**

Run *Actions → Vendor Debian libraries → Run workflow*. It commits the new
`.deb` files and starts a build. The WebKit patch step fails loudly if a new
WebKitGTK changes the helper path string.

**Build locally** (x86_64 Debian 13 host or container, as root):

    apt-get install -y build-essential pkg-config patchelf file python3 git curl \
      gcc-aarch64-linux-gnu g++-aarch64-linux-gnu qemu-user squashfs-tools libglib2.0-bin
    # plus Rust (rustup target add aarch64-unknown-linux-gnu), Node.js 24 and pnpm 11
    git submodule update --init
    scripts/build-appimage.sh          # result in dist/

## Layout

```
gale/                         upstream Gale (git submodule, pinned tag)
packaging/AppRun              launcher: environment, WebKit helper links, pixbuf cache
packaging/pack_gale.py        builds the AppDir from the sysroot
packaging/gale.desktop        desktop entry template
scripts/vendor-debs.sh        refreshes vendor/debian-trixie-arm64 (used by the vendor workflow)
scripts/setup-sysroot.sh      unpacks the vendored .debs into build/sysroot
scripts/build-gale.sh         frontend + aarch64 cross-compile
scripts/make-appimage.sh      AppDir -> dist/Gale-<version>-aarch64.AppImage
scripts/check-appimage.sh     qemu smoke test
scripts/build-appimage.sh     all of the above, in order
vendor/debian-trixie-arm64/   packages.txt, exclude.txt, debs/, SHA256SUMS, MANIFEST.txt
vendor/appimage-runtime/      pinned aarch64 AppImage type 2 runtime
```

## Licenses

Gale is GPL-3.0 (see `gale/LICENSE.md`). The bundled libraries are unmodified
Debian builds, mostly LGPL, except for the one-string path change in
`libwebkit2gtk-4.1.so.0` described above. Each stays a separate file in the
AppImage. Their Debian copyright files and a package list are in
`share/doc/` inside the AppImage. The AppImage runtime is MIT licensed.
