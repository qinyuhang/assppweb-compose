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

# 询问配置
read -p "请输入域名: " APP_DOMAIN
read -p "请输入 Cloudflare API Token: " CF_API_TOKEN
# 生成 .env 文件
cat > .env <<EOL
APP_DOMAIN=$APP_DOMAIN
CF_API_TOKEN=$CF_API_TOKEN
EOL
echo ".env 文件已生成"


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
# 随机生成一个端口号，范围在 1024-65535
SNELL_PORT=$(shuf -i 1024-65535 -n 1)
# 随机生成一个密码，长度为 31 位
SNELL_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 31)
echo "Snell 配置已生成，端口: $SNELL_PORT，密码: $SNELL_PSK"
cat >> .env <<EOL
SNELL_PORT=$SNELL_PORT
SNELL_PSK=$SNELL_PSK
EOL
echo ".env 文件已生成"