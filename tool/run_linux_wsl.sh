#!/usr/bin/env bash
# Preview the Linux release in WSLg with isolated, disposable app/keyring data.
set -euo pipefail
binary=${1:?Usage: bash tool/run_linux_wsl.sh /absolute/path/to/digitales_register}
[[ -x "$binary" ]] || { echo "Linux executable not found: $binary" >&2; exit 1; }
binary=$(realpath "$binary")
test_session=$(mktemp -d -t schulregister-wsl-XXXXXX)
trap 'rm -rf "$test_session"' EXIT
export XDG_DATA_HOME="$test_session/data"
export XDG_CONFIG_HOME="$test_session/config"
export XDG_CACHE_HOME="$test_session/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
export LIBGL_ALWAYS_SOFTWARE=true
export GALLIUM_DRIVER=llvmpipe
export GDK_BACKEND=${SCHULREGISTER_WSL_BACKEND:-wayland}
export SCHULREGISTER_WSL_PID_FILE="$test_session/app.pid"
# Keep the preview visible on the first monitor, even if WSLg remembered a
# window position on a disconnected or unused secondary monitor.
position_preview() {
  for attempt in {1..60}; do
    if [[ -s "$SCHULREGISTER_WSL_PID_FILE" ]]; then
      app_pid=$(cat "$SCHULREGISTER_WSL_PID_FILE")
      # WSLg/Weston does not always expose _NET_CLIENT_LIST for wmctrl -lp.
      while read -r window_id; do
        if xprop -id "$window_id" _NET_WM_PID 2>/dev/null | grep -q "= $app_pid$"; then
          wmctrl -ir "$window_id" -e 0,100,100,1280,720
          wmctrl -ia "$window_id"
          return
        fi
      done < <(xwininfo -root -tree | awk '/it.bucci.digitalesregister/ && !/ 10x10[+-]/ {print $1}')
    fi
    sleep 0.25
  done
}
if [[ "$GDK_BACKEND" == x11 ]] && command -v wmctrl >/dev/null; then
  position_preview &
fi
echo 'WSLg preview: app data and the temporary keyring are removed after closing.'
dbus-run-session -- bash -euo pipefail -c '
  eval "$(printf "\n" | gnome-keyring-daemon --unlock --components=secrets)"
  printf "%s\n" "$$" > "$SCHULREGISTER_WSL_PID_FILE"
  exec "$1"
' bash "$binary"
