/**
 * __ai_context__: Shadowsocks 协议实现模块。
 * 实现 IProtocol 接口，提供 Shadowsocks over WebSocket 的连接能力。
 * 仅支持 WebSocket 传输模式（需要服务端安装 v2ray-plugin 等 WS 插件）。
 */

import {
  type IProtocol,
  type IConnection,
  type ValidationResult,
  registerProtocol,
} from '../../core/protocol';
import {
  type ServerConfig,
  type ShadowsocksSpecificConfig,
  ProtocolType,
} from '../../core/config';
import { Logger } from '../../utils/logger';
import { concatBuffers, uint16ToBuffer } from '../../utils/binary';
import { CIPHER_INFO, SsAddressType } from './types';
import {
  deriveKey,
  hkdfSha1,
  aeadEncrypt,
  aeadDecrypt,
  incrementNonce,
  generateSalt,
} from './crypto';

const logger = new Logger('Shadowsocks');

// Shadowsocks HKDF info 常量
const SS_SUBKEY_INFO = new TextEncoder().encode('ss-subkey');

// ============================================================
// Shadowsocks 连接
// ============================================================
class ShadowsocksConnection implements IConnection {
  private ws: WebSocket;
  private encryptKey: Uint8Array | null = null;
  private decryptKey: Uint8Array | null = null;
  private encryptNonce: Uint8Array;
  private decryptNonce: Uint8Array;
  private isFirstResponse: boolean = true;
  private cipherKeySize: number;

  onData: ((data: ArrayBuffer) => void) | null = null;
  onClose: ((reason: string) => void) | null = null;
  onError: ((error: Error) => void) | null = null;

  constructor(
    ws: WebSocket,
    encryptKey: Uint8Array,
    nonceSize: number,
    keySize: number,
  ) {
    this.ws = ws;
    this.encryptKey = encryptKey;
    this.encryptNonce = new Uint8Array(nonceSize);
    this.decryptNonce = new Uint8Array(nonceSize);
    this.cipherKeySize = keySize;

    this.ws.onmessage = (event: MessageEvent) => {
      if (event.data instanceof ArrayBuffer) {
        this.handleIncomingData(event.data).catch((err) => {
          this.onError?.(err as Error);
        });
      }
    };

    this.ws.onclose = (event: CloseEvent) => {
      this.onClose?.(event.reason || `Code: ${event.code}`);
    };

    this.ws.onerror = () => {
      this.onError?.(new Error('WebSocket error'));
    };
  }

  /**
   * 处理接收到的加密数据
   */
  private async handleIncomingData(data: ArrayBuffer): Promise<void> {
    const dataView = new Uint8Array(data);

    if (this.isFirstResponse) {
      // WHY: 第一个响应包包含服务端的 salt，用于推导解密密钥
      const salt = dataView.slice(0, this.cipherKeySize);

      // WHY: 使用 HKDF 从主密钥 + 服务端 salt 推导解密子密钥
      if (this.encryptKey) {
        this.decryptKey = await hkdfSha1(
          this.encryptKey,
          salt,
          SS_SUBKEY_INFO,
          this.cipherKeySize,
        );
      }

      this.isFirstResponse = false;

      // 剩余数据是加密的载荷
      const encrypted = dataView.slice(this.cipherKeySize);
      if (encrypted.length > 0) {
        await this.decryptAndEmit(encrypted);
      }
    } else {
      await this.decryptAndEmit(dataView);
    }
  }

  /**
   * 解密数据并触发回调
   */
  private async decryptAndEmit(encrypted: Uint8Array): Promise<void> {
    if (!this.decryptKey) {
      this.onError?.(new Error('Decrypt key not ready'));
      return;
    }

    try {
      const decrypted = await aeadDecrypt(
        this.decryptKey,
        this.decryptNonce,
        encrypted,
      );
      incrementNonce(this.decryptNonce);
      this.onData?.(decrypted.buffer as ArrayBuffer);
    } catch (error) {
      this.onError?.(error as Error);
    }
  }

  async send(data: ArrayBuffer): Promise<void> {
    if (!this.encryptKey || this.ws.readyState !== WebSocket.OPEN) {
      return;
    }

    try {
      const encrypted = await aeadEncrypt(
        this.encryptKey,
        this.encryptNonce,
        new Uint8Array(data),
      );
      incrementNonce(this.encryptNonce);
      this.ws.send(encrypted);
    } catch (error) {
      this.onError?.(error as Error);
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
// Shadowsocks 协议
// ============================================================
class ShadowsocksProtocol implements IProtocol {
  readonly name = ProtocolType.SHADOWSOCKS;
  private currentConnection: ShadowsocksConnection | null = null;

  async connect(config: ServerConfig): Promise<IConnection> {
    const protocolConfig = config.protocolConfig as ShadowsocksSpecificConfig;
    const cipherInfo = CIPHER_INFO[protocolConfig.method];

    if (!cipherInfo) {
      throw new Error(`Unsupported cipher method: ${protocolConfig.method}`);
    }

    if (!cipherInfo.webCryptoAlgorithm) {
      throw new Error(`Cipher ${protocolConfig.method} is not supported in browser (needs WASM polyfill)`);
    }

    // Step 1: 密钥推导
    const masterKey = await deriveKey(protocolConfig.password, cipherInfo.keySize);

    // Step 2: 生成客户端 salt
    const salt = generateSalt(cipherInfo.keySize);

    // Step 3: 使用 HKDF 从主密钥 + salt 推导加密子密钥
    const encryptSubKey = await hkdfSha1(
      masterKey,
      salt,
      SS_SUBKEY_INFO,
      cipherInfo.keySize,
    );

    // Step 4: 建立 WebSocket 连接
    const wsScheme = config.tls.enabled ? 'wss' : 'ws';
    const wsPath = config.websocket.path || '/';
    const wsUrl = `${wsScheme}://${config.address}:${config.port}${wsPath}`;

    logger.info(`Connecting to ${wsUrl} with method ${protocolConfig.method}`);

    const ws = await this.createWebSocket(wsUrl);

    // Step 5: 构建初始数据（salt + 加密的目标地址头）
    const addressHeader = this.buildAddressHeader(config.address, config.port);
    const encryptNonce = new Uint8Array(cipherInfo.nonceSize);
    const encryptedHeader = await aeadEncrypt(encryptSubKey, encryptNonce, addressHeader);
    incrementNonce(encryptNonce);

    // WHY: 第一个包 = salt + 加密的地址头
    const initialPayload = concatBuffers(salt.buffer as ArrayBuffer, encryptedHeader.buffer as ArrayBuffer);
    ws.send(initialPayload);

    logger.info('Shadowsocks handshake sent');

    this.currentConnection = new ShadowsocksConnection(
      ws,
      masterKey,
      cipherInfo.nonceSize,
      cipherInfo.keySize,
    );
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
    const protocolConfig = config.protocolConfig as ShadowsocksSpecificConfig;

    if (!config.address) {
      errors['address'] = '服务器地址不能为空';
    }

    if (config.port <= 0 || config.port > 65535) {
      errors['port'] = '端口必须在 1-65535 之间';
    }

    if (!protocolConfig.password) {
      errors['password'] = '密码不能为空';
    }

    if (!protocolConfig.method) {
      errors['method'] = '请选择加密方法';
    } else if (!CIPHER_INFO[protocolConfig.method]) {
      errors['method'] = `不支持的加密方法: ${protocolConfig.method}`;
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
          resolve(Math.round(performance.now() - startTime));
          ws.close();
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
   * 构建目标地址头部（SOCKS5 格式）
   */
  private buildAddressHeader(address: string, port: number): Uint8Array {
    const ipv4Regex = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
    const ipv4Match = address.match(ipv4Regex);

    if (ipv4Match) {
      const result = new Uint8Array(7); // 1(type) + 4(addr) + 2(port)
      result[0] = SsAddressType.IPV4;
      result[1] = parseInt(ipv4Match[1]);
      result[2] = parseInt(ipv4Match[2]);
      result[3] = parseInt(ipv4Match[3]);
      result[4] = parseInt(ipv4Match[4]);
      result[5] = (port >> 8) & 0xff;
      result[6] = port & 0xff;
      return result;
    }

    // 域名
    const domainBytes = new TextEncoder().encode(address);
    const result = new Uint8Array(1 + 1 + domainBytes.length + 2);
    result[0] = SsAddressType.DOMAIN;
    result[1] = domainBytes.length;
    result.set(domainBytes, 2);
    result[2 + domainBytes.length] = (port >> 8) & 0xff;
    result[2 + domainBytes.length + 1] = port & 0xff;
    return result;
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

// 自动注册
registerProtocol(new ShadowsocksProtocol());

export { ShadowsocksProtocol };

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - 仅支持 WebSocket 传输模式
 *    - AES-GCM 通过 Web Crypto API 实现
 *    - ChaCha20 需要额外 polyfill（当前未实现）
 *    - SS-2022 的 BLAKE3 KDF 需要额外实现
 * 2. Potential edge cases:
 *    - 加密方法 'chacha20-ietf-poly1305' 验证会通过但连接会失败
 *    - AEAD 每个数据块的长度限制（2^14 = 16384 字节）
 *    - 密钥推导使用 SHA-256 替代 MD5 可能与某些服务端不兼容
 * 3. Dependencies: ../../core/protocol, ../../core/config, ./crypto, ./types
 */
