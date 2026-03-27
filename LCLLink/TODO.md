# LCLLink 项目进度与 TODO

## 📋 当前进度摘要

LCLLink 是一个支持多协议的 Chrome 代理扩展，目前已完成 **Phase 1 (纯浏览器模式)** 和 **Phase 2 (Native Helper 模式)** 的核心代码开发。

- **Phase 1**: 支持 WebSocket 传输的 VLESS/Trojan/SS。
- **Phase 2**: 引入 Go 编写的 Native Helper，内嵌 xray-core，支持 Reality、XTLS-Vision 等原始 TCP 协议，并支持多浏览器 Profile 独立出口 IP。

---

## ✅ 已完成任务

### 1. 基础架构与 UI
- [x] Manifest V3 基础配置与扩展架构
- [x] 赛博科技风 UI (Popup + Options)
- [x] Vite 多入口构建与 CSS Code Splitting 修复
- [x] 统一日志系统 (Logger)

### 2. 协议与解析
- [x] 协议抽象层 (IProtocol / IConnection)
- [x] WebSocket 模式实现 (VLESS / Trojan / SS)
- [x] 增强型 URI 解析器 (支持标准及非标准 vless/trojan/ss 链接)

### 3. Native Helper (Phase 2 核心)
- [x] Go 项目初始化与依赖管理 (xray-core)
- [x] Native Messaging 协议实现 (stdin/stdout)
- [x] 多实例管理器 (Manager, 端口池 10001-10099)
- [x] HTTP API 接口 (127.0.0.1:19527)
- [x] **Embedded Web UI**: 嵌入式赛博风管理面板 (Go embed)
- [x] **HelperClient**: 扩展侧自动启动与控制逻辑
- [x] **双模式 Service Worker**: Helper 启动成功走 Helper，失败自动回退到 WS 直连

---

## 🚀 待办任务 (TODO)

### 1. 验证与测试 (高优先级)
- [ ] **macOS 安装脚本验证**: 测试 `install.sh` 是否能正确注册 NM Host。
- [ ] **端到端联动测试**: 验证从扩展点击「连接」，Helper 是否自动启动并建立 VLESS+Reality 连接。
- [ ] **多 Profile 测试**: 验证两个 Chrome 实例是否能分别通过 Helper 的不同端口走不同出口 IP。

### 2. Phase 2 协议扩展
- [ ] **Hysteria 2**: Helper 侧集成支持。
- [ ] **TUIC v5**: Helper 侧集成支持。
- [ ] **WireGuard**: Helper 侧集成支持。

### 3. 功能完善
- [ ] **PAC 分流支持**: 完善 `ProxyManager` 的分流规则配置 UI。
- [ ] **Helper 自动更新**: 扩展侧检测 Helper 版本并提示升级。
- [ ] **更多安装脚本**: 增加 Windows (.bat/powershell) 和 Linux 系统的安装支持。

### 4. 优化
- [ ] **延迟检测优化**: 增加 Helper 侧的并发测速功能。
- [ ] **连接稳定性**: 增加 Service Worker 与 Helper 之间的心跳检测与断线重连。

---

## 🛠 开发指南
- 编译扩展: `pnpm run build`
- 编译 Helper: `cd helper && go build -o lcllink-helper .`
- 管理面板地址: `http://127.0.0.1:19527`

---
*上次更新: 2026-03-27*
