# IP-Scan 网络扫描工具

使用 Tauri 2.0 开发的跨平台网络 IP 扫描桌面应用。

## 功能

- 🔍 扫描网络区块（CIDR 格式，如 192.168.1.0/24）
- 📡 ICMP ping 检测活跃主机
- 🔌 端口扫描（24 个常用端口）
- 💻 操作系统推测（基于 TTL）
- 🖥️ 设备类型识别
- 📊 实时进度显示

## 快速开始

### 开发模式
```bash
npm install
npm run tauri dev
```

### 构建发布
```bash
npm run tauri build
```

## 技术栈

- **框架**: Tauri 2.0
- **后端**: Rust (pnet, surge-ping, tokio)
- **前端**: HTML + CSS + JavaScript

## 注意事项

- 部分扫描功能（如 ICMP ping）可能需要管理员权限
- 请仅在授权的网络环境中使用
