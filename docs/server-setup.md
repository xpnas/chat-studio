# 服务端连接与自测环境

## 已有 Studio

手机只需填写服务根地址和 Studio 账号密码。不要求在手机配置 Provider API key，也不要求修改服务器源码。

1. 在 Studio 网页确认可以登录、Profile 权限正确，并先配置至少一个可用模型。
2. 如果要使用 Hermes 引擎，先在 Studio 修复/安装 Hermes Runtime；否则可选择内置 Ekko。
3. 使用 HTTPS 域名连接；服务需要支持 WebSocket，不仅仅是普通 REST。
4. 首次默认凭据必须立即修改。生产服务不应暴露默认 `admin / 123456`。
5. 移动端退出只清除本地令牌；彻底撤销某个设备请到 Studio 设备/应用连接管理中操作。客户端没有虚构一个服务器并不存在的 logout / refresh API。

## 独立 Docker 部署模板（未在本机执行 Docker 验证）

`deploy/compose.yaml` 使用**上游自己的 Dockerfile**，不将 BSL 上游源码复制进移动端仓库。

```sh
# 在 mobile 仓库的同级目录获取源码
git clone --branch v1.0.3 --depth 1 https://github.com/EKKOLearnAI/hermes-studio.git ../hermes-studio-v1.0.3
git -C ../hermes-studio-v1.0.3 rev-parse HEAD
# 必须是 b44c74318fe5a0a1f3aed29d5095393964fc3d62
cd deploy
cp .env.example .env
# 编辑 .env，填写你已审阅的 Hermes 基础镜像 tag，推荐用固定 sha256 digest。
docker compose up -d --build
```

模板默认仅发布 `127.0.0.1:6060`，通过本机浏览器或 SSH 隧道访问并改密码、配置模型后，再配置 HTTPS 代理。**不要为了省事把初始服务直接暴露公网。** `.env` 不提交；数据使用 named volumes，销毁 volume 会丢数据。

上游 Dockerfile 默认 base image 是浮动 latest；此模板要求显式指定基础镜像，避免把“固定源码 tag”误当作全部依赖可逐字节复现。Docker 构建还涉及上游脚本及依赖兼容性，与本次已验证的 Node 源码服务不是同一种验证。

## HTTPS / WebSocket

同一宿主机上的 Caddy 示例见 `deploy/Caddyfile.example`。替换域名，配置 DNS、证书和防火墙。代理应转发整个 origin，包括 `/api/` 和 `/socket.io/`，不能只代理聊天页面。

Nginx 场景至少需要 WebSocket upgrade：

```nginx
# http {} 内
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}
# 已配置 TLS 的 server {} 内
location / {
    proxy_pass http://127.0.0.1:6060;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 3600s;
}
```

这里只是代理片段，非完整公网安全配置。不要禁用证书校验，不要把 provider 密钥放 URL 或移动端源码。

## 局域网

- Android 真机：电脑的私网 IP，如 `http://192.168.1.20:6060`；勾选 LAN HTTP，并在防火墙中只放行可信网段。
- Android Emulator：访问宿主机通常为 `http://10.0.2.2:6060`。
- iOS 真机：同一 LAN 地址，首次允许局域网权限；项目已提供权限用途说明。
- iOS Simulator：与服务同一 Mac 时可用 loopback。
- `localhost` 永远表示当前设备，不表示远程电脑。移动端不支持把 `/studio/` 等子路径作为 API 基址。

HTTP 不提供传输加密，允许 LAN 并不保证所在 Wi-Fi 安全。公网始终要求 HTTPS。

## 源码协议自测

见 `docs/testing.md` 和手动 `Studio contract` 工作流。使用固定 tag 的 Node 服务和本地 SSE 模型夹具，不需要付费模型密钥，也不会验证真实模型的能力。

重要：v1.0.3 的源码服务启动会监听 `0.0.0.0`，仅设置 `HOST=127.0.0.1` 并不能限制监听。测试只应在隔离 runner 或有防火墙限制的开发机运行，创建一次性目录、旋转初始密码，并在测试完成后停止服务。
