#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter_bin="$(readlink -f "$(command -v flutter)")"
flutter_root="$(dirname "$(dirname "$flutter_bin")")"
case "$(uname -m)" in
  aarch64) engine_arch=arm64 ;;
  x86_64) engine_arch=x64 ;;
  *) echo "Unsupported architecture" >&2; exit 1 ;;
esac
engine="$flutter_root/bin/cache/artifacts/engine/linux-$engine_arch"
test_binary="$(mktemp)"
trap 'rm -f "$test_binary"' EXIT
"${CXX:-c++}" -std=c++14 -Wall -Werror linux/test/file_open_portal_test.cc \
  -I "$engine" -L "$engine" -Wl,-rpath,"$engine" -lflutter_linux_gtk \
  $(pkg-config --cflags --libs gtk+-3.0 gio-unix-2.0) -o "$test_binary"
dbus-run-session -- "$test_binary"
