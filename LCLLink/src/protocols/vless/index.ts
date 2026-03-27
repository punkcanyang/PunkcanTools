/**
 * __ai_context__: VLESS 协议实现模块。
 * 实现 IProtocol 接口，提供 VLESS over WebSocket 的连接能力。
 * 连接流程：建立 WebSocket → 发送 VLESS 头部 → 透传数据
 */

import {
  type IProtocol,
  type IConnection,
  type ValidationResult,
  registerProtocol,
} from '../../core/protocol';
import {
  type ServerConfig,
  type VlessSpecificConfig,
  ProtocolType,
} from '../../core/config';
import { isValidUuid } from '../../utils/uuid';
import { Logger } from '../../utils/logger';
import { buildRequestHeader, parseResponseHeader } from './header';
import { VlessCommand } from './types';

const logger = new Logger('VLESS');

// ============================================================
// VLESS 连接实现
// ============================================================
class VlessConnection implements IConnection {
  private ws: WebSocket;
  private headerSent: boolean = false;

  onData: ((data: ArrayBuffer) => void) | null = null;
  onClose: ((reason: string) => void) | null = null;
  onError: ((error: Error) => void) | null = null;

  constructor(ws: WebSocket) {
    this.ws = ws;

    this.ws.onmessage = (event: MessageEvent) => {
      if (event.data instanceof ArrayBuffer) {
        this.handleData(event.data);
      }
    };

    this.ws.onclose = (event: CloseEvent) => {
      this.onClose?.(event.reason || `Connection closed: ${event.code}`);
    };

    this.ws.onerror = () => {
      this.onError?.(new Error('WebSocket error'));
    };
  }

  /**
   * 处理接收到的数据
   * WHY: 第一个响应包含 VLESS 响应头部，需要跳过后再传递数据
   */
  private handleData(data: ArrayBuffer): void {
    if (!this.headerSent) {
      // WHY: 第一次收到数据时解析响应头
      try {
        const dataOffset = parseResponseHeader(data);
        const payload = data.slice(dataOffset);
        if (payload.byteLength > 0) {
          this.onData?.(payload);
        }
        this.headerSent = true;
      } catch (error) {
        this.onError?.(error as Error);
      }
    } else {
      // 后续数据直接透传
      this.onData?.(data);
    }
  }

  send(data: ArrayBuffer): void {
    if (this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(data);
    }
  }

  close(): void {
    this.ws.close(1000, 'Client close');
  }

  get isAlive(): boolean {
    return this.ws.readyState === WebSocket.OPEN;
  }
}

// ============================================================
// VLESS 协议实现
// ============================================================
class VlessProtocol implements IProtocol {
  readonly name = ProtocolType.VLESS;
  private currentConnection: VlessConnection | null = null;

  /**
   * 建立 VLESS over WebSocket 连接
   *
   * 流程：
   * 1. 构建 WebSocket URL（包含 TLS 和路径配置）
   * 2. 建立 WebSocket 连接
   * 3. 发送 VLESS 请求头部
   * 4. 进入数据透传阶段
   */
  async connect(config: ServerConfig): Promise<IConnection> {
    const protocolConfig = config.protocolConfig as VlessSpecificConfig;

    // Step 1: 构建 WebSocket URL
    const wsScheme = config.tls.enabled ? 'wss' : 'ws';
    const wsPath = config.websocket.path || '/';
    const wsUrl = `${wsScheme}://${config.address}:${config.port}${wsPath}`;

    logger.info(`Connecting to ${wsUrl}`);

    // Step 2: 建立 WebSocket 连接
    const ws = await this.createWebSocket(wsUrl, config);

    // Step 3: 发送 VLESS 请求头部
    // WHY: VLESS 头部在首个 WebSocket 消息中发送，包含目标地址信息
    const header = buildRequestHeader(
      protocolConfig.uuid,
      VlessCommand.TCP,
      config.address,
      config.port,
    );
    ws.send(header);

    logger.info('VLESS handshake sent');

    // Step 4: 创建连接对象
    this.currentConnection = new VlessConnection(ws);
    return this.currentConnection;
  }

  async disconnect(): Promise<void> {
    if (this.currentConnection) {
      this.currentConnection.close();
      this.currentConnection = null;
    }
    logger.info('Disconnected');
  }

  /**
   * 验证 VLESS 配置
   */
  validateConfig(config: ServerConfig): ValidationResult {
    const errors: Record<string, string> = {};
    const protocolConfig = config.protocolConfig as VlessSpecificConfig;

    if (!config.address) {
      errors['address'] = '服务器地址不能为空';
    }

    if (config.port <= 0 || config.port > 65535) {
      errors['port'] = '端口必须在 1-65535 之间';
    }

    if (!protocolConfig.uuid) {
      errors['uuid'] = 'UUID 不能为空';
    } else if (!isValidUuid(protocolConfig.uuid)) {
      errors['uuid'] = 'UUID 格式无效';
    }

    return {
      valid: Object.keys(errors).length === 0,
      errors,
    };
  }

  /**
   * 测试服务器延迟
   * WHY: 通过测量 WebSocket 握手时间来估算延迟
   */
  async ping(config: ServerConfig): Promise<number> {
    const wsScheme = config.tls.enabled ? 'wss' : 'ws';
    const wsPath = config.websocket.path || '/';
    const wsUrl = `${wsScheme}://${config.address}:${config.port}${wsPath}`;

    const startTime = performance.now();

    try {
      const ws = new WebSocket(wsUrl);
      return await new Promise<number>((resolve) => {
        // WHY: 5 秒超时
        const timeout = setTimeout(() => {
          ws.close();
          resolve(-1);
        }, 5000);

        ws.onopen = () => {
          clearTimeout(timeout);
          const latency = Math.round(performance.now() - startTime);
          ws.close();
          resolve(latency);
        };

        ws.onerror = () => {
          clearTimeout(timeout);
          resolve(-1);
        };
      });
    } catch {
      return -1;
    }
  }

  /**
   * 创建 WebSocket 连接
   * WHY: 将连接建立封装为 Promise，便于 async/await 使用
   */
  private createWebSocket(url: string, config: ServerConfig): Promise<WebSocket> {
    return new Promise((resolve, reject) => {
      try {
        const ws = new WebSocket(url);
        ws.binaryType = 'arraybuffer';

        const timeout = setTimeout(() => {
          ws.close();
          reject(new Error('WebSocket connection timeout'));
        }, 10_000);

        ws.onopen = () => {
          clearTimeout(timeout);
          resolve(ws);
        };

        ws.onerror = (event) => {
          clearTimeout(timeout);
          reject(new Error('WebSocket connection failed'));
        };
      } catch (error) {
        reject(error);
      }
    });
  }
}

// WHY: 模块加载时自动注册 VLESS 协议实现
registerProtocol(new VlessProtocol());

export { VlessProtocol };

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - VLESS 头部只发送一次（连接建立时）
 *    - 后续通信是透明的二进制数据透传
 *    - Reality 模式需要服务端配合，浏览器端主要依赖 TLS/SNI 配置
 * 2. Potential edge cases:
 *    - WebSocket 可能被中间设备（如 CDN）修改或拦截
 *    - TLS SNI 可能被运营商检测
 *    - 第一个响应包可能与应用数据合并
 * 3. Dependencies: ../../core/protocol, ../../core/config, ../../utils/uuid, ./header
 */
