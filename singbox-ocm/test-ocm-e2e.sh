#!/usr/bin/env bash

# 端到端测试脚本：启动本地 sing-box OCM，用 docker codex-cli 验证连通

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPT="$SCRIPT_DIR/sing-box-ocm.5s.sh"

OCM_PORT="3780"
OCM_HOST="127.0.0.1"
OCM_LISTEN_ADDR="${OCM_HOST}:${OCM_PORT}"
TEST_TIMEOUT=30

echo "========================================="
echo "🧪 sing-box OCM End-to-End Test"
echo "========================================="

# Step 1: 初始化配置
echo -e "\n📦 Step 1: Initializing configuration..."
bash "$PLUGIN_SCRIPT" 2>/dev/null || true

# Step 2: 启动 sing-box OCM 服务
echo -e "\n🚀 Step 2: Starting sing-box OCM service..."
bash "$PLUGIN_SCRIPT" start
sleep 3

# Step 3: 检查 OCM 服务健康
echo -e "\n🏥 Step 3: Checking OCM service health..."
for i in $(seq 1 10); do
  if curl -s "http://${OCM_LISTEN_ADDR}/v1/models" >/dev/null 2>&1; then
    echo "✅ OCM service is healthy (attempt $i)"
    break
  fi
  echo "⏳ Waiting for OCM service... (attempt $i)"
  sleep 1
  if [[ $i -eq 10 ]]; then
    echo "❌ OCM service failed to respond"
    tail -20 "$HOME/Library/Logs/singbox-ocm.log"
    exit 1
  fi
done

# Step 4: 获取可用模型列表
echo -e "\n📋 Step 4: Fetching available models..."
MODELS=$(curl -s "http://${OCM_LISTEN_ADDR}/v1/models")
echo "Available models: $MODELS"

# Step 5: 用 docker codex-cli 测试
echo -e "\n🐳 Step 5: Testing with docker codex-cli..."

# 检查 docker 镜像是否存在
if ! docker image inspect ghcr.io/exo-explore/exo:latest >/dev/null 2>&1; then
  echo "⚠️  Pulling codex docker image..."
  docker pull ghcr.io/exo-explore/exo:latest
fi

# 运行 codex-cli 容器并测试连接
echo "Starting codex-cli container and testing connection..."
docker run --rm \
  --network host \
  -e CODEX_BASE_URL="http://${OCM_LISTEN_ADDR}/v1" \
  -e CODEX_API_KEY="dummy-key-for-testing" \
  ghcr.io/exo-explore/exo:latest \
  bash -c "
    set -e
    echo 'Testing connection to OCM service...'
    
    # 等待服务响应
    for i in {1..10}; do
      if curl -s 'http://${OCM_LISTEN_ADDR}/v1/models' >/dev/null 2>&1; then
        echo '✅ Connected to OCM service at http://${OCM_LISTEN_ADDR}/v1'
        break
      fi
      echo '⏳ Attempt \$i/10 - Waiting for service...'
      sleep 1
    done
    
    # 测试模型列表
    echo 'Fetching models list...'
    curl -s 'http://${OCM_LISTEN_ADDR}/v1/models' | head -50
    echo 'Test completed'
  " || {
    echo "❌ Docker test failed"
    exit 1
  }

# Step 6: 显示诊断信息
echo -e "\n🔧 Step 6: Service diagnostics..."
bash "$PLUGIN_SCRIPT" debug

# 清理
echo -e "\n🧹 Cleaning up..."
bash "$PLUGIN_SCRIPT" stop
sleep 1

echo -e "\n✅ All tests passed!"
echo "========================================="
echo "To use with codex-cli on your host, add this to ~/.codex/config.toml:"
echo ""
echo "[model_providers.ocm]"
echo "name = \"sing-box OCM\""
echo "base_url = \"http://${OCM_LISTEN_ADDR}/v1\""
echo "supports_websockets = true"
echo ""
echo "[profiles.ocm]"
echo "model_provider = \"ocm\""
echo "========================================="
