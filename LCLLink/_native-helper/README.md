# Phase 2: Native Messaging Helper

> 此目录为 Phase 2 计划预留，当前版本不包含实际代码。

## 设计方向

### 目的
为 LCLLink Chrome 扩展提供本地 Helper 应用程序，通过 Chrome Native Messaging 协议与扩展通信，
实现浏览器沙箱内无法直接支持的代理协议。

### 计划支持的协议
- **Hysteria 2** - 基于 QUIC 的高速传输协议
- **TUIC v5** - 基于 QUIC 的代理协议
- **WireGuard** - 内核级 VPN 协议
- **OpenVPN** - 经典 VPN 协议
- **IKEv2 / IPsec** - 企业级 VPN 协议

### 技术方案
- 使用 **Go** 或 **Rust** 编写
- 在本地启动 SOCKS5/HTTP 代理端口
- 通过 Chrome Native Messaging 与扩展通信（控制命令）
- 扩展通过 `chrome.proxy` API 将浏览器流量指向本地代理端口

### 通信协议
```json
// 从扩展到 Helper 的消息格式
{
  "action": "connect",
  "config": {
    "protocol": "hysteria2",
    "server": "example.com",
    "port": 443,
    "...": "..."
  }
}

// 从 Helper 到扩展的响应格式
{
  "status": "connected",
  "localPort": 1080,
  "error": null
}
```
