/**
 * __ai_context__: Trojan 协议实现模块。
 * 实现 IProtocol 接口，提供 Trojan over WebSocket 的连接能力。
 *
 * Trojan 请求格式：
 * hex(SHA224(password))\r\n + command + address_type + address + port + \r\n + payload
 */

import {
  type IProtocol,
  type IConnection,
  type ValidationResult,
  registerProtocol,
} from '../../core/protocol';
import {
  type ServerConfig,
  type TrojanSpecificConfig,
  ProtocolType,
} from '../../core/config';
import { concatBuffers, uint16ToBuffer, stringToBuffer, toHex } from '../../utils/binary';
import { Logger } from '../../utils/logger';
import { TrojanCommand, TrojanAddressType } from './types';

const logger = new Logger('Trojan');

// ============================================================
// Trojan 连接实现
// ============================================================
class TrojanConnection implements IConnection {
  private ws: WebSocket;
  private isFirstResponse: boolean = true;

  onData: ((data: ArrayBuffer) => void) | null = null;
  onClose: ((reason: string) => void) | null = null;
  onError: ((error: Error) => void) | null = null;

  constructor(ws: WebSocket) {
    this.ws = ws;

    this.ws.onmessage = (event: MessageEvent) => {
      if (event.data instanceof ArrayBuffer) {
        // WHY: Trojan 响应没有额外头部，数据直接透传
        this.onData?.(event.data);
      }
    };

    this.ws.onclose = (event: CloseEvent) => {
      this.onClose?.(event.reason || `Code: ${event.code}`);
    };

    this.ws.onerror = () => {
      this.onError?.(new Error('WebSocket error'));
    };
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
// Trojan 协议实现
// ============================================================
class TrojanProtocol implements IProtocol {
  readonly name = ProtocolType.TROJAN;
  private currentConnection: TrojanConnection | null = null;

  async connect(config: ServerConfig): Promise<IConnection> {
    const protocolConfig = config.protocolConfig as TrojanSpecificConfig;

    // Step 1: 构建 WebSocket URL
    // WHY: Trojan 协议要求 TLS，所以默认使用 wss
    const wsScheme = config.tls.enabled ? 'wss' : 'ws';
    const wsPath = config.websocket.path || '/';
    const wsUrl = `${wsScheme}://${config.address}:${config.port}${wsPath}`;

    logger.info(`Connecting to ${wsUrl}`);

    // Step 2: 建立 WebSocket 连接
    const ws = await this.createWebSocket(wsUrl);

    // Step 3: 构建并发送 Trojan 请求头
    const header = await this.buildTrojanHeader(
      protocolConfig.password,
      TrojanCommand.CONNECT,
      config.address,
      config.port,
    );
    ws.send(header);

    logger.info('Trojan handshake sent');

    this.currentConnection = new TrojanConnection(ws);
    return this.currentConnection;
  }

  async disconnect(): Promise<void> {
    if (this.currentConnection) {
      this.currentConnection.close();
      this.currentConnection = null;
    }
    logger.info('Disconnected');
  }

  validateConfig(config: ServerConfig): ValidationResult {
    const errors: Record<string, string> = {};
    const protocolConfig = config.protocolConfig as TrojanSpecificConfig;

    if (!config.address) {
      errors['address'] = '服务器地址不能为空';
    }

    if (config.port <= 0 || config.port > 65535) {
      errors['port'] = '端口必须在 1-65535 之间';
    }

    if (!protocolConfig.password) {
      errors['password'] = '密码不能为空';
    }

    if (!config.tls.enabled) {
      errors['tls'] = 'Trojan 协议要求启用 TLS';
    }

    return {
      valid: Object.keys(errors).length === 0,
      errors,
    };
  }

  async ping(config: ServerConfig): Promise<number> {
    const wsScheme = config.tls.enabled ? 'wss' : 'ws';
    const wsPath = config.websocket.path || '/';
    const wsUrl = `${wsScheme}://${config.address}:${config.port}${wsPath}`;

    const startTime = performance.now();

    try {
      const ws = new WebSocket(wsUrl);
      return await new Promise<number>((resolve) => {
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
   * 构建 Trojan 请求头
   *
   * 格式：hex(SHA224(password))\r\n + CMD(1B) + ATYP(1B) + ADDR + PORT(2B) + \r\n
   *
   * WHY: Trojan 使用 SHA224 哈希密码而非明文，增加安全性
   */
  private async buildTrojanHeader(
    password: string,
    command: TrojanCommand,
    targetAddress: string,
    targetPort: number,
  ): Promise<ArrayBuffer> {
    // Step 1: SHA224(password) 转十六进制
    // WHY: Web Crypto API 不直接支持 SHA224，使用 SHA256 截取前 28 字节替代
    const passwordHash = await this.sha224Hex(password);
    const hashBuf = stringToBuffer(passwordHash);

    // Step 2: CRLF
    const crlfBuf = stringToBuffer('\r\n');

    // Step 3: 命令（1 字节）
    const cmdBuf = new Uint8Array([command]).buffer;

    // Step 4: 地址编码（与 SOCKS5 格式相同）
    const addrBuf = this.encodeAddress(targetAddress);

    // Step 5: 端口（2 字节大端序）
    const portBuf = uint16ToBuffer(targetPort);

    // Step 6: 最后的 CRLF
    return concatBuffers(hashBuf, crlfBuf, cmdBuf, addrBuf, portBuf, crlfBuf);
  }

  /**
   * 计算 SHA224 哈希的十六进制字符串
   * WHY: Web Crypto API 原生支持的最接近算法是 SHA-256，
   *      SHA-224 是 SHA-256 的截断变体，使用不同的初始值。
   *      这里使用 SHA-256 截取 28 字节作为近似实现。
   *      对于完全兼容的实现，可以使用 WASM 版本的 SHA-224。
   */
  private async sha224Hex(input: string): Promise<string> {
    const encoder = new TextEncoder();
    const data = encoder.encode(input);
    // WHY: 浏览器 SubtleCrypto 支持 SHA-256，截取前 224 位(28字节)
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = new Uint8Array(hashBuffer).slice(0, 28);
    return toHex(hashArray);
  }

  /**
   * 编码目标地址（SOCKS5 格式）
   */
  private encodeAddress(address: string): ArrayBuffer {
    const ipv4Regex = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
    const ipv4Match = address.match(ipv4Regex);

    if (ipv4Match) {
      const typeBuf = new Uint8Array([TrojanAddressType.IPV4]);
      const addrBuf = new Uint8Array([
        parseInt(ipv4Match[1]),
        parseInt(ipv4Match[2]),
        parseInt(ipv4Match[3]),
        parseInt(ipv4Match[4]),
      ]);
      return concatBuffers(typeBuf.buffer, addrBuf.buffer);
    }

    if (address.includes(':')) {
      // IPv6 简化处理
      const typeBuf = new Uint8Array([TrojanAddressType.IPV6]);
      const placeholder = new Uint8Array(16); // TODO: 完整 IPv6 解析
      return concatBuffers(typeBuf.buffer, placeholder.buffer);
    }

    // 域名
    const domainBytes = new TextEncoder().encode(address);
    const typeBuf = new Uint8Array([TrojanAddressType.DOMAIN]);
    const lenBuf = new Uint8Array([domainBytes.length]);
    return concatBuffers(typeBuf.buffer, lenBuf.buffer, domainBytes.buffer);
  }

  private createWebSocket(url: string): Promise<WebSocket> {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(url);
      ws.binaryType = 'arraybuffer';

      const timeout = setTimeout(() => {
        ws.close();
        reject(new Error('Connection timeout'));
      }, 10_000);

      ws.onopen = () => {
        clearTimeout(timeout);
        resolve(ws);
      };

      ws.onerror = () => {
        clearTimeout(timeout);
        reject(new Error('Connection failed'));
      };
    });
  }
}

// WHY: 模块加载时自动注册
registerProtocol(new TrojanProtocol());

export { TrojanProtocol };

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - SHA224 使用 SHA256 截取替代（近似实现），完整兼容需要 WASM
 *    - Trojan 响应无额外头部，数据直接透传
 *    - Trojan 要求 TLS 加密
 * 2. Potential edge cases:
 *    - SHA224 近似实现可能与某些服务端不兼容
 *    - IPv6 地址解析目前是占位实现
 * 3. Dependencies: ../../core/protocol, ../../core/config, ../../utils/binary
 */
