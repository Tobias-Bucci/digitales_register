#!/usr/bin/env bash
# Install a portable bundle for the current user without requiring root.
set -euo pipefail
source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
app_id=io.github.Tobias_Bucci.digitales_register
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
target=${SCHULREGISTER_INSTALL_DIR:-$HOME/.local/opt/$app_id}
[[ -x "$source_dir/digitales_register" ]] || { echo 'Run from an extracted Linux release bundle.' >&2; exit 1; }
mkdir -p "$target" "$data_home/applications" "$data_home/icons/hicolor" "$data_home/metainfo"
if [[ "$source_dir" != "$target" ]]; then
  cp -a "$source_dir/." "$target/"
fi
cp -a "$target/share/icons/hicolor/." "$data_home/icons/hicolor/"
cp "$target/share/metainfo/$app_id.metainfo.xml" "$data_home/metainfo/"
python3 - "$target" "$data_home/applications/$app_id.desktop" <<'PY'
import pathlib
import sys

target = pathlib.Path(sys.argv[1])
text = (target / 'share/applications/io.github.Tobias_Bucci.digitales_register.desktop').read_text()
# Desktop Exec quoting is different from shell quoting (no shell is invoked).
def quote(value):
    for old, new in [('\\', '\\\\'), ('"', '\\"'), ('`', '\\`'), ('$', '\\$')]:
        value = value.replace(old, new)
    return '"' + value.replace('%', '%%') + '"'
text = '\n'.join(
    'Exec=' + quote(str(target / 'digitales_register')) if line.startswith('Exec=')
    else line for line in text.splitlines() if not line.startswith('TryExec=')) + '\n'
pathlib.Path(sys.argv[2]).write_text(text)
PY
if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$data_home/applications"
fi
if command -v gtk-update-icon-cache >/dev/null && [[ -f "$data_home/icons/hicolor/index.theme" ]]; then
  gtk-update-icon-cache -f -t "$data_home/icons/hicolor"
fi
echo "Installed: $target"
echo 'Start Digitales Register from your application menu.'
