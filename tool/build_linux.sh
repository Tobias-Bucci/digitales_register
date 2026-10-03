#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ $(uname -s) != Linux ]]; then
  echo 'Run this script on Linux (or in a separate Linux checkout in WSL).' >&2
  exit 1
fi
case $(uname -m) in
  x86_64) arch=x64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo 'Only x86_64 and aarch64 (64-bit ARM) are supported.' >&2; exit 1 ;;
esac
requested_arch=${1:-$arch}
if [[ $requested_arch != "$arch" ]]; then
  echo "Build $requested_arch on a native $requested_arch Linux host; this host is $arch." >&2
  exit 1
fi
for command in flutter python3 clang cmake ninja pkg-config dpkg-deb dpkg-shlibdeps desktop-file-validate appstreamcli; do
  command -v "$command" >/dev/null || { echo "Missing build tool: $command" >&2; exit 1; }
done
pkg-config --exists gtk+-3.0 libsecret-1 jsoncpp
flutter config --enable-linux-desktop
flutter pub get
dart run build_runner build
dart run tool/prepare_linux_assets.dart
desktop-file-validate linux/digitales_register.desktop
appstreamcli validate --no-net linux/digitales_register.metainfo.xml
flutter build linux --release --target-platform "linux-$arch"
python3 tool/package_linux.py --arch "$arch"
