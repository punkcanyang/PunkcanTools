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

## 📁 项目结构

```
vless-reality-setup/
├── install.sh              # VLESS+Reality 安装 (Debian/Ubuntu)
├── install-centos.sh       # VLESS+Reality 安装 (CentOS)
├── uninstall.sh            # VLESS+Reality 卸载
├── uninstall-centos.sh     # VLESS+Reality 卸载 (CentOS)
├── show-config.sh          # 查看配置
├── health-check.sh         # 健康检查
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

---

## 各协议安装说明

### VLESS + Reality

抗检测能力最强的代理协议，无需证书。

```bash
sudo bash install.sh              # Debian/Ubuntu
sudo bash install-centos.sh       # CentOS/RHEL
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
sudo bash <协议目录>/uninstall.sh
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
