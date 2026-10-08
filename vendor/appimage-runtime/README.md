# AppImage runtime

`runtime-aarch64` is the static aarch64 AppImage type 2 runtime, release
[20251108](https://github.com/AppImage/type2-runtime/releases/tag/20251108) of
<https://github.com/AppImage/type2-runtime> (MIT). It is the small ELF program
at the front of the AppImage that mounts the embedded squashfs and starts
`AppRun`. It is vendored so builds do not depend on the moving `continuous`
release.

To update it, download a newer `runtime-aarch64` from that project's releases
into this directory and regenerate the checksum:

    sha256sum runtime-aarch64 > SHA256SUMS
