# AssppWeb-Compose

在vps部署，并且套了cloudflare cdn，访问速度非常快，且不受限于国内网络环境。

## 使用方法
1. clone项目到vps
2. 配置cloudflare cdn，添加一个A记录，指向vps的ip地址，并且开启proxied（云朵图标为橙色）
3. 复制 `env.example` 为 `.env` 文件，并且修改其中的环境变量
4. 运行 `docker compose up -d` 启动服务
