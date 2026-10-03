#!/usr/bin/env python3
"""Package a native Flutter release bundle as a portable tarball and a Debian package."""
import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_ID = "it.bucci.digitalesregister"
BINARY = "digitales_register"
ARCHITECTURES = {"x64": ("x86_64", "amd64", 62), "arm64": ("aarch64", "arm64", 183)}


def check_bundle(bundle, arch, version, build):
    """Reject mixed architectures, missing assets and stale application versions."""
    for relative in (BINARY, "lib/libflutter_linux_gtk.so", "lib/libapp.so",
                     "data/icudtl.dat", "data/icon.png",
                     "share/applications/" + APP_ID + ".desktop",
                     "share/metainfo/" + APP_ID + ".metainfo.xml"):
        if not (bundle / relative).is_file():
            raise ValueError(f"Missing bundle file: {relative}")
    info = json.loads((bundle / "data/flutter_assets/version.json").read_text())
    if (info["version"], str(info["build_number"])) != (version, build):
        raise ValueError(f"Stale Flutter bundle version: {info}")
    if (bundle / "data/icon.png").read_bytes() != (ROOT / "linux/icon.png").read_bytes():
        raise ValueError("Bundle icon does not match the current Linux app icon")
    elfs = []
    expected_machine = ARCHITECTURES[arch][2]
    for path in sorted(bundle.rglob("*")):
        if not path.is_file():
            continue
        with path.open("rb") as stream:
            header = stream.read(20)
        if header[:4] != b"\x7fELF":
            continue
        if len(header) < 20 or header[4:6] != b"\x02\x01":
            raise ValueError(f"Expected a little-endian 64-bit ELF: {path}")
        if struct.unpack_from("<H", header, 18)[0] != expected_machine:
            raise ValueError(f"Wrong ELF architecture for {arch}: {path}")
        elfs.append(path)
        # This runs on the native build host, so it also checks all plugin libraries.
        environment = os.environ.copy()
        if path.name != BINARY:
            environment["LD_LIBRARY_PATH"] = str(bundle / "lib")
        linked = subprocess.run(["ldd", str(path)], capture_output=True, text=True,
                                env=environment)
        if linked.returncode or "not found" in linked.stdout:
            raise ValueError(f"Unresolved runtime libraries: {path}\n{linked.stdout}{linked.stderr}")
    if not elfs:
        raise ValueError("No ELF binaries in bundle")
    return elfs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", required=True, choices=ARCHITECTURES)
    args = parser.parse_args()
    version_match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$",
                              (ROOT / "pubspec.yaml").read_text(), re.MULTILINE)
    if not version_match:
        raise ValueError("Expected major.minor.patch+build in pubspec.yaml")
    version, build = version_match.groups()
    display_arch, deb_arch, _ = ARCHITECTURES[args.arch]
    bundle = ROOT / "build/linux" / args.arch / "release/bundle"
    elfs = check_bundle(bundle, args.arch, version, build)
    output = ROOT / "build/linux/packages"
    output.mkdir(parents=True, exist_ok=True)
    stem = f"Digitales-Register-{version}+{build}-linux-{display_arch}"
    tar_path = output / (stem + ".tar.gz")
    deb_path = output / (stem + ".deb")

    with tempfile.TemporaryDirectory(prefix="schulregister-linux-") as temporary:
        work = Path(temporary)
        portable = work / stem
        shutil.copytree(bundle, portable)
        shutil.copy2(ROOT / "linux/install.sh", portable / "install.sh")
        (portable / "install.sh").chmod(0o755)
        shutil.copy2(ROOT / "LICENSE.txt", portable / "LICENSE.txt")
        (portable / "LICENSE.txt").chmod(0o644)
        (portable / "LINUX-README.txt").write_text(
            f"Digitales Register {version}, build {build} ({display_arch})\n"
            "Start: ./digitales_register\nInstall for current user: bash install.sh\n"
            "Requires GTK 3, libsecret, jsoncpp, xdg-utils, an OpenGL-capable desktop\n"
            "and an unlocked Secret Service keyring (GNOME Keyring or compatible).\n"
            "Keep the complete bundle together; do not copy only the executable.\n"
            "This archive requires libraries at least as recent as the build host.\n",
            encoding="utf-8")
        (portable / "LINUX-README.txt").chmod(0o644)
        with tarfile.open(tar_path, "w:gz") as archive:
            archive.add(portable, arcname=stem)

        package = work / "deb"
        install_dir = package / "usr/lib" / APP_ID
        shutil.copytree(bundle, install_dir)
        shutil.copytree(install_dir / "share", package / "usr/share", dirs_exist_ok=True)
        shutil.rmtree(install_dir / "share")
        executable_dir = package / "usr/bin"
        executable_dir.mkdir(parents=True)
        (executable_dir / BINARY).symlink_to(f"../lib/{APP_ID}/{BINARY}")
        doc = package / "usr/share/doc/schulregister-suedtirol"
        doc.mkdir(parents=True)
        shutil.copy2(ROOT / "LICENSE.txt", doc / "copyright")
        (doc / "copyright").chmod(0o644)

        # Derive minimum library versions and distro-specific names (e.g. t64)
        # from the actual binaries, rather than hard-coding an x64 dependency list.
        source_control = work / "debian/control"
        source_control.parent.mkdir()
        source_control.write_text(
            "Source: schulregister-suedtirol\nSection: education\nPriority: optional\n"
            "Maintainer: Tobias Bucci <buccitobias774@gmail.com>\n\n"
            "Package: schulregister-suedtirol\nArchitecture: any\n"
            "Description: Digitales Register\n", encoding="utf-8")
        deps_result = subprocess.run(
            ["dpkg-shlibdeps", "--ignore-missing-info", "-O", f"-l{bundle / 'lib'}",
             *(f"-e{path}" for path in elfs)], cwd=work, check=True,
            capture_output=True, text=True)
        dependencies = next(line.split("=", 1)[1] for line in deps_result.stdout.splitlines()
                            if line.startswith("shlibs:Depends="))
        control_dir = package / "DEBIAN"
        control_dir.mkdir()
        installed_kib = (sum(p.stat().st_size for p in package.rglob("*")
                             if p.is_file() and not p.is_symlink()) + 1023) // 1024
        (control_dir / "control").write_text(
            f"Package: schulregister-suedtirol\nVersion: {version}-{build}\n"
            f"Architecture: {deb_arch}\nSection: education\nPriority: optional\n"
            "Maintainer: Tobias Bucci <buccitobias774@gmail.com>\n"
            f"Installed-Size: {installed_kib}\nDepends: {dependencies}, xdg-utils\n"
            "Recommends: gnome-keyring, xdg-desktop-portal, "
            "xdg-desktop-portal-gtk\n"
            "Homepage: https://github.com/Tobias-Bucci/digitales_register\n"
            "Description: Digitales Register\n"
            " Inoffizieller Schulplaner für das Digitale Register in Südtirol.\n",
            encoding="utf-8")
        subprocess.run(["dpkg-deb", "--root-owner-group", "--build", str(package), str(deb_path)],
                       check=True)

    for artifact in (tar_path, deb_path):
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        artifact.with_name(artifact.name + ".sha256").write_text(
            f"{digest}  {artifact.name}\n", encoding="ascii")
        print(f"{artifact} ({artifact.stat().st_size} bytes)")
    print(f"Verified {len(elfs)} native {display_arch} ELF files; version {version}+{build}")


if __name__ == "__main__":
    main()
