# cyo

自编译二进制仓库，供 PaaS / 免费容器平台部署代理服务使用，避免依赖第三方镜像源。
`web` / `bot` / `v1` / `sb` 全部由官方上游源码自行编译（Go 1.27.1，`CGO_ENABLED=0 -trimpath -ldflags "-s -w"`，静态链接 Linux ELF），构建溯源见下表。
`Plugins/` 目录另存官方插件原版镜像，供各替换器在官方源不可达时兜底下载。

## 文件列表

| 文件 | 说明 | 来源 |
|------|------|------|
| `web` | Xray-core（VLESS / Reality，官方源码，**不含 hy2 补丁**） | [XTLS/Xray-core](https://github.com/XTLS/Xray-core) @ 52a412d (v26.9.9) |
| `bot` | Cloudflared（Argo 隧道） | [cloudflare/cloudflared](https://github.com/cloudflare/cloudflared) @ 0f222b3 |
| `sb` | sing-box（tags: with_quic with_wireguard with_gvisor with_utls） | [SagerNet/sing-box](https://github.com/SagerNet/sing-box) @ f6ce1d5 |
| `v1` | 哪吒监控 agent（v1），版本号 5.5.5（ldflags 注入） | [nezhahq/agent](https://github.com/nezhahq/agent) @ 6df74da |
| `sbsh` | 辅助工具（历史遗留，未自编译） | - |
| `bot.so` / `v1.so` / `sbx.so` / `web.so` | 历史下载版（未自编译，供 FFI 方案使用） | - |

目录结构按架构区分：`amd64/`、`arm64/`。

## 构建方法（2026-09-11 构建）

```bash
# web = Xray-core
cd Xray-core/main && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o ../sbx-so/amd64/web .
# bot = cloudflared
cd cloudflared && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o ../sbx-so/amd64/bot ./cmd/cloudflared
# v1 = 哪吒 agent（必须注入版本号，否则哪吒后台版本显示为空；改版本号改 -X 后面的值即可）
cd agent && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X github.com/nezhahq/agent/pkg/monitor.Version=5.5.5" -o ../sbx-so/amd64/v1 ./cmd/agent
# sb = sing-box（注意：新版本 with_ech tag 已废弃，不要再加）
cd sing-box && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -tags "with_quic with_wireguard with_gvisor with_utls" -o ../sbx-so/amd64/sb ./cmd/sing-box
# arm64 把 GOARCH 换成 arm64 即可
```

## 下载地址

```
https://raw.githubusercontent.com/cyoxyu/cyo/main/amd64/web
https://raw.githubusercontent.com/cyoxyu/cyo/main/amd64/bot
https://raw.githubusercontent.com/cyoxyu/cyo/main/arm64/web
https://raw.githubusercontent.com/cyoxyu/cyo/main/arm64/bot
```

示例：

```bash
curl -fsSL -o web https://raw.githubusercontent.com/cyoxyu/cyo/main/amd64/web && chmod +x web
```

## Plugins（官方插件镜像）

官方插件原版包，替换器优先走官方源，此处为兜底镜像。均已校验大小与 SHA-256。

| 文件 | 官方来源 | 大小 | SHA-256 |
|------|----------|------|---------|
| `EssentialsX-2.21.1.jar` | [EssentialsX/Essentials Release 2.21.1](https://github.com/EssentialsX/Essentials/releases/download/2.21.1/EssentialsX-2.21.1.jar) | 4,655,797 | `15dd7f8713e613a1ddeada792db660a88c8bf69015bc13f1a9f9e37f6d44cf5a` |
| `Geyser-Spigot.jar` | [Modrinth Geyser (cEESv2Kx)](https://cdn.modrinth.com/data/wKkoqHrH/versions/cEESv2Kx/Geyser-Spigot.jar) | 19,662,581 | `b754bb257976549553239be82c4b1a8ca97bac997c8799fdee5a28a287e7fda6` |
| `lithium-fabric-0.21.4+mc1.21.11.jar` | [Modrinth Lithium (Ow7wA0kG)](https://cdn.modrinth.com/data/gvQqBUqZ/versions/Ow7wA0kG/lithium-fabric-0.21.4%2Bmc1.21.11.jar) | 900,462 | `5135c41da5b43cbdcb29424bde65195143ac4084e23834c8eac065942201c78b` |

镜像下载地址：

```
https://raw.githubusercontent.com/cyoxyu/cyo/main/Plugins/EssentialsX-2.21.1.jar
https://raw.githubusercontent.com/cyoxyu/cyo/main/Plugins/Geyser-Spigot.jar
https://raw.githubusercontent.com/cyoxyu/cyo/main/Plugins/lithium-fabric-0.21.4%2Bmc1.21.11.jar
```
