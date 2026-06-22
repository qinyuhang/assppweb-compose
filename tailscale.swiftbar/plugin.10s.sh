#!/usr/bin/env bash

set -u

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

resolve_bin() {
  local name="$1"
  shift
  local candidate

  for candidate in "$@"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  candidate="$(command -v "$name" 2>/dev/null || true)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi

  return 1
}

TSCALED_BIN="$(resolve_bin tailscaled /opt/homebrew/bin/tailscaled /usr/local/bin/tailscaled || true)"
if [[ -n "$TSCALED_BIN" ]]; then
  TS_BIN_PAIRED="$(dirname "$TSCALED_BIN")/tailscale"
  if [[ -x "$TS_BIN_PAIRED" ]]; then
    TS_BIN="$TS_BIN_PAIRED"
  else
    TS_BIN="$(resolve_bin tailscale /opt/homebrew/bin/tailscale /usr/local/bin/tailscale /Applications/Tailscale.app/Contents/MacOS/Tailscale /Applications/Tailscale.app/Contents/MacOS/tailscale || true)"
  fi
else
  TS_BIN="$(resolve_bin tailscale /opt/homebrew/bin/tailscale /usr/local/bin/tailscale /Applications/Tailscale.app/Contents/MacOS/Tailscale /Applications/Tailscale.app/Contents/MacOS/tailscale || true)"
fi

get_bin_version() {
  local bin_path="$1"
  local version_line

  if [[ -z "$bin_path" || ! -x "$bin_path" ]]; then
    return 1
  fi

  version_line="$($bin_path version 2>/dev/null | head -n 1)"
  if [[ -z "$version_line" ]]; then
    version_line="$($bin_path --version 2>/dev/null | head -n 1)"
  fi
  if [[ -z "$version_line" ]]; then
    return 1
  fi

  # Normalize to major.minor.patch to compare across different output formats.
  printf '%s\n' "$version_line" | awk '{print $1}' | awk -F'-' '{print $1}'
}

TS_BIN_VERSION="$(get_bin_version "$TS_BIN" || true)"
TSCALED_BIN_VERSION="$(get_bin_version "$TSCALED_BIN" || true)"
VERSION_MISMATCH="no"
if [[ -n "$TS_BIN_VERSION" && -n "$TSCALED_BIN_VERSION" && "$TS_BIN_VERSION" != "$TSCALED_BIN_VERSION" ]]; then
  VERSION_MISMATCH="yes"
fi

TS_SOCKET="/tmp/tailscaled-swiftbar.sock"
TS_STATE_DIR="$HOME/Library/TailscaleSwiftBar"
TS_STATE="$TS_STATE_DIR/tailscaled.state"
TS_UP_STATE_FILE="$TS_STATE_DIR/tailscale-up.state"
UP_LOG="/tmp/tailscale-up-swiftbar.log"
TSCALED_LOG="$HOME/Library/Logs/tailscaled-swiftbar.log"
LAUNCHD_LABEL="com.qinyuhang.tailscaled.swiftbar"
LAUNCHD_PLIST_TARGET="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"

ONLINE_ICON_BASE64="$(cat <<'EOF'
iVBORw0KGgoAAAANSUhEUgAAABYAAAAXCAYAAAAP6L+eAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAFqADAAQAAAABAAAAFwAAAAAhQRrqAAABWUlEQVQ4Ee2Uu0oEQRRE2ydsJIKCDxZENB40MjIXA8FI2MzcL9C/MDdSTAUDwV8w8xcMREV8gojPU3DvOvS0ss3OZl4oqrrmdk1Pz0yH8F+2A33RTgwwbpp3AX+YzvXDoE10WkRM2GAcPjOd64d+m+g05gLuRleCr0rB3egQ77GeYNLCL+FP0+qbyvCttQcUr7jBPTbtPnvwi+lc36b90BHyyyDtlev7vDY/oTz4se2GIO2+eryuESfgFNy7meJDTA+Q9vrNL3+S096c4iHMlkHaSz9SytcfuQOWvbEuLgjSE76Ctb9CtYIZg3QntUuTwt/Ahk/o9KzYYsK8T0rwA94IOADK3I+/4xW7AIV3oDc+Cm5B3IuVrHPcIl6xzgd/u9KqO7AK5jRI1DDeNtACnoGerlI6KxQsxCdfpRlDCzsG2mMtYAnUUgUpCr0BC7UklkLW0bOlcW/lNwXeUmw0Azf4AAAAAElFTkSuQmCC
EOF
)"

OFFLINE_ICON_BASE64="$(cat <<'EOF'
iVBORw0KGgoAAAANSUhEUgAAABYAAAAXCAYAAAAP6L+eAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAFqADAAQAAAABAAAAFwAAAAAhQRrqAAABtUlEQVQ4Ee1UPS9EQRSdu0tBoyEhuytRKIX4AxIK+1YvCgXiq+CtBtFprca+REiEWlQKdv0EiQZ/QLIfEX+AAjvu2b3vmQyveFm6vcnLOXPux9x3ZzJKtUwmQNYk4rxOiVZm/BQeVVdtkujDKJNeWfQw3gmPqquYJPrQ7RPGZviPwi9G4Wa4smeMP+iT4s+MNeFRdUn7B7A77uA9FmSfM8a3v9rzkgtp+cADK62lJytuZpUFuxmCDn8QzMS+FROGc9zgKh6jCyJ1VHGd013JA2INHX4z3r7HV+yckYBrM1ArfUiKdohofjGbobGH16XB4c4Tbn8OcfCb8fZvtbNzWgLQwbsZXM5mcvyLm3VNqyceygA4X539VL6wZcbahU3fr7zqOnuK6LuI1rmEV9y2g+1RhL0Jfh5poi6zG6zZCQmHHph9eHgThuQDN41P3znmCisQtdaPQKyhNyiUhtmFw94HVV13PD64Zcnzkl5xhLmHNXT4xVcHu3DY+6B0jGaRwad/kMgXsqBA7jxf18UPDrNnfM+aXxxvRWCkP6b42vYnvZvzQGTCnW9U3fQtqVrJ1Fs8mMAXsap8UfPvJU0AAAAASUVORK5CYII=
EOF
)"

notify() {
  local message="$1"
  /usr/bin/osascript -e "display notification \"${message}\" with title \"SwiftBar Tailscale\"" >/dev/null 2>&1 || true
}

show_error_dialog() {
  local message="$1"
  local clicked
  clicked="$(/usr/bin/osascript -e "button returned of (display dialog \"${message}\" with title \"SwiftBar Tailscale\" buttons {\"OK\",\"Show LaunchAgent\"} default button \"OK\")" 2>/dev/null || true)"
  if [[ "$clicked" == "Show LaunchAgent" ]]; then
    show_launchagent
  fi
}

show_binary_paths() {
  /usr/bin/osascript <<EOF >/dev/null 2>&1 || true
display dialog "tailscale: ${TS_BIN:-not found}\nversion: ${TS_BIN_VERSION:-unknown}\n\ntailscaled: ${TSCALED_BIN:-not found}\nversion: ${TSCALED_BIN_VERSION:-unknown}" with title "SwiftBar Tailscale" buttons {"OK"} default button "OK"
EOF
}

open_in_console() {
  local log_file="$1"
  open -a Console "$log_file" >/dev/null 2>&1 || open -a Console >/dev/null 2>&1 || true
}

show_launchagent() {
  local plist_to_open="$LAUNCHD_PLIST_TARGET"
  open -a TextEdit "$plist_to_open" >/dev/null 2>&1 || open "$plist_to_open" >/dev/null 2>&1 || true
}

build_launchagent_plist_text() {
  cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.qinyuhang.tailscaled.swiftbar</string>

    <key>ProgramArguments</key>
    <array>
        <string>__TSCALED_BIN__</string>
        <string>--socket=/tmp/tailscaled-swiftbar.sock</string>
        <string>--state=__HOME__/Library/TailscaleSwiftBar/tailscaled.state</string>
        <string>--tun=userspace-networking</string>
        <string>--socks5-server=localhost:1055</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <key>ProcessType</key>
    <string>Background</string>

    <key>ThrottleInterval</key>
    <integer>5</integer>

    <key>WorkingDirectory</key>
    <string>/tmp</string>

    <key>StandardOutPath</key>
    <string>__HOME__/Library/Logs/tailscaled-swiftbar.log</string>

    <key>StandardErrorPath</key>
    <string>__HOME__/Library/Logs/tailscaled-swiftbar.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF
}

build_launchd_debug_text() {
  local launchctl_print_output
  local launchctl_print_cmd
  local bootstrap_cmd
  local kickstart_cmd
  local bootout_cmd

  launchctl_print_cmd="launchctl print gui/$(id -u)/$LAUNCHD_LABEL"
  bootstrap_cmd="launchctl bootstrap gui/$(id -u) \"$LAUNCHD_PLIST_TARGET\""
  kickstart_cmd="launchctl kickstart -k gui/$(id -u)/$LAUNCHD_LABEL"
  bootout_cmd="launchctl bootout gui/$(id -u)/$LAUNCHD_LABEL"

  if launchctl_print_output="$($launchctl_print_cmd 2>&1)"; then
    :
  else
    launchctl_print_output=$(printf '%s\n%s' "(launchctl print failed for current job)" "$launchctl_print_output")
  fi

  cat <<EOF
SwiftBar Tailscale launchd debug

Current binaries
  tailscaled: ${TSCALED_BIN:-not found}
  tailscale: ${TS_BIN:-not found}

Current paths
  state: $TS_STATE
  socket: $TS_SOCKET
  plist: $LAUNCHD_PLIST_TARGET

Useful commands
  $launchctl_print_cmd
  $bootstrap_cmd
  $kickstart_cmd
  $bootout_cmd
  "$TSCALED_BIN" --socket="$TS_SOCKET" --state="$TS_STATE" --tun=userspace-networking --socks5-server=localhost:1055
  "$TS_BIN" --socket="$TS_SOCKET" status

launchctl print output
------------------------------------------------------------
$launchctl_print_output
EOF
}

show_launchd_debug() {
  local debug_file="$HOME/Library/Logs/tailscaled-swiftbar-launchd-debug.txt"
  build_launchd_debug_text > "$debug_file"
  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy < "$debug_file"
  fi
  open -a TextEdit "$debug_file" >/dev/null 2>&1 || open "$debug_file" >/dev/null 2>&1 || true
  /usr/bin/osascript -e "display dialog \"Launchd debug text copied to clipboard and opened in TextEdit.\" with title \"SwiftBar Tailscale\" buttons {\"OK\"} default button \"OK\"" >/dev/null 2>&1 || true
}

run_as_admin() {
  local command="$1"
  /usr/bin/osascript -e "do shell script \"${command}\" with administrator privileges" >/dev/null
}

is_tailscaled_running() {
  pgrep -f "tailscaled.*${TS_SOCKET}" >/dev/null 2>&1
}

is_tailscale_stopped_status() {
  local status_output="$1"
  grep -q '^Tailscale is stopped\.$' <<<"$status_output" || grep -q 'failed to connect to local Tailscale service; is Tailscale running?' <<<"$status_output"
}

is_tailscale_explicitly_stopped() {
  local status_output="$1"
  grep -q '^Tailscale is stopped\.$' <<<"$status_output"
}

set_tailscale_desired_state() {
  local desired_state="$1"
  mkdir -p "$TS_STATE_DIR"
  printf '%s\n' "$desired_state" > "$TS_UP_STATE_FILE"
}

get_tailscale_desired_state() {
  if [[ -f "$TS_UP_STATE_FILE" ]]; then
    local desired_state
    desired_state="$(tr -d '[:space:]' < "$TS_UP_STATE_FILE" 2>/dev/null || true)"
    if [[ "$desired_state" == "yes" || "$desired_state" == "no" ]]; then
      printf '%s\n' "$desired_state"
      return 0
    fi
  fi
  printf '%s\n' "no"
}

is_launchagent_loaded() {
  launchctl print "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1
}

render_launchagent_plist() {
  local home_escaped
  local tailscaled_bin_escaped

  sed_escape_replacement() {
    printf '%s' "$1" | sed 's/[\\|&]/\\&/g'
  }

  if [[ -z "$TSCALED_BIN" || ! -x "$TSCALED_BIN" ]]; then
    return 1
  fi

  home_escaped="$(sed_escape_replacement "$HOME")"
  tailscaled_bin_escaped="$(sed_escape_replacement "$TSCALED_BIN")"
  build_launchagent_plist_text | sed -e "s|__HOME__|$home_escaped|g" -e "s|__TSCALED_BIN__|$tailscaled_bin_escaped|g" > "$LAUNCHD_PLIST_TARGET"
}

install_launchagent() {
  mkdir -p "$TS_STATE_DIR" "$HOME/Library/Logs" "$HOME/Library/LaunchAgents"
  if [[ -z "$TSCALED_BIN" || ! -x "$TSCALED_BIN" ]]; then
    notify "tailscaled not found"
    return 1
  fi

  render_launchagent_plist || return 1
  if is_launchagent_loaded; then
    launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
  fi
  launchctl bootstrap "gui/$(id -u)" "$LAUNCHD_PLIST_TARGET" >/dev/null 2>&1 || return 1
  return 0
}

uninstall_launchagent() {
  if is_launchagent_loaded; then
    launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1 || return 1
  fi
  rm -f "$LAUNCHD_PLIST_TARGET"
  return 0
}

wait_for_tailscaled() {
  local i=0
  while [[ $i -lt 10 ]]; do
    if is_tailscaled_running; then
      return 0
    fi
    sleep 0.2
    i=$((i + 1))
  done
  return 1
}

get_launchd_last_exit() {
  launchctl print "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null | awk -F'last exit code = ' '/last exit code = / {print $2; exit}'
}

get_launchd_failure_detail() {
  local last_line
  if [[ -f "$TSCALED_LOG" ]]; then
    last_line="$(tail -n 1 "$TSCALED_LOG" 2>/dev/null || true)"
    if [[ -n "$last_line" ]]; then
      printf '%s\n' "$last_line"
      return 0
    fi
  fi
  printf '%s\n' "No tailscaled log line found (log may not be created yet)."
}

start_tailscaled_launchd() {
  install_launchagent || return 1
  rm -f "$TS_SOCKET"

  if is_launchagent_loaded; then
    launchctl kickstart -k "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1
  else
    launchctl bootstrap "gui/$(id -u)" "$LAUNCHD_PLIST_TARGET" >/dev/null 2>&1
  fi
}

stop_tailscaled_launchd() {
  if is_launchagent_loaded; then
    launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1 || return 1
  fi
  return 0
}

handle_action() {
  local action="${1:-}"

  case "$action" in
    toggled)
      if is_tailscaled_running; then
        stop_tailscaled_launchd || true
        pkill -f "tailscaled.*$TS_SOCKET" >/dev/null 2>&1 || true
        notify "tailscaled stopped"
      else
        if [[ ! -x "$TSCALED_BIN" ]]; then
          notify "tailscaled not found: $TSCALED_BIN"
          exit 1
        fi
        if start_tailscaled_launchd && wait_for_tailscaled; then
          notify "tailscaled started (launchd)"
        else
          local launchd_exit
          local failure_detail
          launchd_exit="$(get_launchd_last_exit || true)"
          failure_detail="$(get_launchd_failure_detail)"
          notify "failed to start tailscaled (launchd: ${launchd_exit:-unknown})"
          show_error_dialog "tailscaled failed to start via launchd.\nlaunchd last exit: ${launchd_exit:-unknown}\n\nfailure detail:\n${failure_detail}\n\nUse Settings -> Open tailscaled log for full details."
          exit 1
        fi
      fi
      ;;
    stopd)
      if ! is_tailscaled_running; then
        notify "tailscaled not running"
        exit 0
      fi
      stop_tailscaled_launchd || true
      pkill -f "tailscaled.*$TS_SOCKET" >/dev/null 2>&1 || true
      notify "tailscaled stopped"
      ;;
    toggleup)
      local action_status_output
      if [[ ! -x "$TS_BIN" ]]; then
        notify "tailscale cli not found"
        exit 1
      fi
      if [[ "$VERSION_MISMATCH" == "yes" ]]; then
        notify "tailscale/tailscaled version mismatch: ${TS_BIN_VERSION} vs ${TSCALED_BIN_VERSION}"
        exit 1
      fi

      action_status_output="$("$TS_BIN" --socket="$TS_SOCKET" status 2>&1 || true)"
      if [[ -n "$action_status_output" ]] && ! is_tailscale_stopped_status "$action_status_output"; then
        "$TS_BIN" --socket="$TS_SOCKET" down >/dev/null 2>&1 || true
        set_tailscale_desired_state "no"
        notify "tailscale down done"
      else
        nohup "$TS_BIN" --socket="$TS_SOCKET" up --accept-dns=false --accept-routes >"$UP_LOG" 2>&1 &
        set_tailscale_desired_state "yes"
        notify "tailscale up started"
      fi
      ;;
    stopt)
      if [[ ! -x "$TS_BIN" ]]; then
        notify "tailscale cli not found"
        exit 1
      fi
      "$TS_BIN" --socket="$TS_SOCKET" down >/dev/null 2>&1 || true
      set_tailscale_desired_state "no"
      notify "tailscale down done"
      ;;
    up)
      if [[ ! -x "$TS_BIN" ]]; then
        notify "tailscale cli not found"
        exit 1
      fi
      if [[ "$VERSION_MISMATCH" == "yes" ]]; then
        notify "tailscale/tailscaled version mismatch: ${TS_BIN_VERSION} vs ${TSCALED_BIN_VERSION}"
        exit 1
      fi

      nohup "$TS_BIN" --socket="$TS_SOCKET" up --accept-dns=false --accept-routes >"$UP_LOG" 2>&1 &
      set_tailscale_desired_state "yes"
      notify "tailscale up started"
      ;;
    down)
      if [[ ! -x "$TS_BIN" ]]; then
        notify "tailscale cli not found"
        exit 1
      fi

      "$TS_BIN" --socket="$TS_SOCKET" down >/dev/null 2>&1 || true
      set_tailscale_desired_state "no"
      notify "tailscale down done"
      ;;
    pingnode)
      local node_ip="${2:-}"
      local ping_output
      if [[ -z "$node_ip" ]]; then
        notify "missing node ip"
        exit 1
      fi
      if [[ ! -x "$TS_BIN" ]]; then
        notify "tailscale cli not found"
        exit 1
      fi

      ping_output="$("$TS_BIN" --socket="$TS_SOCKET" ping "$node_ip" 2>&1 || true)"
      if grep -Eiq 'pong|is local' <<<"$ping_output"; then
        notify "ping ${node_ip} ok"
      else
        notify "ping ${node_ip} failed"
      fi
      ;;
    copyip)
      local node_ip="${2:-}"
      if [[ -z "$node_ip" ]]; then
        notify "missing node ip"
        exit 1
      fi

      if command -v pbcopy >/dev/null 2>&1; then
        printf '%s' "$node_ip" | pbcopy
        notify "copied ${node_ip}"
      else
        notify "pbcopy not found"
        exit 1
      fi
      ;;
    openuplog)
      open_in_console "$UP_LOG"
      ;;
    opendlog)
      open_in_console "$TSCALED_LOG"
      ;;
    showagent)
      show_launchagent
      ;;
    showdebug)
      show_launchd_debug
      ;;
    showpaths)
      show_binary_paths
      ;;
    installagent)
      if install_launchagent; then
        notify "launch agent installed"
      else
        notify "failed to install launch agent"
        exit 1
      fi
      ;;
    uninstallagent)
      if uninstall_launchagent; then
        notify "launch agent uninstalled"
      else
        notify "failed to uninstall launch agent"
        exit 1
      fi
      ;;
  esac
}

render_nodes_menu() {
  local status_text="$1"
  local found="no"
  local line
  local node_ip
  local node_name

  echo "Nodes"

  while IFS= read -r line; do
    node_ip="$(printf '%s\n' "$line" | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]/ {print $1}')"
    if [[ -z "$node_ip" ]]; then
      continue
    fi

    node_name="$(printf '%s\n' "$line" | awk '{print $2}')"
    if [[ -z "$node_name" ]]; then
      node_name="$node_ip"
    fi
    node_name="${node_name//|/ }"

    found="yes"
    echo "-- ${node_name} (${node_ip})"
    echo "---- Ping | bash='$0' param1='action' param2='pingnode' param3='${node_ip}' terminal=false refresh=false"
    echo "---- Copy IP | bash='$0' param1='action' param2='copyip' param3='${node_ip}' terminal=false refresh=false"
  done <<<"$status_text"

  if [[ "$found" != "yes" ]]; then
    echo "-- no nodes"
  fi
}

if [[ "${1:-}" == "action" ]]; then
  handle_action "${2:-}" "${3:-}"
  exit 0
fi

if [[ ! -x "$TS_BIN" ]]; then
  echo "TS:ERR"
  echo "---"
  echo "tailscale cli not found (checked Homebrew paths and Tailscale.app)"
  echo "Install | bash='/bin/zsh' param1='-lc' param2='brew install tailscale' terminal=true refresh=true"
  exit 0
fi

if [[ "$VERSION_MISMATCH" == "yes" ]]; then
  echo "TS:ERR"
  echo "---"
  echo "version mismatch: tailscale=${TS_BIN_VERSION}, tailscaled=${TSCALED_BIN_VERSION}"
  echo "Use same source/version for both binaries"
  echo "---"
  echo "Detected tailscale: ${TS_BIN}"
  echo "Detected tailscaled: ${TSCALED_BIN}"
  echo "---"
  echo "Settings"
  echo "-- Install LaunchAgent | bash='$0' param1='action' param2='installagent' terminal=false refresh=true"
  echo "-- Uninstall LaunchAgent | bash='$0' param1='action' param2='uninstallagent' terminal=false refresh=true"
  echo "-- Show LaunchAgent | bash='$0' param1='action' param2='showagent' terminal=false refresh=false"
  echo "-- Debug Launchd | bash='$0' param1='action' param2='showdebug' terminal=false refresh=false"
  echo "-- Show Binary Paths | bash='$0' param1='action' param2='showpaths' terminal=false refresh=false"
  echo "-- Open tailscaled log | bash='$0' param1='action' param2='opendlog' terminal=false refresh=false"
  echo "-- Open tailscale up log | bash='$0' param1='action' param2='openuplog' terminal=false refresh=false"
  exit 0
fi

daemon_ready="no"
connected="no"
tailscaled_running="no"
tailscaled_loaded="no"
tailscaled_active="no"
ipv4="-"
launchd_diag="ok"
status_output="$($TS_BIN --socket="$TS_SOCKET" status 2>&1 || true)"

if is_tailscaled_running; then
  tailscaled_running="yes"
fi

if is_launchagent_loaded; then
  tailscaled_loaded="yes"
  launchd_last_exit="$(get_launchd_last_exit || true)"
  if [[ "$tailscaled_running" != "yes" && -n "$launchd_last_exit" && "$launchd_last_exit" != 0* ]]; then
    launchd_diag="$launchd_last_exit"
  fi
else
  launchd_diag="not-loaded"
fi

if [[ "$tailscaled_loaded" == "yes" || "$tailscaled_running" == "yes" ]]; then
  tailscaled_active="yes"
fi

toggle_mark=""
if [[ "$tailscaled_active" == "yes" ]]; then
  toggle_mark="✓ "
fi

ts_toggle_mark=""
tailscale_desired="$(get_tailscale_desired_state)"

if [[ -n "$status_output" ]]; then
  if ! is_tailscale_stopped_status "$status_output"; then
    daemon_ready="yes"
    connected="yes"
    tailscale_desired="yes"
    ipv4="$(printf '%s\n' "$status_output" | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]/ {print $1; exit}')"
  elif is_tailscale_explicitly_stopped "$status_output"; then
    tailscale_desired="no"
  fi
fi

if [[ "$tailscale_desired" == "yes" ]]; then
  ts_toggle_mark="✓ "
fi

if [[ "$tailscaled_running" == "yes" && "$connected" == "yes" ]]; then
  echo "| image=$ONLINE_ICON_BASE64"
else
  echo "| image=$OFFLINE_ICON_BASE64"
fi

echo "---"
echo "Status: tailscaled=${tailscaled_active}, connected=${connected}"
echo "Launchd: ${launchd_diag}"
echo "Version: tailscale=${TS_BIN_VERSION:-unknown}, tailscaled=${TSCALED_BIN_VERSION:-unknown}"
echo "Mode: userspace socks5=1055"
echo "Socket: ${TS_SOCKET}"
echo "IPv4: ${ipv4}"
echo "---"
echo "${toggle_mark}tailscaled | bash='$0' param1='action' param2='toggled' terminal=false refresh=true"
echo "${ts_toggle_mark}tailscale | bash='$0' param1='action' param2='toggleup' terminal=false refresh=true"
echo "---"
render_nodes_menu "$status_output"
echo "---"
echo "Settings"
echo "-- Install LaunchAgent | bash='$0' param1='action' param2='installagent' terminal=false refresh=true"
echo "-- Uninstall LaunchAgent | bash='$0' param1='action' param2='uninstallagent' terminal=false refresh=true"
echo "-- Show LaunchAgent | bash='$0' param1='action' param2='showagent' terminal=false refresh=false"
echo "-- Debug Launchd | bash='$0' param1='action' param2='showdebug' terminal=false refresh=false"
echo "-- Show Binary Paths | bash='$0' param1='action' param2='showpaths' terminal=false refresh=false"
echo "-- Open tailscaled log | bash='$0' param1='action' param2='opendlog' terminal=false refresh=false"
echo "-- Open tailscale up log | bash='$0' param1='action' param2='openuplog' terminal=false refresh=false"
echo "---"
echo "Refresh now | refresh=true"
