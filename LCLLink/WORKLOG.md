# WORKLOG - LCLLink

## 2026-03-27

### 项目初始化与基础架构搭建

**完成内容：**

1. **项目规划**
   - 分析 Chrome Extension MV3 技术限制
   - 确定渐进式架构方案（Phase 1 纯浏览器 + Phase 2 Native Helper）
   - 编写详细实施计划并获得批准

2. **基础设施**（6 个文件）
   - `package.json` - npm 配置（TypeScript + Vite）
   - `tsconfig.json` - TypeScript 严格模式
   - `vite.config.ts` - 多入口构建 + 静态资源自动复制
   - `manifest.json` - Chrome Extension Manifest V3
   - `.gitignore`
   - `README.md`

3. **核心模块**（`src/core/`，4 个文件）
   - `config.ts` - 全部类型定义（协议配置、连接状态、消息协议）
   - `protocol.ts` - 协议抽象接口 + 注册表工厂
   - `proxy-manager.ts` - chrome.proxy API 封装
   - `connection.ts` - WebSocket 连接管理与 Service Worker 保活

4. **协议实现**（`src/protocols/`，8 个文件）
   - VLESS：`types.ts` + `header.ts`（头部二进制构建）+ `index.ts`（协议实现）
   - Trojan：`types.ts` + `index.ts`（SHA224 + 协议实现）
   - Shadowsocks：`types.ts` + `crypto.ts`（AEAD 加解密）+ `index.ts`（协议实现）

5. **工具模块**（`src/utils/`，3 个文件）
   - `binary.ts` - 二进制数据处理
   - `uuid.ts` - UUID 字符串/字节转换
   - `logger.ts` - 分级日志系统

6. **UI 层**
   - Popup：`index.html` + `popup.css` + `popup.ts`（深色主题，连接控制）
   - Options：`index.html` + `options.css` + `options.ts`（服务器管理，表单，日志）

7. **Service Worker**
   - `service-worker.ts` - 消息处理、协议连接管理、代理配置

8. **资源**
   - 项目 Logo 生成（闪电盾牌图标）
   - 4 种尺寸图标（16/32/48/128px）

**构建验证：**
- TypeScript 编译：✅ 无错误
- Vite 构建：✅ 23 个模块成功打包
- dist 目录：✅ 结构与 manifest.json 路径匹配

**待办：**
- 在 Chrome 开发者模式中手动加载扩展测试
- Phase 2 Native Messaging Helper 开发

---

### URI 链接导入功能

**完成内容：**

1. **URI 解析器**（`src/utils/uri-parser.ts`）
   - 支持 `vless://uuid@host:port?params#name` 格式
   - 支持 `trojan://password@host:port?params#name` 格式
   - 支持 `ss://base64(method:password)@host:port#name` 格式（Legacy + SIP002）
   - 批量导入（每行一个 URI）
   - 完整的错误处理和用户提示

2. **Options 页面更新**
   - 新增「导入链接」按钮，展开可折叠导入面板
   - `textarea` 粘贴区域支持多行 URI
   - 解析结果动态显示（成功数/失败数/错误详情）
   - 导入成功 3 秒后自动收起面板

3. **UI 重新设计**
   - 修复 CSS code splitting 问题（popup 和 options 独立 CSS 文件）
   - 升级为赛博科技风深色主题
   - 氰色高光 + 发光边框 + 微光背景

**构建验证：** ✅ 24 个模块成功打包

---

### Phase 2：Native Helper 开发

**Go Helper 骨架完成：**

1. **项目结构** (`helper/`)
   - `main.go` — 入口：NM 监听 + HTTP API + 优雅关闭
   - `internal/types/` — 共享类型（镜像 TypeScript config.ts）
   - `internal/nativemsg/` — Chrome NM 协议编解码
   - `internal/manager/` — 端口池管理器（10001-10099，99 实例上限）
   - `internal/engine/` — xray-core 封装（SOCKS5 入站 + 协议出站）
   - `internal/api/` — HTTP API（127.0.0.1:19527）

2. **技术选型：** Go + xray-core（库模式），支持 VLESS+Reality/Trojan/SS

3. **编译验证：** ✅ 41MB ARM64 二进制

3. **Embedded Web UI**: 
   - 实现了基于 Go embed 的内置管理面板（`http://127.0.0.1:19527`）
   - 赛博科技风设计，实时显示所有浏览器的代理实例状态、端口分配、运行时长
   - 支持通过 Web 界面手动断开指定端口的代理

4. **扩展侧集成 (HelperClient)**:
   - 实现自动检测、启动 Helper (Native Messaging)
   - 重构 Service Worker 连接逻辑：优先调起 Helper 建立 SOCKS5 代理，Helper 不可用时回退到 WebSocket 直连

**构建验证：** ✅ 25 个 TS 模块成功打包；Go Helper 编译为 41MB 二进制

**待办：** 安装脚本测试、端到端联动测试、更多系统级协议支持 (Hysteria2/TUIC)
