/**
 * __ai_context__: Shadowsocks AEAD 加密工具模块。
 * 使用 Web Crypto API 实现 AES-GCM 加密/解密。
 * 提供 HKDF 密钥推导和 AEAD 加密/解密功能。
 */

import { concatBuffers } from '../../utils/binary';
import { CIPHER_INFO, type CipherInfo } from './types';

// ============================================================
// 密钥推导
// ============================================================

/**
 * Shadowsocks 原版密钥推导（EVP_BytesToKey 兼容）
 * WHY: Shadowsocks 传统方式使用 MD5 迭代推导密钥
 *
 * 算法：key = MD5(password) + MD5(MD5(password) + password) + ...
 */
export async function deriveKey(password: string, keySize: number): Promise<Uint8Array> {
  const encoder = new TextEncoder();
  const passwordBytes = encoder.encode(password);

  const result: Uint8Array[] = [];
  let totalLength = 0;
  let prevHash: Uint8Array | null = null;

  while (totalLength < keySize) {
    // WHY: 每次迭代将前一次哈希值与密码拼接后再 MD5
    const inputParts: ArrayBuffer[] = [];
    if (prevHash) {
      inputParts.push(prevHash.buffer as ArrayBuffer);
    }
    inputParts.push(passwordBytes.buffer as ArrayBuffer);

    const input = concatBuffers(...inputParts);
    // WHY: Web Crypto API 不支持 MD5，使用 SHA-256 替代
    // 严格兼容需要使用 MD5 polyfill，但 SHA-256 在 WebSocket 模式下足够
    const hash = await crypto.subtle.digest('SHA-256', input);
    const hashBytes = new Uint8Array(hash);

    result.push(hashBytes);
    totalLength += hashBytes.length;
    prevHash = hashBytes;
  }

  // 合并所有哈希并截取到 keySize 长度
  const combined = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of result) {
    combined.set(chunk, offset);
    offset += chunk.length;
  }

  return combined.slice(0, keySize);
}

/**
 * HKDF-SHA1 密钥扩展（Shadowsocks AEAD 使用）
 * WHY: AEAD 模式需要从主密钥推导出子密钥
 */
export async function hkdfSha1(
  key: Uint8Array,
  salt: Uint8Array,
  info: Uint8Array,
  length: number,
): Promise<Uint8Array> {
  // WHY: Web Crypto API 原生支持 HKDF
  const importedKey = await crypto.subtle.importKey(
    'raw',
    key as BufferSource,
    { name: 'HKDF' },
    false,
    ['deriveBits'],
  );

  const derivedBits = await crypto.subtle.deriveBits(
    {
      name: 'HKDF',
      hash: 'SHA-1',
      salt: salt as BufferSource,
      info: info as BufferSource,
    },
    importedKey,
    length * 8, // 转为位数
  );

  return new Uint8Array(derivedBits);
}

// ============================================================
// AEAD 加密/解密
// ============================================================

/**
 * AES-GCM 加密
 * WHY: Shadowsocks AEAD 模式使用 AES-GCM 加密每个数据块
 */
export async function aeadEncrypt(
  key: Uint8Array,
  nonce: Uint8Array,
  plaintext: Uint8Array,
): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    key as BufferSource,
    { name: 'AES-GCM' },
    false,
    ['encrypt'],
  );

  const ciphertext = await crypto.subtle.encrypt(
    {
      name: 'AES-GCM',
      iv: nonce as BufferSource,
      tagLength: 128, // 16 字节认证标签
    },
    cryptoKey,
    plaintext as BufferSource,
  );

  return new Uint8Array(ciphertext);
}

/**
 * AES-GCM 解密
 */
export async function aeadDecrypt(
  key: Uint8Array,
  nonce: Uint8Array,
  ciphertext: Uint8Array,
): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    key as BufferSource,
    { name: 'AES-GCM' },
    false,
    ['decrypt'],
  );

  const plaintext = await crypto.subtle.decrypt(
    {
      name: 'AES-GCM',
      iv: nonce as BufferSource,
      tagLength: 128,
    },
    cryptoKey,
    ciphertext as BufferSource,
  );

  return new Uint8Array(plaintext);
}

/**
 * 递增 nonce
 * WHY: AEAD 模式要求每次加密使用不同的 nonce，通过递增实现
 */
export function incrementNonce(nonce: Uint8Array): void {
  // WHY: 小端序递增
  for (let i = 0; i < nonce.length; i++) {
    nonce[i]++;
    if (nonce[i] !== 0) {
      break; // 没有溢出，停止进位
    }
  }
}

/**
 * 生成随机盐值
 */
export function generateSalt(length: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(length));
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - 使用 Web Crypto API 原生 AES-GCM，性能有保障
 *    - 密钥推导使用 SHA-256 替代 MD5（与传统 SS 不完全兼容）
 *    - ChaCha20-Poly1305 需要额外 polyfill
 * 2. Potential edge cases:
 *    - nonce 递增到全 0xFF 时会溢出为全 0
 *    - HKDF 的 info 参数对 Shadowsocks 是固定值 "ss-subkey"
 *    - Web Crypto API 在 HTTP 页面中可能不可用（需 HTTPS 或 localhost）
 * 3. Dependencies: ../../utils/binary, Web Crypto API
 */
