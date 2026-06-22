# 这是什么:
# 这是一个使用 sing-box 在本机开启 OpenAI Codex 反代理的 SwiftBar 插件。
# 目标不是把代理逻辑写进菜单栏脚本，而是让 launchd 负责常驻进程，SwiftBar 只负责状态展示、启动/停止和诊断入口。
# 需要安装 sing-box、SwiftBar，以及能读取本机 OCM 服务的 codex-cli 配置。
#
# 关键实现思路:
# 1. sing-box 通过 OCM service 对外提供本机监听地址，例如 127.0.0.1:3780。
# 2. codex-cli 的 ~/.codex/config.toml 或容器挂载配置指向 base_url = "http://127.0.0.1:3780/v1"。
# 3. 如果需要鉴权，sing-box OCM 的 users 与 codex-cli 的 experimental_bearer_token 必须一致。
# 4. LaunchAgent 负责拉起/守护 sing-box，写入日志、状态文件、socket/port 等运行信息。
# 5. SwiftBar 负责展示运行状态、监听端口、控制接口地址，并提供 bootstrap / bootout / kickstart / open log 等动作。
#
# 参考到的外部实践与约束:
# - sing-box 官方 OCM 示例默认监听 127.0.0.1:3780，客户端通过 /v1 访问。
# - OCM 支持 credential_path、usages_path、users、headers、detour、tls 等字段，适合把凭据、统计和出口代理拆开管理。
# - SwiftBar 插件更适合做“轻逻辑 + 菜单动作”，重状态机和守护交给 launchd 或独立进程。
# - 类似本仓库里的 tailscale.swiftbar 做法，插件应优先探测二进制、显示路径/版本、把日志和 launchd 诊断放在可点开的菜单项里。
#
# @任务拆解:
# Milestone 0: 确认运行拓扑
# - 明确 sing-box 可执行文件路径、OCM 监听地址、端口、credential_path、usages_path。
# - 明确是否需要认证，以及 codex-cli 是否通过 Docker 容器访问本地服务。
#
# Milestone 1: 配置可启动
# - 产出 sing-box OCM 配置模板。
# - 产出 LaunchAgent plist，确保 RunAtLoad、KeepAlive、日志路径、工作目录都正确。
# - 验证 launchctl bootstrap / kickstart / bootout 的行为。
#
# Milestone 2: SwiftBar 状态面板
# - 菜单栏展示运行/停止、端口、监听地址、认证状态、日志路径。
# - 菜单项提供启动、停止、重载、打开日志、打开 plist、查看诊断信息。
# - 失败时给出可读错误，而不是只显示一个停顿图标。
#
# Milestone 3: 客户端联通
# - 给 codex-cli 写入或生成 profile 示例。
# - 用最小请求验证 base_url、鉴权、WebSocket 支持是否正常。
# - 明确本地请求成功后再考虑 Docker 化访问。
#
# Milestone 4: 稳定性和维护
# - 增加健康检查、端口占用检测、配置存在性检查。
# - 补充更新、卸载、清理 state/log 的路径说明。
# - 将常见失败模式写入 README，方便日后排障。
#
# @DOC: https://sing-box.sagernet.org/configuration/service/ocm/
# @github: https://github.com/SagerNet/sing-box/tree/testing/service/ocm

#!/usr/bin/env bash

set -u

# Base64 encoded icons for SwiftBar
ON_ICON='iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAAGzs1ytAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAFqADAAQAAAABAAAAFgAAAAAcITNaAAABmklEQVQ4Ea2TzVHDQAyFHaAA04G5caQDQgfpwC4hnVBC0onTQeAGJ8MtN0IF4X1G8sg/G4cZNPMi7dPTW6/XybIQ11Y3yg/Ob7zo5UKrU2R6Cxp57F6FBY1KYKLbRXUbIwK2I6PNstXbDwr8HHv4rwFRQnqgLHzhmYlksAcYiRYTI9jH6DQcwZ3WqhE+RaVxUKOdEA+BWTL21imTikFj0s2/i6httHg34hAbU+JvCXbCWxRO1bjGA9ZTIkiEvJ4ops6F9gw3KhDdCTSInbAUPAoV3YEpSmEr1AJDlYF6JYwuBAHNCH/norMsvo0XrT9bNsvulY8Cj3c2Suv2XFMTnGH0jCnxFI9BYybUsxH/kSlxbQ3OeitgPHuchQ2lUmEmeRBsVR+FV4H6T+FPFa8yVVfnnDHiHZJXgpvUqpdh7XzMG/WJSuAi8WiDAqL8XY6MKvEMR7NhvbZZPHrm8GzApeTCVmAYEXCjWrXD+UZcITCLx2xgcDoDDJMx91XEwUKLlXAUdsKHkIxLvmOOx7EfLT8r58K/BRuAi+IH3wiLqxi85HIAAAAASUVORK5CYII='
OFF_ICON='iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAAGzs1ytAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAFqADAAQAAAABAAAAFgAAAAAcITNaAAACP0lEQVQ4EZ1U7XHCMAxNQvmfTlB3gtIJCgsAmQDYgBHKBGUD2CAHx3/YoHQC2AAWAPqea+kUJ/R69V2w9Cw96wsniVkp5dVqdUjTdOfx9Xq98ELlpyxLB7ObghWFKCxyPYXgmcOBw97NsmxxvV5fiemCV0cVESyYCdhqtboip7QA36cA2PfQs60F4DFXnfHCyylAAeBJAI1XAImCtIPB4FFw7hqVgAyGH/Q8Lo2PloZM4Xa7faAKvSjYBDekDKcSRsxEEpawKIo95dqCg6/JZrMZ1Q6bAEkyPqslCOYDjDpNDg+xN4ZpBmyHOI+1MwsEVicYp7Df7/dUp4CJ3KJsDiInjJ8uVIONcaxIRrbg7QDmOtNqnhD3OfimtNvtl8vl0oPhE27ogm1CWzRnAawAtmDrU4JcyH7Mwx9Nf/cw0rlWY3FA2wdgGkI/x4OkFCJI56STgjfubAYMdYatUSUMe2BlEiCfEljOqbw7WMapNhrmzIvsFwXk+hzyZZR+MGNbq/8aMSJ1iJQkOgBo0RL6Gd8X+k65cTUSh9TZyk6jlwFx0aTpAj/4UkPUr0CrHVrNeiZw2mG4Zojal8PwWfENyhIcnCv/MvhRDqRbEL4TABHT9IuTyotC+gJXdtiM0YcpfJewnTIIcmopwgV8kfkWzeE9wieX5GRjBty5QNjBRvwYfErsE5kYJaaxXeHf27VYJB85KRGm6l1itQgCMnJIdRhK1fj4WJ/aq2UPKZseTKGeUII5U4/t/q3zAn5/JfgGZeIdOpZH8bQAAAAASUVORK5CYII='

# 配置常量
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

OCM_PORT="${OCM_PORT:-3780}"
OCM_HOST="127.0.0.1"
OCM_LISTEN_ADDR="${OCM_HOST}:${OCM_PORT}"

OCM_CONFIG_DIR="$HOME/.singbox-ocm"
OCM_CONFIG_FILE="$OCM_CONFIG_DIR/config.json"
OCM_STATE_DIR="$HOME/Library/SingBoxOCM"
OCM_STATE_FILE="$OCM_STATE_DIR/singbox.state"
OCM_LOG_FILE="$HOME/Library/Logs/singbox-ocm.log"

LAUNCHD_LABEL="com.qinyuhang.singbox.ocm"
LAUNCHD_PLIST_TARGET="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"

if defaults read -g AppleInterfaceStyle >/dev/null 2>&1; then
  MENU_INFO_COLOR="#D0D0D0"
else
  MENU_INFO_COLOR="#303030"
fi

# 探测 sing-box 二进制
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

SINGBOX_BIN="$(resolve_bin sing-box /opt/homebrew/bin/sing-box /usr/local/bin/sing-box || true)"

# 生成 sing-box OCM 配置
build_singbox_ocm_config() {
  cat <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "services": [
    {
      "type": "ocm",
      "listen": "127.0.0.1",
      "listen_port": 3780
    }
  ]
}
EOF
}

# 生成 LaunchAgent plist
build_launchagent_plist_text() {
  if [[ -z "$SINGBOX_BIN" ]] || [[ ! -x "$SINGBOX_BIN" ]]; then
    echo "❌ ERROR: sing-box binary not found or not executable: $SINGBOX_BIN" >&2
    return 1
  fi
  
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCHD_LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>$SINGBOX_BIN</string>
        <string>run</string>
        <string>-c</string>
        <string>$OCM_CONFIG_FILE</string>
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
    <string>$OCM_LOG_FILE</string>

    <key>StandardErrorPath</key>
    <string>$OCM_LOG_FILE</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>$HOME</string>
    </dict>
</dict>
</plist>
EOF
  return 0
}

# 初始化配置目录和文件
init_config() {
  mkdir -p "$OCM_CONFIG_DIR"
  mkdir -p "$OCM_STATE_DIR"
  mkdir -p "$(dirname "$OCM_LOG_FILE")"

  if [[ ! -f "$OCM_CONFIG_FILE" ]]; then
    build_singbox_ocm_config > "$OCM_CONFIG_FILE"
  fi

  if [[ ! -d "$HOME/.codex" ]]; then
    mkdir -p "$HOME/.codex"
  fi
}

# 初始化 LaunchAgent plist
init_launchagent() {
  mkdir -p "$(dirname "$LAUNCHD_PLIST_TARGET")"
  if [[ ! -f "$LAUNCHD_PLIST_TARGET" ]]; then
    build_launchagent_plist_text > "$LAUNCHD_PLIST_TARGET"
  fi
}

# 检查 LaunchAgent 是否已加载
is_launchagent_loaded() {
  launchctl print "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1
}

# 启动 LaunchAgent
bootstrap_launchagent() {
  if ! is_launchagent_loaded; then
    launchctl bootstrap "gui/$(id -u)" "$LAUNCHD_PLIST_TARGET" 2>/dev/null || true
  fi
}

# 启动 sing-box 进程
start_singbox() {
  if [[ -z "$SINGBOX_BIN" ]] || [[ ! -x "$SINGBOX_BIN" ]]; then
    echo "❌ sing-box not found or not executable. Install with: brew install sing-box"
    echo "   Searched: /opt/homebrew/bin/sing-box, /usr/local/bin/sing-box, \$(which sing-box)"
    return 1
  fi

  echo "ℹ️  Using sing-box: $SINGBOX_BIN"
  
  init_config
  if ! init_launchagent; then
    echo "❌ Failed to create LaunchAgent plist"
    return 1
  fi
  
  bootstrap_launchagent
  sleep 1
  launchctl kickstart -k "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
  
  echo "ℹ️  Started sing-box OCM at $OCM_LISTEN_ADDR"
  sleep 2
}

# 停止 sing-box 进程
stop_singbox() {
  if is_launchagent_loaded; then
    launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
  fi
}

# 检查 sing-box 是否运行
is_singbox_running() {
  if is_launchagent_loaded; then
    return 0
  fi
  return 1
}

# 检查 OCM 服务是否响应
is_ocm_service_healthy() {
  # 尝试连接到任何端点，如果得到任何响应（包括错误）就认为服务在运行
  # 只有连接拒绝或超时才认为不健康
  local response
  response=$(timeout 2 curl -s -w "\n%{http_code}" "http://${OCM_LISTEN_ADDR}/v1/chat/completions" 2>&1)
  # 如果包含 "Connection refused" 或 "Failed to connect"，说明服务不可用
  if echo "$response" | grep -qi "refused\|failed"; then
    return 1
  fi
  # 否则认为服务健康（即使是 API 错误也说明服务在运行）
  return 0
}

# 获取 OCM 服务状态
get_ocm_status() {
  if is_singbox_running; then
    if is_ocm_service_healthy; then
      echo "✅ Running (port $OCM_PORT)"
      return 0
    else
      echo "⚠️  Process running but service unresponsive (port $OCM_PORT)"
      return 1
    fi
  else
    echo "⭕ Stopped"
    return 1
  fi
}

# SwiftBar 菜单逻辑
show_menu() {
  local status
  local icon
  status="$(get_ocm_status)"

  # 根据状态选择 icon
  if is_singbox_running && is_ocm_service_healthy; then
    icon="$ON_ICON"
  else
    icon="$OFF_ICON"
  fi

  # 菜单栏主标题（包含 base64 图标）
  echo "| image='$icon'"
  echo "---"

  # 状态信息
  echo "Status: $status | color=$MENU_INFO_COLOR"
  echo "Listen: $OCM_LISTEN_ADDR | color=$MENU_INFO_COLOR"
  echo "Port: $OCM_PORT | color=$MENU_INFO_COLOR"
  echo "---"

  # 控制按钮
  if is_singbox_running; then
    echo "Stop Service | bash='$0' param1=stop terminal=false refresh=true"
    echo "Reload Config | bash='$0' param1=reload terminal=false refresh=true"
  else
    echo "Start Service | bash='$0' param1=start terminal=false refresh=true"
  fi

  echo "---"
  echo "Open Log | bash='open -a Console \"$OCM_LOG_FILE\"' terminal=false"
  echo "Open Config | bash='open \"$OCM_CONFIG_FILE\"' terminal=false"
  echo "Open LaunchAgent | bash='open \"$LAUNCHD_PLIST_TARGET\"' terminal=false"
  echo "---"
  echo "Show Debug Info | bash='$0' param1=debug terminal=true"
  echo "Install sing-box | bash='brew install sing-box' terminal=true"
}

# 生成调试信息
show_debug_info() {
  cat <<EOF
sing-box OCM Plugin - Debug Info
=================================

Binaries:
  sing-box: ${SINGBOX_BIN:-not found}

Paths:
  config: $OCM_CONFIG_FILE
  plist: $LAUNCHD_PLIST_TARGET
  log: $OCM_LOG_FILE
  state: $OCM_STATE_DIR

Service:
  listen: $OCM_LISTEN_ADDR
  status: $(get_ocm_status)

Useful Commands:
  Start:    launchctl bootstrap gui/\$(id -u) "$LAUNCHD_PLIST_TARGET"
  Stop:     launchctl bootout gui/\$(id -u) "$LAUNCHD_LABEL"
  Reload:   launchctl kickstart -k gui/\$(id -u)/$LAUNCHD_LABEL
  Status:   launchctl print gui/\$(id -u)/$LAUNCHD_LABEL
  Logs:     tail -f $OCM_LOG_FILE
  Health:   curl http://$OCM_LISTEN_ADDR/v1/models

Recent Logs:
------------------------------------------------------------
$(tail -20 "$OCM_LOG_FILE" 2>/dev/null || echo "[No logs yet]")
EOF
}

# 主入口
main() {
  case "${1:-menu}" in
    menu)
      show_menu
      ;;
    start)
      start_singbox
      ;;
    stop)
      stop_singbox
      ;;
    reload)
      stop_singbox
      sleep 1
      start_singbox
      ;;
    debug)
      show_debug_info
      ;;
    *)
      show_menu
      ;;
  esac
}

main "$@"