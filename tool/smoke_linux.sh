#!/usr/bin/env bash
# An actual release launch with a display and keyring, on the build architecture.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
arch=${1:?Usage: bash tool/smoke_linux.sh x64|arm64}
case "$arch" in x64|arm64) ;; *) exit 1 ;; esac
binary=$(realpath "build/linux/$arch/release/bundle/digitales_register")
log=$(realpath -m "build/linux/$arch/smoke.log")
export LIBGL_ALWAYS_SOFTWARE=1
# WSLg may provide Wayland even inside xvfb-run; force the isolated X11 display.
export GDK_BACKEND=x11
unset WAYLAND_DISPLAY
export SCHULREGISTER_SMOKE_BINARY=$binary
export SCHULREGISTER_SMOKE_LOG=$log
dbus-run-session -- xvfb-run -a bash -euo pipefail <<'SH'
# Use a temporary keyring, never a user's real login keyring.
export XDG_DATA_HOME=$(mktemp -d)
trap 'rm -rf "$XDG_DATA_HOME"' EXIT
eval "$(printf '\n' | gnome-keyring-daemon --unlock --components=secrets)"
"$SCHULREGISTER_SMOKE_BINARY" >"$SCHULREGISTER_SMOKE_LOG" 2>&1 &
app_pid=$!
sleep 20
if ! kill -0 "$app_pid" 2>/dev/null; then
  status=0
  wait "$app_pid" || status=$?
  cat "$SCHULREGISTER_SMOKE_LOG"
  echo "Linux release terminated during startup (exit $status)." >&2
  exit 1
fi
if command -v xprop >/dev/null; then
  # Locate by ASCII application ID, since legacy WM_NAME can use Latin-1.
  window_id=$(xwininfo -root -tree | awk '/it.bucci.digitalesregister/ {print $1; exit}')
  [[ -n "$window_id" ]] || { xwininfo -root -tree; exit 1; }
  xprop -id "$window_id" WM_CLASS _NET_WM_NAME | tee -a "$SCHULREGISTER_SMOKE_LOG"
  xprop -id "$window_id" WM_CLASS | grep -F 'it.bucci.digitalesregister'
fi
if python3 -c 'from PIL import ImageGrab' 2>/dev/null; then
  python3 - "$SCHULREGISTER_SMOKE_LOG.png" <<'PY'
import os
import sys
from PIL import ImageGrab
ImageGrab.grab(xdisplay=os.environ['DISPLAY']).save(sys.argv[1])
PY
fi
kill "$app_pid"
wait "$app_pid" || true
if grep -Ei 'Unhandled Exception|MissingPluginException|Failed to load.*(library|lib)|Failed to start Flutter engine|error while loading shared libraries' "$SCHULREGISTER_SMOKE_LOG"; then
  exit 1
fi
SH
echo "Native Linux $arch startup smoke test passed; log: $log"
