# VLESS + Reality 一键安装脚本

在 Debian/Ubuntu 或 CentOS/RHEL 系统上一键部署 VLESS + Reality 代理服务器。

## ✨ 功能

- 🚀 一键安装 Xray-core + VLESS + Reality
- 🔐 自动生成密钥和用户配置
- 🛡️ 自动配置防火墙
- ⚡ 启用 BBR 网络加速
- 📋 自动生成客户端配置、分享链接和二维码
- � 轻松查看配置: `xray-show-config` 命令
- �🔄 定时健康检查和自动重启

## 📋 系统要求

| 系统 | 支持版本 |
|------|----------|
| Debian | 11 / 12 / 13 |
| Ubuntu | 20.04 / 22.04 / 24.04 |
| CentOS |  8 / 9 |
| RHEL / Rocky / Alma |  8 / 9 |

- Root 权限
- 网络连接

## 🚀 快速开始

### Debian / Ubuntu 安装

```bash
# 下载脚本
git clone https://github.com/punkcanyang/PunkcanTools.git
cd PunkcanTools/vless-reality-setup

# 给予执行权限
chmod +x *.sh

# 执行安装
sudo bash install.sh
```

### CentOS / RHEL 安装

```bash
# 下载脚本
git clone https://github.com/punkcanyang/PunkcanTools.git
cd PunkcanTools/vless-reality-setup

# 给予执行权限
chmod +x *.sh

# 执行安装 (CentOS 版本)
sudo bash install-centos.sh
```

### 卸载

```bash
# Debian/Ubuntu
sudo bash uninstall.sh

# CentOS/RHEL
sudo bash uninstall-centos.sh
```

## 📄 配置说明

安装完成后，会自动生成以下配置文件:

| 文件 | 说明 |
|------|------|
| `/usr/local/etc/xray/vless-link.txt` | 🔗 纯 VLESS 分享链接（方便复制） |
| `/usr/local/etc/xray/vless-qrcode.png` | 📱 二维码图片（方便手机扫描） |
| `/usr/local/etc/xray/client-config.txt` | 📄 完整配置信息 |

配置包含:
- 服务器连接信息
- VLESS 分享链接 (可直接导入客户端)
- JSON 格式配置

## 📁 文件结构

```
vless-reality-setup/
├── install.sh          # Debian/Ubuntu 安装脚本
├── install-centos.sh   # CentOS/RHEL 安装脚本
├── uninstall.sh        # Debian/Ubuntu 卸载脚本
├── uninstall-centos.sh # CentOS/RHEL 卸载脚本
├── health-check.sh     # 健康检查脚本 (通用)
├── show-config.sh      # 配置查看脚本 (通用)
└── README.md           # 说明文档
```

安装后的快捷命令:
- `xray-show-config` - 查看配置和二维码
- `xray-uninstall.sh` - 卸载脚本

## 🔧 常用命令

```bash
# 查看配置和二维码
xray-show-config

# 仅查看 VLESS 分享链接
xray-show-config --link

# 仅显示终端二维码
xray-show-config --qr

# 查看配置文件路径
xray-show-config --path

# 查看服务状态
systemctl status xray

# 查看实时日志
journalctl -u xray -f

# 手动重启服务
systemctl restart xray

# 复制链接到本地 (scp)
scp root@服务器IP:/usr/local/etc/xray/vless-link.txt ./
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

### 手动生成客户端配置

如果安装过程中断或需要重新生成客户端配置，按以下步骤操作：

**1. 查看服务器配置获取 UUID 和 Short ID：**
```bash
cat /usr/local/etc/xray/config.json | jq '.inbounds[0].settings.clients[0].id'
cat /usr/local/etc/xray/config.json | jq '.inbounds[0].streamSettings.realitySettings.shortIds[0]'
```

**2. 从 Private Key 获取 Public Key：**
```bash
# 先查看 Private Key
PRIVATE_KEY=$(cat /usr/local/etc/xray/config.json | jq -r '.inbounds[0].streamSettings.realitySettings.privateKey')
echo "Private Key: $PRIVATE_KEY"

# 获取 Public Key
/usr/local/bin/xray x25519 -i "$PRIVATE_KEY"
# 输出中的 Password 就是 Public Key
```

**3. 生成 VLESS 分享链接：**
```
vless://UUID@服务器IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp&headerType=none#VLESS-Reality
```

**4. 导入客户端：**
- **Shadowrocket**: 复制链接 → 打开 App → 点击 "+" → 从剪贴板导入
- **V2rayN**: 复制链接 → 服务器 → 从剪贴板导入
- **Clash**: 需要转换为 Clash 格式配置

## 📜 许可证

MIT License
