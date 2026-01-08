# VLESS + Reality 一键安装脚本

在 Debian 12 环境上一键部署 VLESS + Reality 代理服务器。

## ✨ 功能

- 🚀 一键安装 Xray-core + VLESS + Reality
- 🔐 自动生成密钥和用户配置
- 🛡️ 自动配置防火墙
- ⚡ 启用 BBR 网络加速
- 📋 自动生成客户端配置和分享链接
- 🔄 定时健康检查和自动重启

## 📋 系统要求

- Debian 12 (其他 Debian/Ubuntu 系统可能兼容)
- Root 权限
- 网络连接

## 🚀 快速开始

### 安装

```bash
# 下载脚本
git clone https://github.com/yourusername/vless-reality-setup.git
cd vless-reality-setup

# 给予执行权限
chmod +x install.sh health-check.sh uninstall.sh

# 执行安装
sudo bash install.sh
```

### 卸载

```bash
sudo bash uninstall.sh
```

## 📄 配置说明

安装完成后，客户端配置会自动保存到:

```
/usr/local/etc/xray/client-config.txt
```

配置包含:
- 服务器连接信息
- VLESS 分享链接 (可直接导入客户端)
- JSON 格式配置

## 📁 文件结构

```
vless-reality-setup/
├── install.sh          # 主安装脚本
├── uninstall.sh        # 卸载脚本
├── health-check.sh     # 健康检查脚本
└── README.md           # 说明文档
```

## 🔧 常用命令

```bash
# 查看服务状态
systemctl status xray

# 查看实时日志
journalctl -u xray -f

# 手动重启服务
systemctl restart xray

# 重新查看客户端配置
cat /usr/local/etc/xray/client-config.txt
```

## ⚙️ 默认配置

| 项目 | 默认值 |
|------|--------|
| 端口 | 443 |
| 协议 | VLESS + Reality |
| 伪装目标 | www.microsoft.com |
| Flow | xtls-rprx-vision |

## 🔒 安全说明

- Reality 协议提供更强的抗检测能力
- 使用 x25519 椭圆曲线加密
- 建议定期更新 Xray-core

## 📝 客户端推荐

| 平台 | 推荐客户端 |
|------|-----------|
| Windows | V2rayN, Clash Verge |
| macOS | V2rayU, ClashX Pro |
| iOS | Shadowrocket, Stash |
| Android | V2rayNG, Clash for Android |
| Linux | v2rayA, Clash |

## ❓ 常见问题

### 连接失败

1. 检查服务器防火墙是否开放 443 端口
2. 检查 Xray 服务是否正常运行: `systemctl status xray`
3. 检查客户端配置是否正确，特别是 Public Key 和 Short ID

### 速度慢

1. 确认 BBR 已启用: `sysctl net.ipv4.tcp_congestion_control`
2. 检查服务器带宽限制
3. 尝试更换客户端指纹 (fingerprint)

## 📜 许可证

MIT License
