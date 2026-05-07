# WORKLOG - vless-reality-setup

## 2026-05-07 AI 自动部署第一版范围与 P0 修补

### P1 AI command 合约

- `install.sh` 与 `install-centos.sh` 支援 `--port`、`--dest`、`--dest-port`、`--uuid`、`--short-id`、`--server-ip`、`--yes` / `--non-interactive`。
- 明确指定 `--port` 时，如果端口被占用会直接失败；未指定端口时保留旧行为，可从 443 自动切换到 8443。
- 安装完成后固定生成 `/usr/local/etc/xray/vless-reality.json` 与 `/usr/local/etc/xray/vless-reality.yaml`。
- `--json` / `--yaml` 会在安装完成后把对应合约输出到 stdout，方便 AI 通过 SSH 直接取回。
- JSON/YAML 合约包含协议、核心、server、port、uuid、Reality public key、short ID、分享链接、档案路径、服务状态与健康检查命令。
- 新增 `docs/ai-contract/`，包含 `vless-reality.schema.json`、`vless-reality.example.json`、`vless-reality.example.yaml` 与合约 README。
- 合约 README 明确要求回报日志、PR、issue、聊天内容时遮罩真实 `uuid`、`publicKey`、`shortId`、`shareLink` 与真实服务器地址。

### 已确认范围

- AI 自动部署第一版只支援根目录 VLESS + Reality，不要求全部协议都可由 AI 自动部署。
- Server 端与本地 command line client 第一版都采用 Xray-core。
- 本地 client 第一版平台仍锁定 macOS + Linux。
- 结构化输出已提供固定 JSON/YAML schema，同时保留 `vless://` 分享链接。
- 多线路备援第一版限定为多个 VLESS + Reality 节点，切换条件依序为手动优先级、连通性、延迟、失败次数。

### P0 修补方向

- 先修 VLESS + Reality 自动部署路径的 SSH 防锁、Xray 覆盖保护、敏感 client config 权限。
- 其他协议先保留给人类手动使用；后续若要纳入 AI 自动部署，再逐一套用同样合约。

### 本次落地

- `install.sh` 与 `install-centos.sh` 增加 `--replace` 参数；检测到既有 Xray 配置时，预设停止，避免无声覆盖其他协议。
- VLESS + Reality 安装完成后写入 `${XRAY_CONFIG_DIR}/vrs-protocol` 标记，用于辨识当前 Xray 配置归属。
- Debian/Ubuntu 路径在启用 UFW 前会保留 SSH 端口；iptables 路径也会写入 SSH allow 规则。
- CentOS/RHEL 路径会在 firewalld 或 iptables 中保留 SSH 端口。
- VLESS 分享链接、完整 client config、二维码图片改为 `chmod 600`。

## 2026-05-06 AI 可读部署目标与本地 CLI Client 目标

### 记录内容

新增两个待拆解的产品目标到 `TODO.md`：

1. AI 可读与可执行的远端服务器设定流程
   - README 后续要补成 AI 能读懂并执行的操作合约。
   - 目标流程是：选择协议、对远端服务器完成安装、取回设定资料、执行健康检查、交给本地连线流程。
   - 首要协议锁定根目录 VLESS + Reality。
   - 待规划非互动安装模式与机器可读输出，避免 AI 执行时卡在交互输入或只能解析人类说明。

2. 本地 Command Line Client 规划与实现
   - 远端安装完成后，本地需要能安装 Client 并使用取回的设定资料完成连线。
   - 首要支援 VLESS + Reality。
   - Client 需要规划多线路备援、自动检查连线、自动连线、断线重连、状态查询、日志查看、设定汇入/汇出。
   - 本地核心第一版已确定采用 Xray-core，后续需要规划安装、设定档生成、服务管理、状态检查与日志路径。

### 已确认决策

- AI 操作远端服务器时，SSH root 与 sudo 使用者两种模式都要支援。
- README 的 AI 操作合约要同时提供人类可读 Markdown 与固定 JSON/YAML schema。
- 本地 Client 第一版优先支援 macOS + Linux。
- 本地连线核心第一版采用 Xray-core。
- 多线路备援切换条件依序为：手动优先级、连通性、延迟、失败次数。

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
