/**
 * __ai_context__: 协议抽象接口模块。
 * 定义所有代理协议必须实现的统一接口，使协议实现可插拔。
 * 新增协议只需实现 IProtocol 接口并在工厂中注册即可。
 */

import {
  type ServerConfig,
  ProtocolType,
} from './config';

// ============================================================
// 验证结果
// ============================================================
export interface ValidationResult {
  /** 配置是否有效 */
  valid: boolean;
  /** 验证错误列表（字段名 -> 错误描述） */
  errors: Record<string, string>;
}

// ============================================================
// 连接抽象
// WHY: 将已建立的连接封装为对象，便于管理生命周期
// ============================================================
export interface IConnection {
  /** 发送数据 */
  send(data: ArrayBuffer): void;
  /** 关闭连接 */
  close(): void;
  /** 连接是否仍然活跃 */
  readonly isAlive: boolean;
  /** 数据接收回调 */
  onData: ((data: ArrayBuffer) => void) | null;
  /** 连接关闭回调 */
  onClose: ((reason: string) => void) | null;
  /** 错误回调 */
  onError: ((error: Error) => void) | null;
}

// ============================================================
// 协议接口
// WHY: 统一接口让 Service Worker 不需要关心具体协议实现细节
// ============================================================
export interface IProtocol {
  /** 协议名称标识 */
  readonly name: ProtocolType;

  /**
   * 建立代理连接
   * WHY: 返回 Promise 因为握手过程是异步的
   */
  connect(config: ServerConfig): Promise<IConnection>;

  /**
   * 断开连接并清理资源
   */
  disconnect(): Promise<void>;

  /**
   * 验证服务器配置是否有效
   * WHY: 在连接前做前置检查，避免无效配置导致的连接失败
   */
  validateConfig(config: ServerConfig): ValidationResult;

  /**
   * 测试到服务器的延迟（毫秒）
   * WHY: 用于 UI 上显示服务器响应速度
   * 返回 -1 表示超时或不可达
   */
  ping(config: ServerConfig): Promise<number>;
}

// ============================================================
// 协议注册表（工厂模式）
// WHY: 使用 Map 作为注册表，新协议只需 register 即可
// ============================================================
const protocolRegistry = new Map<ProtocolType, IProtocol>();

/**
 * 注册一个协议实现
 * WHY: 模块加载时自动注册，避免中心化的 switch/case
 */
export function registerProtocol(protocol: IProtocol): void {
  protocolRegistry.set(protocol.name, protocol);
}

/**
 * 根据协议类型获取对应的实现实例
 */
export function getProtocol(type: ProtocolType): IProtocol | undefined {
  return protocolRegistry.get(type);
}

/**
 * 获取所有已注册的协议类型
 */
export function getRegisteredProtocols(): ProtocolType[] {
  return Array.from(protocolRegistry.keys());
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - 每种协议类型只有一个实例（单例模式）
 *    - 协议实现在各自的模块中调用 registerProtocol 自注册
 *    - IConnection 的生命周期由调用方（Service Worker）管理
 * 2. Potential edge cases:
 *    - getProtocol 可能返回 undefined（协议未注册），调用方需要处理
 *    - disconnect 需要正确清理 WebSocket 连接，避免内存泄漏
 * 3. Dependencies: ./config（类型定义）
 */
