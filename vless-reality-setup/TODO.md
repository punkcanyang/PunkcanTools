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

### 功能增强

- [ ] 统一入口菜单脚本（交互式选择协议安装）
- [ ] 各协议增加 `health-check.sh`（参考根目录版本）
- [ ] 支持自定义端口（安装时通过参数或交互输入）
- [ ] 支持自定义密码/UUID（当前全部随机生成）
- [ ] ACME 证书自动申请（Let's Encrypt，需要域名）
- [ ] WireGuard 多客户端管理（add-client.sh / remove-client.sh）
- [ ] OpenVPN 多客户端管理（同上）

### 安全加固

- [ ] 自签证书协议提供域名 + ACME 选项
- [ ] 自动 fail2ban 集成
- [ ] SSH 端口保护提醒

### 测试

- [ ] Debian 12 实机测试
- [ ] Ubuntu 24.04 实机测试
- [ ] CentOS 9 / Rocky 9 实机测试
- [ ] 各协议客户端连通性测试

### 文档补充

- [ ] 各协议性能对比说明
- [ ] 常见问题 FAQ
- [ ] 防火墙/安全组配置指南
