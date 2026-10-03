# Linux release preparation

Linux is named **Digitales Register** and uses the current shared logo from `assets/index.png`,
application ID `io.github.Tobias_Bucci.digitales_register` and binary `digitales_register`.
The version and build number come from `pubspec.yaml`: **1.17.0+44**.
Other platform versions and build numbers are unchanged.

## Architectures

| Hardware / OS | Flutter target | Artifact suffix | Debian architecture |
| --- | --- | --- | --- |
| Intel/AMD 64-bit PCs | linux-x64 | x86_64 | amd64 |
| 64-bit ARM Linux, including a Raspberry Pi with a 64-bit desktop OS | linux-arm64 | aarch64 | arm64 |

ARM requires an **aarch64 operating system**, not a 32-bit armhf installation.
Each package must be built on its own native architecture. The build script
rejects mismatched host/target architectures. It checks the architecture of
every executable and bundled shared library before packaging. Do not rename
an x64 archive to ARM64, or mix library directories between architectures.

## Build prerequisites

Use a Linux desktop build host with Flutter **3.47.2**, Git and Python 3.
The CI uses native `ubuntu-22.04` and `ubuntu-22.04-arm` runners so both
packages have the same distribution baseline. Build on the oldest supported
distribution: packages built on newer distributions may require newer glibc,
GTK or C++ runtime versions. Debian package dependencies are derived from
the built ELF files by `dpkg-shlibdeps`.

```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev \
  libsecret-1-dev libjsoncpp-dev libstdc++-12-dev curl git unzip xz-utils zip \
  python3 dpkg-dev desktop-file-utils appstream xdg-utils gnome-keyring \
  dbus-x11 xvfb x11-utils libgl1-mesa-dri xdg-desktop-portal xdg-desktop-portal-gtk
flutter pub get
bash tool/build_linux.sh
bash tool/smoke_linux.sh x64   # use arm64 on aarch64
```

The build generates the ignored Dart sources with `build_runner`, regenerates
Linux icons at 32, 48, 64, 128, 256 and 512 pixels,
validates desktop/AppStream metadata and creates a release bundle, `.tar.gz`,
`.deb` and SHA-256 files in `build/linux/packages`.

### Direct Flutter build and missing Builder classes

The generated `*.g.dart` files are ignored by Git. After cloning the repository,
generate them before invoking Flutter directly. On a native ARM64 host:

```bash
flutter pub get
dart run build_runner build
flutter build linux --release --target-platform linux-arm64
```

On x64, use `--target-platform linux-x64`. Stop if code generation fails and
resolve its first error before building. Errors such as
`NotificationStateBuilder isn't a type`, `ProfileStateBuilder isn't a type`
and subsequent undefined setters on `Object?` indicate missing or invalid
generated sources; they do not by themselves indicate an ARM compatibility
problem. `bash tool/build_linux.sh arm64` performs generation, asset preparation,
building and packaging together on ARM64.

## Installation and runtime

### WSLg preview from Windows

WSL sessions may have no default keyring and may place app windows on a
secondary monitor. To preview the locally built app, run in PowerShell:

```powershell
wsl -d Ubuntu -- bash /mnt/c/Users/mainb/Documents/Projects/digitales_register/tool/run_linux_wsl.sh /home/tobi/.cache/codex-linux/clean-checkout/build/linux/x64/release/bundle/digitales_register
```

Adjust the checkout and binary paths if using another machine. The helper uses
software rendering, WSLg's Wayland backend, an isolated D-Bus session and a
temporary unlocked keyring.
**Preview app data is deleted after closing the app**; this does not change
your regular keyring or saved application data. For an optional X11 comparison,
set `SCHULREGISTER_WSL_BACKEND=x11`; with `wmctrl` installed that mode also
places and activates the new window on the first monitor.

### Native Linux installation

For Debian/Ubuntu, install the package for your architecture:

```bash
sudo apt install ./Digitales-Register-1.17.0+44-linux-x86_64.deb
# ARM64: use the corresponding linux-aarch64.deb file instead.
```

For the portable archive, extract it and run `./digitales_register` inside the
extracted directory. Keep `data/`, `lib/` and the executable together.
`bash install.sh` installs the complete bundle for the current user under
`~/.local/opt/io.github.Tobias_Bucci.digitales_register` and adds the application-menu entry,
icons and AppStream metadata. The installer requires Python 3. To remove this
user installation, remove that exact directory and the corresponding
`io.github.Tobias_Bucci.digitales_register` desktop, metainfo and icon files under
`${XDG_DATA_HOME:-$HOME/.local/share}`.

Runtime requirements:

- A graphical 64-bit Linux desktop with GTK 3 and working OpenGL/Mesa.
  This is a desktop application, not a headless service.
- A D-Bus session and an unlocked Secret Service keyring (for example
  GNOME Keyring, or a compatible KWallet setup). The existing encrypted Hive
  storage keeps its key in the keyring; do not replace it with plaintext.
- `libsecret`, `jsoncpp`, `xdg-utils` for opening files/links, and
  `xdg-desktop-portal` with the desktop's backend for file-selection dialogs.
- Biometric app locking is unavailable with the current Linux plugin;
  encrypted credential storage remains available.
- Firebase Analytics and Crashlytics remain disabled by the existing Linux
  capability policy. No Firebase configuration is needed for Linux startup.
- Linux CMake disables optional JNI discovery, so a JDK installed on a build
  runner cannot silently add a Java VM dependency to the desktop package.

## Checks and release workflow

The Linux workflow builds, validates and launches each architecture natively,
runs the telemetry policy tests, and uploads both sets of packages as Actions
artifacts. For a published GitHub release it attaches the packages only after
**both** architecture jobs succeed. PR/push builds do not publish releases.

`tool/smoke_linux.sh` launches the real release for 20 seconds under Xvfb with
a temporary D-Bus session and keyring. It checks that the process stays alive
and that no unhandled Dart exception or missing-plugin/loader error appears.
This does not replace interactive acceptance testing: on both architectures,
check demo login, a real login, restart/persisted login, keyring unlock,
file selection/opening, links, calendar and window/taskbar icons on your
desktop (including Wayland if used).

Local verification on 2026-10-03: a native x64 release build and package
creation succeeded under Ubuntu 26.04 in WSL. All six ELF files passed the
architecture and dynamic-library checks, the isolated X11 startup test passed,
10 targeted Flutter tests and five packaging regression tests passed, and
Flutter analysis reported no issues. These local packages have Ubuntu 26.04
library requirements; use the Ubuntu 22.04 CI artifacts for that older baseline.
The ARM64 workflow is prepared but has not been executed locally. A real ARM64
build/startup and interactive acceptance test are still required before claiming
a verified ARM64 release.

Build references: [Flutter Linux builds](https://docs.flutter.dev/platform-integration/linux/building)
and [native GitHub runner architectures](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
