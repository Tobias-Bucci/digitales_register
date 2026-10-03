#!/usr/bin/env bash
# Exercise the actual portable installer without touching the user's installation.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
archive=${1:?Usage: bash tool/test_linux_install.sh build/linux/packages/package.tar.gz}
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
tar -xzf "$archive" -C "$temporary"
mapfile -t installers < <(find "$temporary" -name install.sh -type f)
[[ ${#installers[@]} == 1 ]]
export SCHULREGISTER_INSTALL_DIR="$temporary/install with spaces"
export XDG_DATA_HOME="$temporary/menu with spaces"
bash "${installers[0]}"
desktop="$XDG_DATA_HOME/applications/io.github.Tobias_Bucci.digitales_register.desktop"
desktop-file-validate "$desktop"
[[ -x "$SCHULREGISTER_INSTALL_DIR/digitales_register" ]]
[[ -f "$XDG_DATA_HOME/icons/hicolor/512x512/apps/io.github.Tobias_Bucci.digitales_register.png" ]]
[[ -f "$XDG_DATA_HOME/metainfo/io.github.Tobias_Bucci.digitales_register.metainfo.xml" ]]
grep -F "Exec=\"$SCHULREGISTER_INSTALL_DIR/digitales_register\"" "$desktop"
ldd "$SCHULREGISTER_INSTALL_DIR/digitales_register" | tee "$temporary/ldd.log"
if grep -F 'not found' "$temporary/ldd.log"; then exit 1; fi
echo 'Portable installation, desktop path quoting, icon and library checks passed.'
