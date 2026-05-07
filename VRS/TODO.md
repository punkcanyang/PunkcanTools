# TODO - 多协议 VPN/代理一键安装脚本集

## ✅ 已完成

### 协议脚本开发

每个协议包含 5 个脚本：`install.sh` / `install-centos.sh` / `uninstall.sh` / `uninstall-centos.sh` / `show-config.sh`

- [x] VLESS + Reality（根目录，原始版本）
- [x] VLESS + WebSocket + TLS (`vless-ws/`)
- [x] Hysteria 2 (`hysteria2/`)
- [x] TUIC v5 (`tuic-v5/`)
- [x] Trojan (`trojan/`)
- [x] Trojan-Go (`trojan-go/`)
- [x] Shadowsocks AEAD (`shadowsocks/`)
- [x] Shadowsocks 2022 (`shadowsocks-2022/`)
- [x] WireGuard (`wireguard/`)
- [x] OpenVPN (`openvpn/`)
- [x] IKEv2 / StrongSwan (`ikev2/`)
- [x] IPsec/L2TP (`ipsec/`)

### 文档

- [x] README.md（含所有协议说明、Debian + CentOS 安装命令）
- [x] WORKLOG.md（工作日报）
- [x] 全部 55 个子目录脚本 `bash -n` 语法检查通过

---

## 🔲 待办 / 可改进

### 待拆解的产品目标

- [ ] AI 可读与可执行的远端服务器设定流程
  - 目标：让 AI 读取 README 后，能知道如何对远端服务器完成协议安装、取回设定资料，并把资料交给本地连线流程使用。
  - 第一版 AI 自动部署只支援根目录 VLESS + Reality，不要求全部协议都可由 AI 自动部署。
  - 第一版 server 端与本地 command line client 都采用 Xray-core，先打通同一套设定资料与连线核心。
  - 其他协议第一阶段保留给人类手动使用；等 VLESS + Reality 的 command 流程稳定后，再评估是否扩展。
  - README 需要补成可执行操作合约：系统要求、权限要求、远端连线方式、协议选择、安装命令、健康检查、设定资料路径、输出格式、错误处理、敏感资讯遮罩规则。
  - README 需要同时保留人类可读 Markdown，并提供固定 JSON/YAML schema，供 AI 和自动化流程稳定解析。
  - 远端操作权限需要同时支援 SSH root 与 sudo 使用者两种模式。
  - 脚本需要规划非互动模式：通过参数或环境变数传入协议、端口、UUID/密码、域名、Reality `serverNames` 等设定，避免 AI 卡在交互输入。
  - 需要规划结构化输出：安装成功后输出机器可读结果，例如 JSON，包含协议、服务器位址、端口、客户端设定档路径、分享链接、健康检查结果与服务状态。
  - 首要协议：根目录 VLESS + Reality。后续再把相同合约推广到其他协议目录。

- [ ] 本地 Command Line Client 规划与实现
  - 目标：远端设定完成后，本地也能安装 Client，读取取回的设定资料并完成连线。
  - 首要支援 VLESS + Reality 连线，先规划可复用的命令列 Client 架构，再扩展到其他可用协议。
  - 第一版平台范围：macOS + Linux。
  - 第一版本地核心：Xray-core。
  - Client 条件：多线路备援、自动检查连线、自动连线、断线重连、状态查询、日志查看、设定汇入/汇出。
  - 多线路备援切换优先顺序：手动优先级、连通性、延迟、失败次数。
  - 优先把目前可命令列化的能力安排进去：安装本地核心、写入本地设定档、启动/停止/重启、健康检查、切换线路、列出节点、清理设定。
  - 需要规划 Xray-core 的本地安装、设定档生成、系统服务管理、状态检查与日志路径。
  - [x] P2 第一版新增 `client/vrs-client.sh`，支援 macOS + Linux 的本地命令列操作。
  - [x] 支援从 `vless-reality.json` 匯入 profile，并生成本地 Xray client config。
  - [x] 支援 `start` / `stop` / `restart` / `status` / `check` / `logs` / `list` / `export` / `config` / `check-core`。
  - [x] 本地 profile 与 Xray config 使用 `chmod 600`。
  - [x] 自动安装本地 Xray-core：macOS/Linux Homebrew 优先；Linux 无 Homebrew 时使用 XTLS 官方安装脚本。
  - [x] 系统服务整合第一版：macOS launchd 使用者服务与 Linux systemd user service。
  - [x] 多线路资料模型第一版：`profiles/index.json` 记录 priority、current、连通性、延迟、失败次数。
  - [x] 手动切换第一版：`use --name NAME` 会选择线路、启动连线并执行连线检查。
  - [x] `check` 成功/失败会写回 `lastStatus`、`latencyMs`、`failureCount`。
  - [x] 多线路自动排序与切换第一版：`auto-use` 会依 priority、连通性、延迟、失败次数尝试候选线路。
  - [x] 断线自动重连与背景健康检查第一版：`watch` / `watch-service`。
  - [x] 离线 regression test：`client/test-vrs-client.sh` 覆盖本地 CLI 状态机与失败路径。
  - [ ] 真实 Xray-core 环境连线测试：启动成功、SOCKS 检查成功、watcher 自动恢复。

### 功能增强

- [x] VLESS + Reality 支持 AI command 参数：`--port` / `--dest` / `--dest-port` / `--uuid` / `--short-id` / `--server-ip` / `--yes`
- [x] VLESS + Reality 生成 `/usr/local/etc/xray/vless-reality.json` 与 `/usr/local/etc/xray/vless-reality.yaml`
- [x] VLESS + Reality 支持安装完成后通过 `--json` / `--yaml` 输出机器可读合约
- [x] 建立 `docs/ai-contract/`，包含 VLESS + Reality JSON Schema、JSON 范例、YAML 范例与敏感资讯遮罩规则
- [x] Xray-backed 协议增加共享 Xray 配置归属保护，安装时避免无声覆盖其他协议
- [x] Xray-backed 卸载脚本增加归属检查，避免误删其他协议使用中的 Xray
- [x] 新增本地 CLI Client 第一版：`client/vrs-client.sh`
- [x] 本地 CLI Client 支援 `install-core` 安装 Xray-core
- [x] 本地 CLI Client 支援使用者层级 `service` 管理
- [x] 本地 CLI Client 支援多 profile index、current route、手动切换与检查回写
- [x] 本地 CLI Client 支援 `auto-use` 自动选线
- [x] 本地 CLI Client 支援 `watch` / `watch-service` 健康检查与自动重连
- [x] 本地 CLI Client 离线 regression test：`client/test-vrs-client.sh`
- [x] IKEv2/IPsec/WireGuard/OpenVPN 补齐极简系统缺少的实际命令依赖
- [x] Hysteria2/TUIC/Trojan/Trojan-Go 分享链接使用内建 URI encoding，不再依赖 `python3`
- [ ] 统一入口菜单脚本（交互式选择协议安装）
- [ ] 各协议增加 `health-check.sh`（参考根目录版本）
- [ ] 支持自定义端口（安装时通过参数或交互输入）
- [ ] 支持自定义密码/UUID（当前全部随机生成）
- [ ] ACME 证书自动申请（Let's Encrypt，需要域名）
- [ ] WireGuard 多客户端管理（add-client.sh / remove-client.sh）
- [ ] OpenVPN 多客户端管理（同上）

### 安全加固

- [x] VLESS + Reality 自动部署前先保护 SSH 防火墙规则，避免启用 UFW/firewalld/iptables 后远端失联
- [x] VLESS + Reality 增加 Xray 覆盖保护，避免无声覆盖既有 `/usr/local/etc/xray/config.json`
- [x] VLESS + Reality 客户端设定档、分享链接、二维码等敏感输出使用 `chmod 600`
- [x] 将覆盖保护推广到 VLESS WS、Trojan、Shadowsocks、SS-2022 的 Debian/Ubuntu 与 CentOS/RHEL 安装脚本
- [x] 将卸载保护推广到 VLESS Reality、VLESS WS、Trojan、Shadowsocks、SS-2022 的 Debian/Ubuntu 与 CentOS/RHEL 卸载脚本
- [x] 将 SSH 防锁规则推广到会修改防火墙的协议安装脚本
- [x] 将敏感输出权限规则推广到其他协议脚本
- [ ] 自签证书协议提供域名 + ACME 选项
- [ ] 自动 fail2ban 集成
- [ ] SSH 端口保护提醒

### 测试

- [x] 本地 CLI 离线 regression test
- [ ] Debian 12 实机测试
- [ ] Ubuntu 24.04 实机测试
- [ ] CentOS 9 / Rocky 9 实机测试
- [ ] 各协议客户端连通性测试

### 文档补充

- [ ] 各协议性能对比说明
- [ ] 常见问题 FAQ
- [ ] 防火墙/安全组配置指南
