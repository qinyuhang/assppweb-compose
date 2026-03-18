# 自动初始化项目
# 1. 安装依赖
# 包括 docker docker-compose-plugin
# 2. 询问配置
# 包括 域名，cloudflare key
# 生成 .env 文件
# 3. 启动项目
# 4. 提示用户访问域名

#!/bin/bash
# 安装依赖
if ! command -v docker &> /dev/null
then
    echo "Docker 未安装，正在安装..."
    # 安装 Docker 的命令，根据不同系统可能有所不同
    # 这里以 Ubuntu 为例
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sudo sh /tmp/get-docker.sh
    echo "Docker 安装完成"
else
    echo "Docker 已安装"
fi

# 询问配置（优先读取 .env）
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
    echo "检测到 .env，将按变量逐个确认是否需要更新"
fi

ask_or_keep() {
    local var_name="$1"
    local prompt="$2"
    local cur_val="${!var_name}"
    if [ -n "$cur_val" ]; then
        read -p "${var_name} 已存在，是否重新输入？[y/N]: " REINPUT
        if [[ "$REINPUT" =~ ^[Yy]$ ]]; then
            read -p "$prompt" new_val
            printf -v "$var_name" "%s" "$new_val"
        fi
    else
        read -p "$prompt" new_val
        printf -v "$var_name" "%s" "$new_val"
    fi
}

ask_or_keep "APP_DOMAIN" "请输入域名: "
ask_or_keep "CF_API_TOKEN" "请输入 Cloudflare API Token: "

# 生成 .env 文件
cat > .env <<EOL
APP_DOMAIN=$APP_DOMAIN
CF_API_TOKEN=$CF_API_TOKEN
EOL
echo ".env 文件已生成"

# 生成 WireGuard 配置
WG_DIR="./wireguard"
WG_CONF="$WG_DIR/wg0.conf"
echo "正在检查 WireGuard 配置..."
if [ -f "$WG_CONF" ]; then
    read -p "检测到 WireGuard 配置已存在 ($WG_CONF)，是否替换？[y/N]: " WG_REPLACE
    if [[ ! "$WG_REPLACE" =~ ^[Yy]$ ]]; then
        echo "已保留现有 WireGuard 配置"
        WG_SKIP_GEN=true
    fi
fi

if [ -z "$WG_SKIP_GEN" ]; then
    mkdir -p "$WG_DIR"
    if command -v wg &> /dev/null; then
        WG_PRIVATE_KEY=$(wg genkey)
    else
        WG_PRIVATE_KEY="REPLACE_WITH_WG_PRIVATE_KEY"
        echo "未检测到 wg 命令，已生成占位符私钥，请自行替换"
    fi

    cat > "$WG_CONF" <<EOL
[Interface]
Address = 172.16.0.1/24
ListenPort = 51820
PrivateKey = $WG_PRIVATE_KEY
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# 在此处添加客户端 Peer 配置
# [Peer]
# PublicKey = <client_public_key>
# AllowedIPs = 172.16.0.2/32
EOL

    echo "WireGuard 配置已生成：$WG_CONF"
fi


# 生成xray config
## uuid
echo "正在生成 Xray 配置..."
UUID=$(cat /proc/sys/kernel/random/uuid)
## copy config.json.example to config.json
cp xray-config/config.json.example xray-config/config.json
## replace uuid in config.json
sed -i "s/your-uuid-here/$UUID/g" xray-config/config.json
echo "Xray 配置已生成，UUID: $UUID"

# 生成snell config
echo "正在生成 Snell 配置..."
if [ -n "$SNELL_PORT" ] || [ -n "$SNELL_PSK" ]; then
    read -p "检测到 Snell 配置已存在，是否重新生成？[y/N]: " SNELL_REGEN
    if [[ "$SNELL_REGEN" =~ ^[Yy]$ ]]; then
        SNELL_PORT=""
        SNELL_PSK=""
    fi
fi

if [ -z "$SNELL_PORT" ]; then
    # 随机生成一个端口号，范围在 1024-65535
    SNELL_PORT=$(shuf -i 1024-65535 -n 1)
fi
if [ -z "$SNELL_PSK" ]; then
    # 随机生成一个密码，长度为 31 位
    SNELL_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 31)
fi
echo "Snell 配置已生成，端口: $SNELL_PORT，密码: $SNELL_PSK"

SNELL_PORT=$SNELL_PORT
SNELL_PSK=$SNELL_PSK
EOL
echo ".env 文件已生成"

