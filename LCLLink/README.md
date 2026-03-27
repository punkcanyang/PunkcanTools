# LCLLink

> 多协议代理客户端 Chrome 扩展

## 功能特性

### Phase 1（当前版本）
基于浏览器 WebSocket 传输的代理协议支持：

| 协议 | 状态 | 传输方式 |
|------|------|----------|
| VLESS | ✅ 已实现 | WebSocket |
| Trojan | ✅ 已实现 | WebSocket |
| Shadowsocks | ✅ 已实现 | WebSocket |
| SS-2022 | ✅ 已实现 | WebSocket |

### Phase 2（计划中）
通过 Native Messaging Helper 支持系统级协议：

- Hysteria 2 (QUIC)
- TUIC v5 (QUIC)
- WireGuard (TUN)
- OpenVPN (TUN/TAP)
- IKEv2 / IPsec

## 技术栈

- **TypeScript** + **Vite** 构建
- **Chrome Extension Manifest V3**
- **Web Crypto API** (AEAD 加密)
- **chrome.proxy API** (代理管理)

## 开发

```bash
# 安装依赖
npm install

# 开发模式（监听文件变化）
npm run dev

# 构建生产版本
npm run build
```

## 加载扩展

1. 运行 `npm run build`
2. 打开 Chrome，进入 `chrome://extensions/`
3. 启用「开发者模式」
4. 点击「加载已解压的扩展程序」
5. 选择项目下的 `dist/` 目录

## 项目结构

```
src/
├── background/        # Service Worker
├── popup/             # 弹出窗口 UI
├── options/           # 设置页面
├── core/              # 核心模块（协议接口、代理管理、连接管理）
├── protocols/         # 协议实现（vless/trojan/shadowsocks）
└── utils/             # 工具函数（二进制处理、UUID、日志）
```

## 许可证

MIT
