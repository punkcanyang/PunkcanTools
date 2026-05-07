# 多协议 VPN/代理一键安装脚本集

在 Debian/Ubuntu 和 CentOS/RHEL 系统上一键部署多种 VPN 和代理协议。每个协议独立子目录，包含安装和卸载脚本，同时提供两种发行版版本。

## ✨ 支持协议

| 协议 | 底层实现 | 传输 | 默认端口 | 适用场景 |
|------|---------|------|---------|---------|
| [VLESS + Reality](#vless--reality) | Xray-core | TCP | 443 | 抗检测，推荐 |
| [VLESS + WebSocket](#vless--websocket) | Xray-core | WebSocket+TLS | 443 | 支持 CDN 中转 |
| [Hysteria 2](#hysteria-2) | hysteria | QUIC/UDP | 443 | 高速，抗丢包 |
| [TUIC v5](#tuic-v5) | tuic-server | QUIC/UDP | 443 | 低延迟 |
| [Trojan](#trojan) | Xray-core | TCP+TLS | 443 | 伪装 HTTPS |
| [Trojan-Go](#trojan-go) | trojan-go | WS+TLS | 443 | 支持 CDN+多路复用 |
| [Shadowsocks](#shadowsocks) | Xray-core | TCP+UDP | 8388 | 轻量经典 |
| [SS-2022](#shadowsocks-2022) | Xray-core | TCP+UDP | 8388 | 新协议更安全 |
| [WireGuard](#wireguard) | 内核模块 | UDP | 51820 | 内核级 VPN |
| [OpenVPN](#openvpn) | openvpn | UDP | 1194 | 传统 VPN |
| [IKEv2](#ikev2) | StrongSwan | UDP | 500/4500 | iOS/Mac 原生 |
| [IPsec/L2TP](#ipsecl2tp) | StrongSwan+xl2tpd | UDP | 500/4500/1701 | 兼容性最广 |

## 📋 系统要求

| 系统 | 支持版本 |
|------|----------|
| Debian | 11 / 12 / 13 |
| Ubuntu | 20.04 / 22.04 / 24.04 |
| CentOS | 8 / 9 / Stream |
| RHEL/Rocky/Alma | 8 / 9 |

- Root 权限
- 网络连接

## 🚀 快速开始

```bash
# 克隆仓库
git clone https://github.com/punkcanyang/PunkcanTools.git
cd PunkcanTools/vless-reality-setup

# 给予执行权限
chmod +x *.sh */*.sh
```

选择想要的协议，运行对应的安装脚本即可。

## AI 自动部署第一版范围

AI 自动部署第一版只支援根目录的 VLESS + Reality，不要求全部协议都能由 AI 自动部署。这个范围用于让 AI 通过 command 完成远端服务器设定、取回设定资料，并交给本地 command line client 连线。

- 远端协议：VLESS + Reality
- 远端核心：Xray-core
- 本地 Client 核心：Xray-core
- 本地 Client 平台：macOS + Linux
- 设定输出：固定提供 JSON/YAML schema，同时保留 `vless://` 分享链接
- 多线路备援：第一版限定为多个 VLESS + Reality 节点，切换条件依序为手动优先级、连通性、延迟、失败次数

其他协议第一阶段保留给人类手动安装使用。等 VLESS + Reality 的 AI command 流程稳定后，再评估是否扩展到其他协议。

### AI Command 合约

VLESS + Reality 安装脚本支援非互动参数，适合 AI 通过 SSH 执行：

```bash
sudo bash install.sh --yes --port 443 --dest www.microsoft.com --dest-port 443 --json
sudo bash install-centos.sh --yes --port 443 --dest www.microsoft.com --dest-port 443 --json
```

若使用 sudo 使用者，可先上传或 clone 项目，再执行：

```bash
ssh user@server 'cd /path/to/vless-reality-setup && sudo bash install.sh --yes --json'
```

可用参数：

| 参数 | 说明 |
|------|------|
| `--port PORT` | 指定 VLESS 监听端口；明确指定时若端口被占用会直接失败 |
| `--dest HOST` | 指定 Reality 回落目标和 SNI，默认 `www.microsoft.com` |
| `--dest-port PORT` | 指定 Reality 回落目标端口，默认 `443` |
| `--uuid UUID` | 指定客户端 UUID；未指定时自动生成 |
| `--short-id HEX` | 指定 Reality short ID；未指定时自动生成 |
| `--server-ip IP` | 指定写入客户端设定的服务器地址；未指定时自动检测公网 IPv4 |
| `--json` | 安装完成后在 stdout 输出 JSON 合约 |
| `--yaml` | 安装完成后在 stdout 输出 YAML 合约 |
| `--yes` / `--non-interactive` | 非互动模式；遇到 unsupported OS 或网络检测失败时直接停止 |
| `--replace` | 明确允许覆盖既有 Xray 配置 |

安装完成后固定生成：

| 路径 | 说明 |
|------|------|
| `/usr/local/etc/xray/vless-reality.json` | AI 读取用 JSON schema |
| `/usr/local/etc/xray/vless-reality.yaml` | AI 读取用 YAML schema |
| `/usr/local/etc/xray/vless-link.txt` | `vless://` 分享链接 |
| `/usr/local/etc/xray/client-config.txt` | 人类可读完整客户端配置 |

正式合约文件在 `docs/ai-contract/`：

- `docs/ai-contract/vless-reality.schema.json`
- `docs/ai-contract/vless-reality.example.json`
- `docs/ai-contract/vless-reality.example.yaml`

JSON/YAML 合约字段包含 `schemaVersion`、`protocol`、`core`、`server`、`port`、`uuid`、`flow`、`transport`、`security`、`sni`、`dest`、`destPort`、`publicKey`、`shortId`、`fingerprint`、`shareLink`、`paths`、`service`、`healthCheck`。回报日志、PR、issue 或聊天内容时必须遮罩真实 `uuid`、`publicKey`、`shortId`、`shareLink` 与真实服务器地址。

### Xray 配置归属保护

目前 Xray-backed 协议仍共用 `/usr/local/etc/xray/config.json` 与同一个 `xray` systemd service；这不是多协议同时共存模式。为避免后安装的协议无声覆盖前一个协议，安装脚本会写入 `/usr/local/etc/xray/vrs-protocol` 归属标记。

适用协议：根目录 VLESS + Reality、`vless-ws/`、`trojan/`、`shadowsocks/`、`shadowsocks-2022/`。

- 安装时若发现既有 Xray 配置属于其他协议，或没有归属标记，脚本会停止；确认要替换时才加 `--replace`。
- 卸载时若归属标记不是当前协议，或没有归属标记，脚本会停止；确认要强制移除整套 Xray 时才加 `--force`。

### 本地 Command Line Client

P2 第一版新增 `client/vrs-client.sh`。它读取远端生成的 `vless-reality.json`，在本地生成 Xray client config，并提供基本启停、状态、日志和连线检查命令。第一版只支援 VLESS + Reality，适用 macOS + Linux。

本地需要先安装 Xray-core，并确认 `xray` 在 `PATH` 中；或通过 `XRAY_BIN=/path/to/xray` 指定执行档。

```bash
# 安装或检查本地 Xray-core
bash client/vrs-client.sh install-core
bash client/vrs-client.sh check-core

# 匯入远端取回的 JSON contract；priority 数值越小越优先
bash client/vrs-client.sh import ./vless-reality.json --name my-node --priority 10

# 选择线路；会写入 current、启动连线，并立刻检查是否正常连线
bash client/vrs-client.sh use --name my-node

# 自动选择线路；依序考虑 priority、连通性、延迟、失败次数
bash client/vrs-client.sh auto-use

# 单次健康检查；current 不可用时会自动尝试切线
bash client/vrs-client.sh watch --once

# 前景 watcher；定期检查 current，不可用时自动重连/切线
bash client/vrs-client.sh watch --interval 60

# 查看目前线路、状态与本地代理端口
bash client/vrs-client.sh current
bash client/vrs-client.sh status
bash client/vrs-client.sh list --sorted

# 透过本地 SOCKS 代理检查连线
bash client/vrs-client.sh check

# 停止本地代理
bash client/vrs-client.sh stop

# 安装成使用者层级背景服务
bash client/vrs-client.sh service install --name my-node
bash client/vrs-client.sh service status --name my-node
bash client/vrs-client.sh service uninstall --name my-node

# 安装 watcher 使用者层级背景服务
bash client/vrs-client.sh watch-service install --interval 60
bash client/vrs-client.sh watch-service status
bash client/vrs-client.sh watch-service uninstall
```

默认本地端口：

| 类型 | 地址 |
|------|------|
| SOCKS | `127.0.0.1:10808` |
| HTTP | `127.0.0.1:10809` |

本地状态目录默认在 `$HOME/.vrs/client`，可用 `VRS_CLIENT_HOME=/path/to/client-state` 覆盖。已支援多个 profile 的命名与列表，后续多线路备援会在这个基础上加入手动优先级、连通性、延迟与失败次数排序。

多线路资料写入 `$HOME/.vrs/client/profiles/index.json`。`check` 成功时会写入 `lastStatus=online`、`latencyMs` 并重置 `failureCount`；失败时会写入 `lastStatus=offline` 并累加 `failureCount`。

`auto-use` 会读取所有 `enabled=true` 的 profile，按 `priority`、`lastStatus`、`latencyMs`、`failureCount` 与名称排序后逐条尝试。第一条启动并检查成功的线路会成为 current；全部失败时返回非 0。

`install-core` 在 macOS 优先使用 Homebrew 的 `brew install xray`。Linux 优先使用 Homebrew；若没有 Homebrew，则下载并执行 XTLS 官方 `Xray-install` 脚本安装 Xray-core。

`service` 在 macOS 使用 `~/Library/LaunchAgents/io.punkcan.vrs.<name>.plist`，在 Linux 使用 `systemd --user` 的 `vrs-client-<name>.service`。服务模式会以前景执行 Xray，并由 launchd/systemd 管理重启。

`watch` 会定期检查 current profile；如果 current 不可用，会调用 `auto-use` 依候选顺序重新启动或切换线路。`watch-service` 在 macOS 使用 `~/Library/LaunchAgents/io.punkcan.vrs.watch.plist`，在 Linux 使用 `systemd --user` 的 `vrs-client-watch.service`。watcher 日志写入 `$HOME/.vrs/client/logs/watcher.log`。

## 📁 项目结构

```
vless-reality-setup/
├── install.sh              # VLESS+Reality 安装 (Debian/Ubuntu)
├── install-centos.sh       # VLESS+Reality 安装 (CentOS)
├── uninstall.sh            # VLESS+Reality 卸载
├── uninstall-centos.sh     # VLESS+Reality 卸载 (CentOS)
├── show-config.sh          # 查看配置
├── health-check.sh         # 健康检查
├── client/
│   └── vrs-client.sh       # 本地 Xray command line client
├── docs/
│   └── ai-contract/        # AI 自动部署 JSON/YAML 合约
│
├── vless-ws/               # VLESS + WebSocket + TLS
│   ├── install.sh / install-centos.sh
│   └── uninstall.sh / uninstall-centos.sh
│
├── hysteria2/              # Hysteria 2 (QUIC)
│   ├── install.sh / install-centos.sh
│   └── uninstall.sh / uninstall-centos.sh
│
├── tuic-v5/                # TUIC v5 (QUIC)
│   ├── install.sh / install-centos.sh
│   └── uninstall.sh / uninstall-centos.sh
│
├── trojan/                 # Trojan (Xray-core)
│   ├── install.sh / install-centos.sh
│   └── uninstall.sh / uninstall-centos.sh
│
├── trojan-go/              # Trojan-Go
│   ├── install.sh / install-centos.sh
│   └── uninstall.sh / uninstall-centos.sh
│
├── shadowsocks/            # Shadowsocks (AEAD)
│   ├── install.sh / install-centos.sh
│   └── uninstall.sh / uninstall-centos.sh
│
├── shadowsocks-2022/       # Shadowsocks 2022
│   ├── install.sh / install-centos.sh
│   └── uninstall.sh / uninstall-centos.sh
│
├── wireguard/              # WireGuard
│   ├── install.sh / install-centos.sh
│   └── uninstall.sh / uninstall-centos.sh
│
├── openvpn/                # OpenVPN
│   ├── install.sh / install-centos.sh
│   └── uninstall.sh / uninstall-centos.sh
│
├── ikev2/                  # IKEv2 (StrongSwan)
│   ├── install.sh / install-centos.sh
│   └── uninstall.sh / uninstall-centos.sh
│
└── ipsec/                  # IPsec/L2TP
    ├── install.sh / install-centos.sh
    └── uninstall.sh / uninstall-centos.sh
```

## 开发验证

```bash
bash -n *.sh */*.sh
bash client/test-vrs-client.sh
```

`client/test-vrs-client.sh` 是离线 regression test，不需要真实 Xray-core 或真实远端节点。它会使用 `/private/tmp` 的临时状态目录，验证本地 CLI 的匯入、index、Xray config 生成、失败路径状态回写、`auto-use` 与 `watch --once`。

---

## 各协议安装说明

### VLESS + Reality

抗检测能力最强的代理协议，无需证书。

```bash
sudo bash install.sh              # Debian/Ubuntu
sudo bash install-centos.sh       # CentOS/RHEL
```

安装脚本会在配置防火墙前保留 SSH 端口，避免远端部署后失联。若机器上已存在其他 Xray 配置，脚本会停止并避免覆盖；确认要替换时才使用：

```bash
sudo bash install.sh --replace
sudo bash install-centos.sh --replace
```

### VLESS + WebSocket

支持 CDN 中转（如 Cloudflare），适合 IP 被墙的情况。

```bash
sudo bash vless-ws/install.sh              # Debian/Ubuntu
sudo bash vless-ws/install-centos.sh       # CentOS/RHEL
sudo bash vless-ws/show-config.sh          # 查看配置
```

### Hysteria 2

基于 QUIC 的高速协议，UDP 传输，极佳的抗丢包性能。

```bash
sudo bash hysteria2/install.sh             # Debian/Ubuntu
sudo bash hysteria2/install-centos.sh      # CentOS/RHEL
sudo bash hysteria2/show-config.sh         # 查看配置
```

### TUIC v5

低延迟 QUIC 协议，0-RTT 握手。

```bash
sudo bash tuic-v5/install.sh               # Debian/Ubuntu
sudo bash tuic-v5/install-centos.sh        # CentOS/RHEL
sudo bash tuic-v5/show-config.sh           # 查看配置
```

### Trojan

伪装为正常 HTTPS 流量，使用密码认证。

```bash
sudo bash trojan/install.sh                # Debian/Ubuntu
sudo bash trojan/install-centos.sh         # CentOS/RHEL
sudo bash trojan/show-config.sh            # 查看配置
```

### Trojan-Go

Trojan 的 Go 语言实现，支持 WebSocket 和 CDN 中转。

```bash
sudo bash trojan-go/install.sh             # Debian/Ubuntu
sudo bash trojan-go/install-centos.sh      # CentOS/RHEL
sudo bash trojan-go/show-config.sh         # 查看配置
```

### Shadowsocks

轻量级代理，使用 AEAD 加密 (chacha20-ietf-poly1305)。

```bash
sudo bash shadowsocks/install.sh           # Debian/Ubuntu
sudo bash shadowsocks/install-centos.sh    # CentOS/RHEL
sudo bash shadowsocks/show-config.sh       # 查看配置
```

### Shadowsocks 2022

新一代 SS 协议 (2022-blake3-aes-128-gcm)，更安全，抗重放。

```bash
sudo bash shadowsocks-2022/install.sh          # Debian/Ubuntu
sudo bash shadowsocks-2022/install-centos.sh   # CentOS/RHEL
sudo bash shadowsocks-2022/show-config.sh      # 查看配置
```

### WireGuard

内核级 VPN，性能最佳，配置最简。

```bash
sudo bash wireguard/install.sh             # Debian/Ubuntu
sudo bash wireguard/install-centos.sh      # CentOS/RHEL
sudo bash wireguard/show-config.sh         # 查看配置
```

### OpenVPN

经典 SSL VPN，生成一体化 .ovpn 客户端文件。

```bash
sudo bash openvpn/install.sh               # Debian/Ubuntu
sudo bash openvpn/install-centos.sh        # CentOS/RHEL
sudo bash openvpn/show-config.sh           # 查看配置
```

### IKEv2

iOS/macOS/Windows 原生支持，使用 EAP 用户名密码认证。

```bash
sudo bash ikev2/install.sh                 # Debian/Ubuntu
sudo bash ikev2/install-centos.sh          # CentOS/RHEL
sudo bash ikev2/show-config.sh             # 查看配置
```

### IPsec/L2TP

兼容性最广的 VPN，所有操作系统原生支持，PSK 认证。

```bash
sudo bash ipsec/install.sh                 # Debian/Ubuntu
sudo bash ipsec/install-centos.sh          # CentOS/RHEL
sudo bash ipsec/show-config.sh             # 查看配置
```

---

## 🔧 卸载

每个协议都有对应的卸载脚本：

```bash
sudo bash uninstall.sh
sudo bash <协议目录>/uninstall.sh
```

Xray-backed 协议的卸载脚本会先检查 `/usr/local/etc/xray/vrs-protocol`。只有归属标记符合当前协议时才会继续移除 Xray；如果你确认要移除未标记或其他协议标记的 Xray，才使用 `--force`：

```bash
sudo bash uninstall.sh --force
sudo bash <协议目录>/uninstall.sh --force
```

## 📝 客户端推荐

| 平台 | 推荐客户端 | 适用协议 |
|------|-----------|---------|
| Windows | V2rayN, Clash Verge | VLESS, Trojan, SS, Hysteria2, TUIC |
| macOS | V2rayU, ClashX Pro | VLESS, Trojan, SS, Hysteria2, TUIC |
| iOS | Shadowrocket, Stash | 全部代理协议 |
| Android | V2rayNG, Clash for Android | VLESS, Trojan, SS, Hysteria2, TUIC |
| 全平台 | WireGuard 官方客户端 | WireGuard |
| 全平台 | OpenVPN Connect | OpenVPN |
| iOS/Mac | 系统内置 | IKEv2, IPsec/L2TP |

## 🔒 安全说明

- VLESS+Reality 使用 x25519 加密，无需证书
- 需要 TLS 的协议默认使用自签证书，客户端需允许不安全连接
- WireGuard/OpenVPN/IKEv2/IPsec 是完整 VPN 方案，全流量转发
- 建议定期更新各组件到最新版本

## 📜 许可证

MIT License
