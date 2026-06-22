#!/usr/bin/env bash

# 端到端验证脚本：确认 sing-box OCM 已成功设置并可以从 docker 访问

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPT="$SCRIPT_DIR/sing-box-ocm.5s.sh"

OCM_LISTEN_ADDR="127.0.0.1:3780"

echo "========================================="
echo "✅ sing-box OCM Setup Verification"
echo "========================================="

# Step 1: 检查 sing-box 是否安装
echo ""
echo "📦 Step 1: Checking sing-box installation..."
if ! which sing-box >/dev/null 2>&1; then
  echo "❌ sing-box not found. Install with: brew install sing-box"
  exit 1
fi
SING_BOX_VERSION=$(sing-box version | head -1)
echo "✅ sing-box installed: $SING_BOX_VERSION"

# Step 2: 检查 LaunchAgent 状态
echo ""
echo "🚀 Step 2: Checking LaunchAgent status..."
LABEL="com.qinyuhang.singbox.ocm"
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  STATUS=$(launchctl print "gui/$(id -u)/$LABEL" 2>&1 | grep "state =" | head -1)
  echo "✅ LaunchAgent loaded: $STATUS"
else
  echo "⚠️  LaunchAgent not loaded. Run: bash $PLUGIN_SCRIPT start"
fi

# Step 3: 检查进程
echo ""
echo "🔍 Step 3: Checking sing-box process..."
PGREP_OUTPUT=$(pgrep -f "sing-box.*run.*-c" || true)
if [[ -n "$PGREP_OUTPUT" ]]; then
  echo "✅ sing-box process running (PID: $PGREP_OUTPUT)"
else
  echo "⚠️  sing-box process not found. May be restarting..."
fi

# Step 4: 检查端口是否开放
echo ""
echo "🔌 Step 4: Checking port 3780..."
if lsof -i :3780 >/dev/null 2>&1; then
  echo "✅ Port 3780 is open"
else
  echo "⚠️  Port 3780 is not listening"
fi

# Step 5: 测试本地连接
echo ""
echo "🧪 Step 5: Testing local connectivity..."
RESPONSE=$(curl -s -w "\n%{http_code}" "http://$OCM_LISTEN_ADDR/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4","messages":[{"role":"user","content":"test"}]}' 2>&1)

if echo "$response" | grep -q "invalid_request_error\|only available in API key mode"; then
  echo "✅ OCM service is responding (API key mode message is expected)"
else
  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  if [[ "$HTTP_CODE" == "000" ]]; then
    echo "❌ Connection refused"
    exit 1
  else
    echo "✅ OCM service responded with HTTP $HTTP_CODE"
  fi
fi

# Step 6: 测试 docker 连接
echo ""
echo "🐳 Step 6: Testing docker connectivity..."
DOCKER_RESULT=$(docker run --rm \
  --network host \
  alpine:latest \
  sh -c "apk add --no-cache curl >/dev/null 2>&1 && curl -s 'http://$OCM_LISTEN_ADDR/v1/chat/completions' \
    -H 'Content-Type: application/json' \
    -d '{\"model\":\"gpt-4\",\"messages\":[{\"role\":\"user\",\"content\":\"test\"}]}' | head -c 100" 2>&1)

if echo "$DOCKER_RESULT" | grep -q "invalid_request_error\|only available in API key mode"; then
  echo "✅ Docker container can reach OCM service at $OCM_LISTEN_ADDR"
else
  echo "⚠️  Docker response: $DOCKER_RESULT"
fi

# Step 7: 显示配置信息
echo ""
echo "📋 Step 7: Configuration summary..."
echo "   Config: ~/.singbox-ocm/config.json"
echo "   Logs: ~/Library/Logs/singbox-ocm.log"
echo "   Listen: $OCM_LISTEN_ADDR"
echo "   LaunchAgent: ~/Library/LaunchAgents/$LABEL.plist"

# Step 8: 显示 codex 配置示例
echo ""
echo "🎯 Step 8: codex-cli configuration (optional)..."
echo "Add to ~/.codex/config.toml:"
echo ""
echo "  [model_providers.ocm_local]"
echo "  name = \"Local OCM Proxy\""
echo "  base_url = \"http://$OCM_LISTEN_ADDR/v1\""
echo "  supports_websockets = true"
echo ""
echo "  [profiles.ocm_local]"
echo "  model_provider = \"ocm_local\""
echo ""

echo ""
echo "========================================="
echo "✅ Verification complete!"
echo "========================================="
echo ""
echo "Quick commands:"
echo "  View menu status:   bash $PLUGIN_SCRIPT menu"
echo "  Show debug info:    bash $PLUGIN_SCRIPT debug"
echo "  View logs:          tail -f ~/Library/Logs/singbox-ocm.log"
echo "  Stop service:       bash $PLUGIN_SCRIPT stop"
echo "  Restart service:    bash $PLUGIN_SCRIPT reload"
