/**
 * __ai_context__: LCLLink 核心配置类型定义模块。
 * 定义所有协议的配置数据结构，使用严格 TypeScript 类型作为 AI 防护栏。
 * 这是整个项目的数据契约核心，所有模块都依赖此文件的类型定义。
 */

// ============================================================
// 协议类型枚举
// WHY: 使用字符串枚举而非 union type，便于运行时校验和序列化
// ============================================================
export enum ProtocolType {
  VLESS = 'vless',
  TROJAN = 'trojan',
  SHADOWSOCKS = 'shadowsocks',
  SHADOWSOCKS_2022 = 'shadowsocks-2022',
}

// ============================================================
// 传输方式枚举
// WHY: Phase 1 只支持 WebSocket，但预留其他传输方式给 Phase 2
// ============================================================
export enum TransportType {
  WEBSOCKET = 'websocket',
  // Phase 2:
  // TCP = 'tcp',
  // QUIC = 'quic',
  // GRPC = 'grpc',
}

// ============================================================
// TLS 安全配置
// ============================================================
export interface TlsConfig {
  /** 是否启用 TLS */
  enabled: boolean;
  /** 服务器名称指示（SNI） */
  serverName: string;
  /** 是否允许不安全连接（跳过证书验证） */
  allowInsecure: boolean;
  /** ALPN 协议列表 */
  alpn: string[];
  /** 指纹伪装类型（如 chrome, firefox） */
  fingerprint: string;
}

// ============================================================
// Reality 配置（VLESS 专用）
// ============================================================
export interface RealityConfig {
  /** 是否启用 Reality */
  enabled: boolean;
  /** 公钥 */
  publicKey: string;
  /** Short ID */
  shortId: string;
  /** Spider X 路径 */
  spiderX: string;
}

// ============================================================
// WebSocket 传输配置
// ============================================================
export interface WebSocketConfig {
  /** WebSocket 路径（如 /ws） */
  path: string;
  /** 自定义 HTTP 头 */
  headers: Record<string, string>;
  /** 最大早期数据大小（0-based WebSocket 0-RTT） */
  maxEarlyData: number;
  /** 早期数据头名称 */
  earlyDataHeaderName: string;
}

// ============================================================
// 各协议独有配置
// ============================================================

/** VLESS 协议配置 */
export interface VlessSpecificConfig {
  /** 用户 UUID */
  uuid: string;
  /** 加密方式（VLESS 通常为 none） */
  encryption: string;
  /** Flow 控制（如 xtls-rprx-vision） */
  flow: string;
  /** Reality 配置 */
  reality: RealityConfig;
}

/** Trojan 协议配置 */
export interface TrojanSpecificConfig {
  /** 密码 */
  password: string;
}

/** Shadowsocks 协议配置 */
export interface ShadowsocksSpecificConfig {
  /** 加密方法 */
  method: ShadowsocksMethod;
  /** 密码 */
  password: string;
}

/** Shadowsocks 支持的加密方法 */
export type ShadowsocksMethod =
  | 'aes-128-gcm'
  | 'aes-256-gcm'
  | 'chacha20-ietf-poly1305'
  | '2022-blake3-aes-128-gcm'
  | '2022-blake3-aes-256-gcm'
  | '2022-blake3-chacha20-poly1305';

// ============================================================
// 服务器节点配置（统一结构）
// ============================================================
export interface ServerConfig {
  /** 唯一标识符 */
  id: string;
  /** 用户自定义名称（备注） */
  name: string;
  /** 协议类型 */
  protocol: ProtocolType;
  /** 服务器地址 */
  address: string;
  /** 服务器端口 */
  port: number;
  /** 传输方式 */
  transport: TransportType;

  /** TLS 配置 */
  tls: TlsConfig;
  /** WebSocket 传输配置 */
  websocket: WebSocketConfig;

  /** 协议特定配置（使用判别联合） */
  protocolConfig: VlessSpecificConfig | TrojanSpecificConfig | ShadowsocksSpecificConfig;

  /** 创建时间 */
  createdAt: number;
  /** 最后修改时间 */
  updatedAt: number;
  /** 最后测速结果（毫秒，-1 表示超时） */
  latency: number;
}

// ============================================================
// 连接状态
// ============================================================
export enum ConnectionStatus {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  ERROR = 'error',
}

// ============================================================
// 应用全局状态
// ============================================================
export interface AppState {
  /** 当前连接状态 */
  status: ConnectionStatus;
  /** 当前激活的服务器 ID（null 表示未选中） */
  activeServerId: string | null;
  /** 错误信息 */
  errorMessage: string;
  /** 连接开始时间戳（用于计算连接时长） */
  connectedSince: number | null;
}

// ============================================================
// 存储结构（chrome.storage.local 的完整 schema）
// ============================================================
export interface StorageSchema {
  /** 所有服务器配置列表 */
  servers: ServerConfig[];
  /** 应用状态 */
  appState: AppState;
  /** 日志条目 */
  logs: LogEntry[];
}

/** 日志条目 */
export interface LogEntry {
  /** 时间戳 */
  timestamp: number;
  /** 日志级别 */
  level: LogLevel;
  /** 日志来源模块 */
  source: string;
  /** 日志内容 */
  message: string;
}

export enum LogLevel {
  DEBUG = 'debug',
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error',
}

// ============================================================
// Service Worker 消息协议
// WHY: 定义 Popup/Options 与 Service Worker 之间的通信格式
// ============================================================
export enum MessageAction {
  /** 连接到指定服务器 */
  CONNECT = 'connect',
  /** 断开当前连接 */
  DISCONNECT = 'disconnect',
  /** 获取当前状态 */
  GET_STATUS = 'get_status',
  /** 测试指定服务器延迟 */
  PING = 'ping',
  /** 状态变更通知（从 SW 广播） */
  STATUS_CHANGED = 'status_changed',
}

export interface ExtensionMessage {
  action: MessageAction;
  payload?: unknown;
}

export interface ExtensionResponse {
  success: boolean;
  data?: unknown;
  error?: string;
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - 所有配置通过 chrome.storage.local 持久化
 *    - ServerConfig.protocolConfig 使用判别联合，需要结合 protocol 字段判断类型
 *    - Phase 1 只使用 TransportType.WEBSOCKET
 * 2. Potential edge cases:
 *    - protocolConfig 的类型判别需要通过 protocol 字段，而非 TypeScript 自带的判别联合
 *    - ShadowsocksMethod 的 2022 变体需要不同的密钥格式（Base64 编码）
 * 3. Dependencies: 无外部依赖，纯类型定义
 */
