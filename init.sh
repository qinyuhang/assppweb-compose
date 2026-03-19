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

# WireGuard 端口
if [ -n "$WG_PORT" ]; then
    read -p "检测到 WG_PORT=$WG_PORT，是否重新设置 WireGuard 端口？[y/N]: " WG_PORT_RESET
    if [[ "$WG_PORT_RESET" =~ ^[Yy]$ ]]; then
        WG_PORT=""
    fi
fi
if [ -z "$WG_PORT" ]; then
    is_port_free() {
        local p="$1"
        if command -v ss >/dev/null 2>&1; then
            ss -lntu | awk '{print $5}' | grep -E "[:.]${p}\$" -q && return 1 || return 0
        elif command -v netstat >/dev/null 2>&1; then
            netstat -lntu | awk '{print $4}' | grep -E "[:.]${p}\$" -q && return 1 || return 0
        else
            return 0
        fi
    }

    pick_random_port() {
        local p
        for _ in $(seq 1 20); do
            p=$(shuf -i 1024-65535 -n 1)
            if is_port_free "$p"; then
                echo "$p"
                return 0
            fi
        done
        echo ""
        return 1
    }

    read -p "WireGuard 使用默认端口 51820 吗？[Y/n]: " WG_USE_DEFAULT
    if [[ "$WG_USE_DEFAULT" =~ ^[Nn]$ ]]; then
        read -p "选择端口方式：1) 手动输入 2) 随机生成 [1/2]: " WG_PORT_MODE
        if [[ "$WG_PORT_MODE" == "1" ]]; then
            while true; do
                read -p "请输入 WireGuard 端口 (1024-65535): " WG_PORT
                if [[ "$WG_PORT" =~ ^[0-9]+$ ]] && [ "$WG_PORT" -ge 1024 ] && [ "$WG_PORT" -le 65535 ]; then
                    if is_port_free "$WG_PORT"; then
                        break
                    else
                        echo "端口 $WG_PORT 已被占用，请换一个"
                    fi
                else
                    echo "端口格式不正确，请重新输入"
                fi
            done
        else
            WG_PORT=$(pick_random_port)
            if [ -z "$WG_PORT" ]; then
                echo "未能生成可用端口，改用默认端口 51820"
                WG_PORT=51820
            else
                echo "已生成 WireGuard 随机端口: $WG_PORT"
            fi
        fi
    else
        WG_PORT=51820
    fi
fi

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
ListenPort = $WG_PORT
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

# 生成 TrustTunnel 配置
echo "正在生成 TrustTunnel 配置..."
echo "注意：TrustTunnel 将使用 Caddy 自动续期的 Let's Encrypt 证书"
if [ -n "$TRUSTTUNEL_DOMAIN" ] || [ -n "$TRUSTTUNEL_USERNAME" ] || [ -n "$TRUSTTUNEL_PASSWORD" ]; then
    read -p "检测到 TrustTunnel 配置已存在，是否重新生成？[y/N]: " TT_REGEN
    if [[ "$TT_REGEN" =~ ^[Yy]$ ]]; then
        TRUSTTUNEL_DOMAIN=""
        TRUSTTUNEL_USERNAME=""
        TRUSTTUNEL_PASSWORD=""
    fi
fi

if [ -z "$TRUSTTUNEL_DOMAIN" ]; then
    read -p "请输入 TrustTunnel 域名 (直接回车使用主域名 ${APP_DOMAIN}): " TRUSTTUNEL_DOMAIN_INPUT
    TRUSTTUNEL_DOMAIN=${TRUSTTUNEL_DOMAIN_INPUT:-$APP_DOMAIN}
fi

# 生成随机用户名和密码
if [ -z "$TRUSTTUNEL_USERNAME" ]; then
    TRUSTTUNEL_USERNAME="user$(tr -dc 0-9 </dev/urandom | head -c 6)"
fi
if [ -z "$TRUSTTUNEL_PASSWORD" ]; then
    TRUSTTUNEL_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
fi

echo "TrustTunnel 域名: tt.$TRUSTTUNEL_DOMAIN"
echo "TrustTunnel 用户名: $TRUSTTUNEL_USERNAME"
echo "TrustTunnel 密码: $TRUSTTUNEL_PASSWORD"
echo ""
echo "证书将由 Caddy 自动获取并续期，路径:"
echo "/caddy-data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/tt.$TRUSTTUNEL_DOMAIN/"

# 更新 hosts.toml 中的域名（使用 | 作为分隔符以避免域名中的 / 引起问题）
# 注意：hosts.toml 中使用 tt. 子域名
sed -i "s|TRUSTTUNEL_DOMAIN_PLACEHOLDER|$TRUSTTUNEL_DOMAIN|g" trusttunnel-config/hosts.toml

# 更新 credentials.toml 中的用户名和密码
sed -i "s/TRUSTTUNEL_USERNAME_PLACEHOLDER/$TRUSTTUNEL_USERNAME/g" trusttunnel-config/credentials.toml
sed -i "s/TRUSTTUNEL_PASSWORD_PLACEHOLDER/$TRUSTTUNEL_PASSWORD/g" trusttunnel-config/credentials.toml

# 将所有配置写回 .env
cat > .env <<EOL
APP_DOMAIN=$APP_DOMAIN
CF_API_TOKEN=$CF_API_TOKEN
WG_PORT=$WG_PORT
SNELL_PORT=$SNELL_PORT
SNELL_PSK=$SNELL_PSK
TRUSTTUNEL_DOMAIN=$TRUSTTUNEL_DOMAIN
TRUSTTUNEL_USERNAME=$TRUSTTUNEL_USERNAME
TRUSTTUNEL_PASSWORD=$TRUSTTUNEL_PASSWORD
EOL
echo ".env 文件已生成"

echo "TrustTunnel 配置已生成，配置位于 trusttunnel-config/ 目录"
echo ""
echo "重要提示："
echo "1. 首次启动时，请先启动 caddy 服务以获取证书:"
echo "   docker-compose up -d caddy"
echo "2. 等待证书获取成功后（查看日志: docker-compose logs -f caddy），再启动 trusttunnel:"
echo "   docker-compose up -d trusttunnel"
echo "3. 客户端连接地址: tt.$TRUSTTUNEL_DOMAIN:8443"
