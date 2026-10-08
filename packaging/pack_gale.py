#!/usr/bin/env python3
"""Collect a portable aarch64 Gale tree (the AppDir) from the arm64 sysroot.

Layout of the result:

    AppRun, gale          launcher (packaging/AppRun)
    gale.bin              the Gale binary, RUNPATH $ORIGIN/lib
    lib/                  bundled GTK 3 / WebKitGTK 4.1 stack and its dependencies
    libexec/              WebKit helper processes and injected bundle
    share/                GSettings schemas, pixbuf loader cache template, icons, licenses
    gale.desktop, gale.png, .DirIcon

WebKitGTK release builds ignore WEBKIT_EXEC_PATH, so the compiled-in helper
directory inside libwebkit2gtk-4.1.so.0 is rewritten to /tmp/gale-webkit2gtk-4.1,
which AppRun fills with symlinks at startup.

Wayland, EGL, GBM, drm, GL, libc and libstdc++ are left to the host (SteamOS).
Bundling libwayland next to a newer host Mesa makes WebKit abort with
"Could not create default EGL display: EGL_BAD_PARAMETER".
"""

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

TRIPLET = "aarch64-linux-gnu"

# Provided by the host system and never bundled.
HOST_LIBS = {
    "ld-linux-aarch64.so.1",
    "libc.so.6",
    "libm.so.6",
    "libdl.so.2",
    "libpthread.so.0",
    "librt.so.1",
    "libresolv.so.2",
    "libgcc_s.so.1",
    "libstdc++.so.6",
    "libEGL.so.1",
    "libGL.so.1",
    "libGLESv2.so.2",
    "libGLX.so.0",
    "libGLdispatch.so.0",
    "libOpenGL.so.0",
    "libdrm.so.2",
    "libgbm.so.1",
    "libvulkan.so.1",
    "libwayland-client.so.0",
    "libwayland-cursor.so.0",
    "libwayland-egl.so.1",
    "libwayland-server.so.0",
    "libxkbcommon.so.0",
    "libxkbcommon-x11.so.0",
}
# These GIO modules pull in a proxy stack that is not useful on SteamOS.
DROP_GIO = {"libgiolibproxy.so", "libgiognomeproxy.so"}
# PNG and JPEG are built into Debian's gdk-pixbuf; the rest are loadable modules.
KEEP_LOADERS = {
    "libpixbufloader-png.so",
    "libpixbufloader-jpeg.so",
    "libpixbufloader-svg.so",
    "libpixbufloader-gif.so",
    "libpixbufloader-ico.so",
    "libpixbufloader-bmp.so",
}
WEBKIT_HELPERS = ["WebKitWebProcess", "WebKitNetworkProcess", "WebKitGPUProcess"]
WEBKIT_LIB = "libwebkit2gtk-4.1.so.0"
WEBKIT_TMP = "/tmp/gale-webkit2gtk-4.1"


def is_elf(path: Path) -> bool:
    with path.open("rb") as f:
        return f.read(4) == b"\x7fELF"


def readelf(*args: str) -> str:
    return subprocess.check_output(["readelf", *args], text=True, errors="replace")


def needed(path: Path) -> list[str]:
    libs = []
    for line in readelf("-d", str(path)).splitlines():
        if "(NEEDED)" in line and "[" in line:
            libs.append(line.split("[", 1)[1].split("]", 1)[0])
    return libs


def glibc_versions(path: Path) -> set[tuple[int, ...]]:
    out = readelf("-V", "-W", str(path))
    return {tuple(int(x) for x in m.split(".")) for m in re.findall(r"Name: GLIBC_([0-9.]+)", out)}


def copy_file(src: Path, dest: Path, mode: int = 0o755) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src.resolve(), dest)
    dest.chmod(mode)


def elf_files(root: Path):
    for p in sorted(root.rglob("*")):
        if p.is_file() and not p.is_symlink() and is_elf(p):
            yield p


class Packer:
    def __init__(self, args: argparse.Namespace):
        self.sysroot: Path = args.sysroot.resolve()
        self.binary: Path = args.binary.resolve()
        self.gale_src: Path = args.gale_src.resolve()
        self.out: Path = args.out.resolve()
        self.packaging = Path(__file__).resolve().parent
        self.qemu: str = args.qemu
        self.libdir = self.sysroot / "usr/lib" / TRIPLET
        self.search = [self.libdir, self.sysroot / "usr/lib"]
        # sysroot-relative file path -> (package, version), from setup-sysroot.sh
        self.owners: dict[str, tuple[str, str]] = {}
        self.used_packages: set[tuple[str, str]] = set()

    # -- helpers -------------------------------------------------------------

    def load_owners(self) -> None:
        listdir = self.sysroot / ".vendor"
        for lst in sorted(listdir.glob("*.list")):
            pkg, version = lst.stem.split("=", 1)
            for line in lst.read_text().splitlines():
                rel = line.lstrip("./").rstrip("/")
                # The sysroot is merged-/usr, so /lib/... is /usr/lib/...
                for prefix in ("lib/", "bin/", "sbin/"):
                    if rel.startswith(prefix):
                        rel = "usr/" + rel
                self.owners[rel] = (pkg, version)

    def note_owner(self, src: Path) -> None:
        rel = str(src.resolve().relative_to(self.sysroot))
        owner = self.owners.get(rel)
        if owner:
            self.used_packages.add(owner)

    def from_sysroot(self, src: Path, dest: Path, mode: int = 0o755) -> None:
        copy_file(src, dest, mode)
        self.note_owner(src)

    def find_lib(self, name: str) -> Path | None:
        for d in self.search:
            p = d / name
            if p.exists():
                return p
        return None

    # -- steps ---------------------------------------------------------------

    def copy_seeds(self) -> None:
        out = self.out
        copy_file(self.binary, out / "gale.bin")

        wk = self.libdir / "webkit2gtk-4.1"
        for name in WEBKIT_HELPERS:
            if (wk / name).exists():
                self.from_sysroot(wk / name, out / "libexec" / name)
        for required in ("WebKitWebProcess", "WebKitNetworkProcess"):
            if not (out / "libexec" / required).exists():
                sys.exit(f"WebKit helper missing from sysroot: {required}")
        bundle = "injected-bundle/libwebkit2gtkinjectedbundle.so"
        self.from_sysroot(wk / bundle, out / "libexec" / bundle)

        loaders = self.libdir / "gdk-pixbuf-2.0/2.10.0/loaders"
        for p in sorted(loaders.glob("*.so")):
            if p.name in KEEP_LOADERS:
                self.from_sysroot(p, out / "lib/gdk-pixbuf-2.0/2.10.0/loaders" / p.name)

        gio = self.libdir / "gio/modules"
        for p in sorted(gio.glob("*.so")):
            if p.name not in DROP_GIO:
                self.from_sysroot(p, out / "lib/gio/modules" / p.name)

    def copy_dependencies(self) -> None:
        queue = list(elf_files(self.out))
        seen: set[Path] = set()
        copied: set[str] = set()
        while queue:
            path = queue.pop()
            if path in seen:
                continue
            seen.add(path)
            for dep in needed(path):
                if dep in HOST_LIBS or dep in copied:
                    continue
                found = self.find_lib(dep)
                if not found:
                    # Reported by verify(), with the library that wants it.
                    continue
                dest = self.out / "lib" / dep
                self.from_sysroot(found, dest)
                copied.add(dep)
                queue.append(dest)
        print(f"bundled {len(copied)} libraries")

    def patch_webkit(self) -> None:
        so = self.out / "lib" / WEBKIT_LIB
        data = bytearray(so.read_bytes())
        old_dir = f"/usr/lib/{TRIPLET}/webkit2gtk-4.1"
        replacements = [
            (old_dir, WEBKIT_TMP),
            (old_dir + "/injected-bundle/", WEBKIT_TMP + "/injected-bundle/"),
        ]
        for old_s, new_s in replacements:
            old = old_s.encode() + b"\0"
            new = new_s.encode() + b"\0"
            if len(new) > len(old):
                sys.exit(f"replacement longer than original: {new_s}")
            i = data.find(old)
            if i < 0:
                sys.exit(f"webkit string not found: {old_s!r}")
            if data.find(old, i + 1) >= 0:
                sys.exit(f"webkit string not unique: {old_s!r}")
            # Pad with NULs so the string table keeps its layout.
            data[i : i + len(old)] = new.ljust(len(old), b"\0")
        if old_dir.encode() in data:
            sys.exit("Debian WebKit helper path is still present after patching")
        so.write_bytes(data)
        print("patched helper path in", so.name)

    def set_rpaths(self) -> None:
        def rpath(path: Path, value: str) -> None:
            subprocess.check_call(["patchelf", "--set-rpath", value, str(path)])

        rpath(self.out / "gale.bin", "$ORIGIN/lib")
        for name in WEBKIT_HELPERS:
            helper = self.out / "libexec" / name
            if helper.exists():
                rpath(helper, "$ORIGIN/../lib")
        rpath(self.out / "libexec/injected-bundle/libwebkit2gtkinjectedbundle.so", "$ORIGIN/../../lib")

    def compile_schemas(self) -> None:
        # GLib only reads gschemas.compiled. Debian generates it in a dpkg
        # trigger, so it is never part of the .deb files.
        src = self.sysroot / "usr/share/glib-2.0/schemas"
        dest = self.out / "share/glib-2.0/schemas"
        dest.mkdir(parents=True, exist_ok=True)
        subprocess.check_call(["glib-compile-schemas", f"--targetdir={dest}", str(src)])
        for p in src.glob("*.xml"):
            self.note_owner(p)

    def pixbuf_loader_cache(self) -> None:
        # Debian also generates loaders.cache in a dpkg trigger. Run the arm64
        # gdk-pixbuf-query-loaders under qemu against the bundled loaders, then
        # turn the absolute paths into @PREFIX@ for AppRun to fill in.
        loaders = sorted((self.out / "lib/gdk-pixbuf-2.0/2.10.0/loaders").glob("*.so"))
        query = self.libdir / "gdk-pixbuf-2.0/gdk-pixbuf-query-loaders"
        text = subprocess.check_output(
            [self.qemu, "-L", str(self.sysroot), str(query), *map(str, loaders)],
            text=True,
            env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
        )
        for loader in loaders:
            if f'"{loader}"' not in text:
                sys.exit(f"gdk-pixbuf-query-loaders did not register {loader.name}")
        text = text.replace(str(self.out), "@PREFIX@")
        (self.out / "share").mkdir(exist_ok=True)
        (self.out / "share/loaders.cache.in").write_text(text)
        print(f"pixbuf loader cache: {len(loaders)} modules")

    def copy_desktop_files(self, version: str) -> None:
        out = self.out
        hicolor = self.sysroot / "usr/share/icons/hicolor"
        if hicolor.exists():
            shutil.copytree(hicolor, out / "share/icons/hicolor", symlinks=True, dirs_exist_ok=True)
        icon = self.gale_src / "src-tauri/icons/128x128.png"
        copy_file(icon, out / "share/icons/hicolor/128x128/apps/gale.png", 0o644)
        copy_file(icon, out / "gale.png", 0o644)
        (out / ".DirIcon").symlink_to("gale.png")

        desktop = (self.packaging / "gale.desktop").read_text().replace("@VERSION@", version)
        (out / "gale.desktop").write_text(desktop)
        copy_file(self.packaging / "AppRun", out / "AppRun")
        copy_file(self.packaging / "AppRun", out / "gale")
        copy_file(self.gale_src / "LICENSE.md", out / "LICENSE.md", 0o644)
        # AppRun reuses /tmp/gale-webkit2gtk-4.1 only for the same build.
        digest = hashlib.sha256((out / "gale.bin").read_bytes())
        digest.update((out / "lib" / WEBKIT_LIB).read_bytes())
        (out / "share/build-id").write_text(f"{version}-{digest.hexdigest()[:16]}\n")

    def copy_licenses(self) -> None:
        doc = self.out / "share/doc"
        lines = []
        for pkg, version in sorted(self.used_packages):
            lines.append(f"{pkg} {version}")
            copyright_file = self.sysroot / "usr/share/doc" / pkg / "copyright"
            if copyright_file.exists():
                copy_file(copyright_file, doc / pkg / "copyright", 0o644)
        (doc / "BUNDLED-PACKAGES.txt").write_text(
            "Debian packages whose files are bundled in this AppImage.\n"
            "Each library is an unmodified Debian build except libwebkit2gtk-4.1.so.0,\n"
            f"whose helper directory string is rewritten to {WEBKIT_TMP}.\n\n" + "\n".join(lines) + "\n"
        )
        print(f"license files for {len(lines)} packages")

    def verify(self) -> None:
        bundled = {p.name for p in (self.out / "lib").iterdir() if p.is_file()}
        problems = []
        newest_glibc: tuple[int, ...] = ()
        for path in elf_files(self.out):
            for dep in needed(path):
                if dep not in HOST_LIBS and dep not in bundled:
                    problems.append(f"{path.relative_to(self.out)} needs {dep}, which is not bundled")
            versions = glibc_versions(path)
            if versions:
                newest_glibc = max(newest_glibc, max(versions))
            if "ARM aarch64" not in subprocess.check_output(["file", "-b", str(path)], text=True):
                problems.append(f"{path.relative_to(self.out)} is not an aarch64 ELF")
        if problems:
            sys.exit("bundle check failed:\n  " + "\n  ".join(problems))
        glibc = ".".join(map(str, newest_glibc))
        (self.out / "share/doc/REQUIREMENTS.txt").write_text(
            f"Host glibc >= {glibc}\n"
            "Host libraries used instead of bundled ones:\n  " + "\n  ".join(sorted(HOST_LIBS)) + "\n"
        )
        print(f"bundle check passed; needs host glibc >= {glibc}")

    def run(self) -> None:
        if not self.binary.exists():
            sys.exit(f"missing binary: {self.binary}")
        if self.out.exists():
            shutil.rmtree(self.out)
        self.out.mkdir(parents=True)
        version = re.search(
            r'^version\s*=\s*"([^"]+)"', (self.gale_src / "src-tauri/Cargo.toml").read_text(), re.M
        ).group(1)

        self.load_owners()
        self.copy_seeds()
        self.copy_dependencies()
        self.patch_webkit()
        self.set_rpaths()
        self.compile_schemas()
        self.pixbuf_loader_cache()
        self.copy_desktop_files(version)
        self.copy_licenses()
        self.verify()
        print(f"portable tree for Gale {version}: {self.out}")


def main() -> None:
    repo = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sysroot", type=Path, default=repo / "build/sysroot")
    ap.add_argument("--gale-src", type=Path, default=repo / "gale")
    ap.add_argument(
        "--binary",
        type=Path,
        default=repo / "gale/src-tauri/target/aarch64-unknown-linux-gnu/release/gale",
    )
    ap.add_argument("--out", type=Path, default=repo / "build/AppDir")
    ap.add_argument(
        "--qemu",
        default=shutil.which("qemu-aarch64-static") or shutil.which("qemu-aarch64") or "qemu-aarch64",
        help="qemu user-mode emulator for aarch64 (runs gdk-pixbuf-query-loaders)",
    )
    Packer(ap.parse_args()).run()


if __name__ == "__main__":
    main()
