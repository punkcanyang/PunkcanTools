# WORKLOG - vless-reality-setup

## 2026-05-07 P3.5 分享链接 URI encoding

### 本次落地

- 新增 `lib/uri-encode.sh`，提供纯 Bash `uri_encode_component`，不依赖 `python3`、`jq` 或其他外部工具。
- Hysteria2 Debian/Ubuntu 与 CentOS/RHEL 分享链接改用内建 URI encoder 处理密码。
- TUIC v5 Debian/Ubuntu 与 CentOS/RHEL 分享链接改用内建 URI encoder 处理密码，修掉 base64 密码含 `/`、`+`、`=` 时可能破坏 `tuic://` userinfo 的问题。
- Trojan Debian/Ubuntu 与 CentOS/RHEL 分享链接改用内建 URI encoder 处理密码。
- Trojan-Go Debian/Ubuntu 与 CentOS/RHEL 分享链接改用内建 URI encoder 处理密码与 WebSocket path。
- README、README.en 与 TODO 已同步。

### 验证

- `bash -n lib/uri-encode.sh hysteria2/install.sh hysteria2/install-centos.sh tuic-v5/install.sh tuic-v5/install-centos.sh trojan/install.sh trojan/install-centos.sh trojan-go/install.sh trojan-go/install-centos.sh`
- `bash -c 'source lib/uri-encode.sh; uri_encode_component "a/b+c=d@x y"'`，输出 `a%2Fb%2Bc%3Dd%40x%20y`。
- `rg -n "python3|urllib|quote\\(|tuic://\\$\\{UUID\\}:\\$\\{PASSWORD\\}|path=\\$\\{WS_PATH\\}" hysteria2/install*.sh tuic-v5/install*.sh trojan/install*.sh trojan-go/install*.sh`，确认没有残留旧 encoding 路径。
- `bash -n *.sh */*.sh`
- `bash client/test-vrs-client.sh`
- `git diff --check`
- `shellcheck` 本机未安装，未执行。

## 2026-05-07 P3.4 VPN 依赖补齐

### 本次落地

- IKEv2 Debian/Ubuntu 版补齐 `curl`、`openssl`、`iproute2`、`iptables`、`procps`。
- IPsec/L2TP Debian/Ubuntu 版补齐 `curl`、`openssl`、`iproute2`、`iptables`、`procps`。
- WireGuard Debian/Ubuntu 版补齐 `curl`、`iproute2`、`iptables`、`procps`。
- OpenVPN Debian/Ubuntu 版补齐 `curl`、`iproute2`、`procps`，并在写入 `/etc/network/if-pre-up.d/iptables` 前建立目录。
- IKEv2、IPsec/L2TP、WireGuard、OpenVPN 的 CentOS/RHEL 版补齐 `curl`、`openssl`、`iproute`、`iptables`、`procps-ng` 等实际使用命令所需套件。
- README、README.en 与 TODO 已同步。

### 验证

- `bash -n ikev2/install.sh ikev2/install-centos.sh ipsec/install.sh ipsec/install-centos.sh wireguard/install.sh wireguard/install-centos.sh openvpn/install.sh openvpn/install-centos.sh`
- `bash -n *.sh */*.sh`
- `bash client/test-vrs-client.sh`
- `git diff --check`
- `shellcheck` 本机未安装，未执行。

## 2026-05-07 P3.3 敏感输出权限推广

### 本次落地

- 将敏感输出 `chmod 600` 推广到其他协议安装脚本。
- Xray-backed 协议会收紧 `/usr/local/etc/xray/config.json`、分享链接与 `client-config.txt`。
- Hysteria2、TUIC v5、Trojan-Go 会收紧服务端 config、分享链接与 `client-config.txt`。
- WireGuard 会收紧 `wg0.conf`、`clients/client1.conf`、`client-config.txt`，并将 client 目录设为 `700`。
- OpenVPN 会收紧 `tls-auth.key`、`.ovpn`、`client-config.txt`，并将 client 目录设为 `700`。
- IKEv2/IPsec 会收紧含密码、PSK 或 EAP 凭证的 client config；既有 private key / secrets 权限保持 `600`。
- README、README.en 与 TODO 已同步。

### 验证

- `bash -n *.sh */*.sh`
- `bash client/test-vrs-client.sh`
- `git diff --check`
- `shellcheck` 本机未安装，未执行。

## 2026-05-07 P3.2 防火墙 SSH 防锁推广

### 本次落地

- 新增 `lib/firewall-ssh-guard.sh`，集中检测 SSH 端口并提供 UFW、firewalld、iptables 的 SSH 放行函数。
- SSH 端口检测来源包含当前 `SSH_CONNECTION`、`sshd -T`、`/etc/ssh/sshd_config`，并保留默认 `22/tcp`。
- 将 SSH 防锁规则推广到会修改防火墙的协议安装脚本：
  - `vless-ws/`
  - `hysteria2/`
  - `tuic-v5/`
  - `trojan/`
  - `trojan-go/`
  - `shadowsocks/`
  - `shadowsocks-2022/`
  - `wireguard/`
  - `openvpn/`
  - `ikev2/`
  - `ipsec/`
- OpenVPN 的 iptables 持久化流程会在 `iptables-save` 前先加入 SSH allow rule，避免规则保存后漏掉 SSH。
- README、README.en 与 TODO 已同步。

### 验证

- `bash -n lib/firewall-ssh-guard.sh`
- `bash -n *.sh */*.sh`
- `bash client/test-vrs-client.sh`
- `bash -c 'source lib/firewall-ssh-guard.sh; detect_ssh_ports'`，当前开发机输出 `22`。
- `git diff --check`
- `shellcheck` 本机未安装，未执行。

## 2026-05-07 P3.1 Xray-backed 协议覆盖与卸载保护

### 本次落地

- 新增 `lib/xray-protocol-guard.sh`，集中处理 Xray 配置归属标记、`--replace` 与 `--force` 参数。
- `vless-ws/`、`trojan/`、`shadowsocks/`、`shadowsocks-2022/` 的 Debian/Ubuntu 与 CentOS/RHEL install 脚本都会在写入 `/usr/local/etc/xray/config.json` 前检查 `/usr/local/etc/xray/vrs-protocol`。
- 上述协议安装完成后会写入对应协议标记，避免后续安装无声覆盖其他协议。
- 根目录 VLESS + Reality 与上述 Xray-backed 协议的 uninstall 脚本都会先检查归属标记；归属不一致或缺少标记时停止，确认强制移除时才允许 `--force`。
- README、README.en、docs/ai-contract 与 TODO 已同步说明目前仍不是多 Xray 协议共存模式，而是先防止覆盖与误删。

### 验证

- `bash -n lib/xray-protocol-guard.sh`
- `bash -n` 覆盖所有本次修改的 Xray-backed install/uninstall 脚本。
- `bash -n *.sh */*.sh`
- `bash client/test-vrs-client.sh`
- `git diff --check`
- `bash vless-ws/install.sh --help`
- `bash shadowsocks/install-centos.sh --help`
- `bash uninstall.sh --help`
- `bash trojan/uninstall-centos.sh --help`
- `bash shadowsocks-2022/uninstall.sh --help`
- `shellcheck` 本机未安装，未执行。

## 2026-05-07 P2.7 本地 CLI 离线 regression test

### 本次落地

- 新增 `client/test-vrs-client.sh`。
- 测试脚本使用 `/private/tmp/vrs-client-regression-$$` 作为临时 `VRS_CLIENT_HOME`，结束后清理。
- 测试覆盖：
  - `client/vrs-client.sh` 语法检查。
  - 匯入 `alpha` / `beta` 两条 profile。
  - `profiles/index.json` schema、current、priority 与 profile 资料。
  - 生成的 Xray client config 是否为合法 JSON，且包含 SOCKS/HTTP inbound、VLESS outbound、Reality security。
  - `list --sorted` 输出包含两条 profile。
  - `check --name beta` 在未运行时会失败，并写入 `offline` 与 `failureCount=1`。
  - `auto-use` 在没有本地 `xray` 时会逐条失败，并写回 offline/failureCount。
  - `watch --once` 会先检查 current，再 fallback 到 `auto-use`。
  - 无效 interval、缺少 `service` / `watch-service` 子命令会失败。
  - `config` 会显示 watcher log 路径。

### 验证

- `bash client/test-vrs-client.sh`

## 2026-05-07 P2.5 背景健康检查与断线重连 watcher

### 本次落地

- `client/vrs-client.sh` 新增 `watch [--interval SEC] [--url URL] [--once]`。
- `watch --once` 会检查 current profile；如果 current 不可用，会调用 `auto-use` 自动尝试候选线路。
- `watch` 前景循环默认每 60 秒检查一次，可通过 `--interval` 调整，范围为 5-86400 秒。
- `auto-use` 在尝试候选线路前会停止该候选的既有 runtime，再重新启动并检查，用于断线重连。
- 新增 `watch-service install|uninstall|start|stop|restart|status`，提供使用者层级背景 watcher。
- macOS watcher 使用 `~/Library/LaunchAgents/io.punkcan.vrs.watch.plist`。
- Linux watcher 使用 `systemd --user` 的 `vrs-client-watch.service`。
- watcher 日志写入 `$VRS_CLIENT_HOME/logs/watcher.log`；`logs` 与 `config` 会显示 watcher log。

### 尚未处理

- 当前机器没有本地 `xray`，所以只验证失败路径；真实启动成功、SOCKS 检查成功、watcher 自动恢复需要装好 Xray 后补测。
- 还没把 watcher 服务实际安装到本机 launchd/systemd，避免未经确认改动本机常驻服务。

### 验证

- `bash -n client/vrs-client.sh`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p25 bash client/vrs-client.sh import docs/ai-contract/vless-reality.example.json --name alpha --priority 10`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p25 bash client/vrs-client.sh import docs/ai-contract/vless-reality.example.json --name beta --priority 20`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p25 bash client/vrs-client.sh watch --once --interval 5`，当前机器无 `xray`，预期检查 current 失败后调用 `auto-use`，最终 exit 1。
- `bash client/vrs-client.sh watch --interval 1 --once`，预期回报 interval 范围错误。
- `bash client/vrs-client.sh watch-service`，预期回报缺少子命令。
- `node -e` 读取 `/private/tmp/vrs-client-test-p25/profiles/index.json`，确认 alpha/beta 写为 `offline` 且 failure count 已累加。
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p25-final bash client/vrs-client.sh config`，确认会显示 watcher log 路径。
- `node -e` 读取 `/private/tmp/vrs-client-test-p25-final/xray/alpha.config.json`，确认 Xray config 仍是合法 JSON。

## 2026-05-07 P2.4 自动选线 auto-use

### 本次落地

- `client/vrs-client.sh` 新增 `auto-use [--url URL]`。
- 新增 `list --sorted`，显示自动选线候选顺序。
- 自动候选只包含 `enabled=true` 的 profile。
- 候选排序依序使用：`priority` 小到大、`lastStatus` 排序为 `online` 优先于 `unknown` 优先于 `offline`、`latencyMs` 小到大、`failureCount` 小到大、profile 名称稳定排序。
- `auto-use` 会逐条调用 `use --name <profile>`，每条线路都会执行启动与连线检查；第一条成功的线路会成为 current。
- 单条线路失败不会中断整个 `auto-use`，会继续试下一条；全部失败时 exit 1。

### 尚未处理

- 当前机器没有本地 `xray`，所以 P2.4 验证只覆盖失败路径；真实启动成功与 SOCKS 连线成功需要装好 Xray 后补测。
- 还没有背景 watcher 做定时健康检查和断线自动重连。

### 验证

- `bash -n client/vrs-client.sh`
- `bash -n *.sh */*.sh`
- `bash client/vrs-client.sh help`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p24 bash client/vrs-client.sh import docs/ai-contract/vless-reality.example.json --name alpha --priority 10`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p24 bash client/vrs-client.sh import docs/ai-contract/vless-reality.example.json --name beta --priority 20`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p24 bash client/vrs-client.sh list --sorted`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p24 bash client/vrs-client.sh auto-use`，当前机器无 `xray`，预期逐条尝试 alpha 与 beta，全部失败后 exit 1。
- `node -e` 读取 `/private/tmp/vrs-client-test-p24/profiles/index.json`，确认 `current=beta`，alpha 与 beta 都写为 `offline` 且 failure count 已累加。
- `node -e` 读取 `/private/tmp/vrs-client-test-p24-final/xray/alpha.config.json`，确认 Xray config 仍是合法 JSON。
- `git diff --check`

## 2026-05-07 P2.3 多线路资料模型与手动切换

### 本次落地

- 新增 `$VRS_CLIENT_HOME/profiles/index.json`，schema 为 `vrs.client.profiles.v1`。
- index 记录 `current` 与每个 profile 的 `priority`、`enabled`、`lastStatus`、`latencyMs`、`failureCount`、`lastCheckedAt`、`lastUsedAt`、`profilePath`、`xrayConfigPath`。
- `import` 新增 `--priority N`，数值越小越优先；匯入后会写入 index。
- `list` 改为从 index 输出 priority、enabled、status、latency、failure count、runtime，并用 `*` 标示 current。
- 新增 `current` 命令，显示当前 profile 并接着显示状态。
- 新增 `use --name NAME [--url URL]`：选择线路、停止旧线路、写入 current、启动新线路，然后执行连线检查。
- `check` 成功会写 `lastStatus=online`、`latencyMs` 并重置 `failureCount`；失败会写 `lastStatus=offline` 并累加 `failureCount`。
- index 写入新增轻量 lock，避免多个 CLI 进程同时匯入 profile 时覆盖彼此。

### 尚未处理

- 还没有自动选择最佳线路；下一步才会按「手动优先级、连通性、延迟、失败次数」排序并切换。
- 当前机器没有本地 `xray`，所以 `use` 的成功启动与真实连线检查尚未实测；已验证缺少 Xray 时会把线路记为 offline 并累加失败次数。

### 验证

- `bash -n client/vrs-client.sh`
- `bash -n *.sh */*.sh`
- `bash client/vrs-client.sh help`
- 并发执行两次 `import` 到同一个 `VRS_CLIENT_HOME`，确认 index lock 后 `alpha` / `beta` 都保留。
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p23-lock bash client/vrs-client.sh list`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p23-lock bash client/vrs-client.sh current`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p23-lock bash client/vrs-client.sh check --name beta`，预期因为未运行而写入 `offline` 与 `failureCount=1`。
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p23-lock bash client/vrs-client.sh use --name beta`，当前机器无 `xray`，预期选择 beta 后写入 `offline` 并累加失败次数。
- `node -e` 读取 `/private/tmp/vrs-client-test-p23-final/profiles/index.json` 与 `alpha.config.json`，确认 index 与 Xray config 都是合法 JSON。
- `git diff --check`
- `shellcheck` 本机未安装，未执行。

## 2026-05-07 P2.2 本地 Client 服务化入口

### 本次落地

- `client/vrs-client.sh` 新增 `service install|uninstall|start|stop|restart|status`。
- macOS 使用使用者层级 launchd plist：`~/Library/LaunchAgents/io.punkcan.vrs.<name>.plist`。
- Linux 使用 systemd user unit：`$XDG_CONFIG_HOME/systemd/user/vrs-client-<name>.service` 或 `$HOME/.config/systemd/user/vrs-client-<name>.service`。
- 新增内部 `run-foreground` 命令，service 模式会以前景执行 Xray，让 launchd/systemd 负责进程管理与重启。
- `status` / `list` 会辨识 service 运行状态；若 profile 由 service 管理，普通 `stop` 会提示改用 `service stop`。

### 尚未处理

- 还没有在真实 macOS launchd / Linux systemd 环境执行安装服务测试。
- 还没有多线路自动排序与切换。
- 还没有独立 watcher 负责连通性、延迟、失败次数统计。

### 验证

- `bash -n client/vrs-client.sh`
- `bash -n *.sh */*.sh`
- `bash client/vrs-client.sh help`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p22 bash client/vrs-client.sh import docs/ai-contract/vless-reality.example.json --name p22-test`
- `node -e "JSON.parse(require('fs').readFileSync('/private/tmp/vrs-client-test-p22/xray/p22-test.config.json','utf8')); console.log('ok')"`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p22 bash client/vrs-client.sh status --name p22-test`
- `bash client/vrs-client.sh service`，预期以 exit 1 回报缺少 service 子命令。
- `git diff --check`

## 2026-05-07 P2.1 本地 Xray-core 安装入口

### 本次落地

- `client/vrs-client.sh` 新增 `install-core` 命令。
- 若本地已存在 `xray` 或 `XRAY_BIN` 指定的可执行档，`install-core` 会直接转为 `check-core` 并显示版本。
- macOS 自动安装优先使用 Homebrew：`brew install xray`。
- Linux 自动安装优先使用 Homebrew；如果没有 Homebrew，则下载 XTLS 官方 `Xray-install` 脚本并执行 `install --without-logfiles --no-update-service`。
- `check-core` 在当前开发机上验证为正确回报「找不到本地 Xray-core」，未误判成已安装。

### 尚未处理

- 还没做 macOS launchd / Linux systemd 的 VRS client profile 服务化。
- 还没做 `install-core --dry-run` 或安装前确认提示；当前行为是使用者显式执行 `install-core` 才安装。

### 验证

- `bash -n client/vrs-client.sh`
- `bash -n *.sh */*.sh`
- `bash client/vrs-client.sh help`
- `bash client/vrs-client.sh check-core`，当前机器没有 `xray`，预期以 exit 1 回报缺少 core。
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test-p21 bash client/vrs-client.sh import docs/ai-contract/vless-reality.example.json --name p21-test`
- `node -e "JSON.parse(require('fs').readFileSync('/private/tmp/vrs-client-test-p21/xray/p21-test.config.json','utf8')); console.log('ok')"`
- 确认 `/private/tmp/vrs-client-test-p21/profiles/p21-test.json` 与 `/private/tmp/vrs-client-test-p21/xray/p21-test.config.json` 为 `-rw-------`。
- `git diff --check`

## 2026-05-07 P2 本地 CLI Client 第一版

### 本次落地

- 新增 `client/vrs-client.sh`，第一版只支援匯入 VLESS + Reality 的 `vless-reality.json`。
- 本地状态目录默认使用 `$HOME/.vrs/client`，可通过 `VRS_CLIENT_HOME` 覆盖。
- 本地 profile 路径为 `profiles/<name>.json`，Xray client config 路径为 `xray/<name>.config.json`。
- 默认提供本地 SOCKS `127.0.0.1:10808` 与 HTTP `127.0.0.1:10809` inbound，可通过 `VRS_SOCKS_PORT` / `VRS_HTTP_PORT` 覆盖。
- 支援命令：`import`、`start`、`stop`、`restart`、`status`、`check`、`logs`、`list`、`export`、`config`、`check-core`。
- `import` 会验证 `schemaVersion=vrs.vless-reality.v1`、`protocol=vless-reality`、`core=xray-core`、`transport=tcp`、`security=reality`。
- 本地 profile、Xray config 与 log/pid 文件会尽量设为 `chmod 600`，状态目录设为 `chmod 700`。

### 尚未处理

- 还没有自动安装本地 Xray-core；当前只做侦测，使用者需先安装 `xray` 或设定 `XRAY_BIN=/path/to/xray`。
- 还没有 macOS launchd / Linux systemd 整合。
- 多线路目前只有 profile 命名与列表基础，还没有自动排序与切换。
- 断线重连与背景健康检查留到后续 P2.x。

### 验证

- `bash -n client/vrs-client.sh`
- `bash -n *.sh */*.sh`
- `bash client/vrs-client.sh help`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test bash client/vrs-client.sh import docs/ai-contract/vless-reality.example.json --name test`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test bash client/vrs-client.sh status --name test`
- `VRS_CLIENT_HOME=/private/tmp/vrs-client-test bash client/vrs-client.sh list`
- `node -e "JSON.parse(require('fs').readFileSync('/private/tmp/vrs-client-test/xray/test.config.json','utf8')); console.log('ok')"`
- 确认 `/private/tmp/vrs-client-test/profiles/test.json` 与 `/private/tmp/vrs-client-test/xray/test.config.json` 为 `-rw-------`。
- `git diff --check`
- `shellcheck` 本机未安装，未执行。

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
