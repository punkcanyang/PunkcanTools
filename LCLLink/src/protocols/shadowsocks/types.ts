/**
 * __ai_context__: Shadowsocks 协议类型定义。
 */

/**
 * Shadowsocks 支持的加密方法与其参数
 */
export interface CipherInfo {
  /** 密钥长度（字节） */
  keySize: number;
  /** Nonce/IV 长度（字节） */
  nonceSize: number;
  /** 认证标签长度（字节） */
  tagSize: number;
  /** Web Crypto API 对应的算法名称 */
  webCryptoAlgorithm: string;
}

/**
 * 加密方法与参数映射
 * WHY: 集中管理加密参数，避免散落在代码各处
 */
export const CIPHER_INFO: Record<string, CipherInfo> = {
  'aes-128-gcm': {
    keySize: 16,
    nonceSize: 12,
    tagSize: 16,
    webCryptoAlgorithm: 'AES-GCM',
  },
  'aes-256-gcm': {
    keySize: 32,
    nonceSize: 12,
    tagSize: 16,
    webCryptoAlgorithm: 'AES-GCM',
  },
  // WHY: ChaCha20 在 Web Crypto API 中不被原生支持，需要 WASM 或 polyfill
  'chacha20-ietf-poly1305': {
    keySize: 32,
    nonceSize: 12,
    tagSize: 16,
    webCryptoAlgorithm: '', // 不支持，需要 polyfills
  },
  // SS-2022 变体
  '2022-blake3-aes-128-gcm': {
    keySize: 16,
    nonceSize: 12,
    tagSize: 16,
    webCryptoAlgorithm: 'AES-GCM',
  },
  '2022-blake3-aes-256-gcm': {
    keySize: 32,
    nonceSize: 12,
    tagSize: 16,
    webCryptoAlgorithm: 'AES-GCM',
  },
};

/**
 * Shadowsocks ATYP（地址类型，与 SOCKS5 相同）
 */
export enum SsAddressType {
  IPV4 = 0x01,
  DOMAIN = 0x03,
  IPV6 = 0x04,
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - AES-GCM 可通过 Web Crypto API 原生加速
 *    - ChaCha20 需要额外的 polyfill
 *    - SS-2022 使用 BLAKE3 KDF 推导密钥
 * 2. Potential edge cases:
 *    - Web Crypto API 可能在某些环境中不可用
 * 3. Dependencies: 无
 */
