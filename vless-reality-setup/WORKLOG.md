# WORKLOG - vless-reality-setup

## 2026-03-27 多协议安装脚本 (续)

### 第二阶段：CentOS 版本 + show-config.sh

在 Debian/Ubuntu 版本基础上，新增了 CentOS/RHEL 版本和配置查看工具。

#### 新增文件

**CentOS 版脚本 (22 个)**

每个协议目录新增 `install-centos.sh` 和 `uninstall-centos.sh`：

| 协议 | 与 Debian 版差异 |
|------|----------------|
| 全部 | `dnf/yum` 替代 `apt-get`、`firewalld` 替代 `ufw`、EPEL 仓库 |
| OpenVPN | Easy-RSA 路径不同、group 为 `nobody` 非 `nogroup` |
| WireGuard | CentOS 8+ 内核已内置支持 |

**show-config.sh (11 个)**

每个协议目录新增 `show-config.sh`，功能：
- 显示 CLIENT_CONFIG_FILE 完整配置
- 显示分享链接（`-l` 选项）
- 显示二维码（`-q` 选项，qrencode）
- 对无分享链接的协议（WireGuard/OpenVPN/IKEv2/IPsec），显示配置文件和下载路径

#### 验证结果

- 全部 55 个脚本 `bash -n` 语法检查通过（22 Debian + 22 CentOS + 11 show-config）
- README.md 已更新（增加 CentOS 支持说明和每协议的 CentOS 命令）

---

## 2026-03-27 多协议安装脚本 (初始)

### 完成内容

新增 11 种 VPN/代理协议的一键安装和卸载脚本：

| 协议 | 目录 | 底层实现 |
|------|------|---------|
| VLESS + WebSocket | `vless-ws/` | Xray-core + 自签证书 |
| Hysteria 2 | `hysteria2/` | hysteria 官方二进制 (QUIC) |
| TUIC v5 | `tuic-v5/` | tuic-server (QUIC) |
| Trojan | `trojan/` | Xray-core |
| Trojan-Go | `trojan-go/` | trojan-go 官方二进制 |
| Shadowsocks | `shadowsocks/` | Xray-core (chacha20-ietf-poly1305) |
| Shadowsocks 2022 | `shadowsocks-2022/` | Xray-core (2022-blake3-aes-128-gcm) |
| WireGuard | `wireguard/` | 内核模块 + wg-quick |
| OpenVPN | `openvpn/` | openvpn + Easy-RSA |
| IKEv2 | `ikev2/` | StrongSwan + EAP |
| IPsec/L2TP | `ipsec/` | StrongSwan + xl2tpd |

### 设计决策

- 需要 TLS 的协议默认使用自签证书
- 每个协议独立子目录，不互相干扰
- 统一 UI 风格 (Banner、颜色、进度)
