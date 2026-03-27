/**
 * __ai_context__: VLESS 协议头部构建与解析模块。
 * 负责将 VLESS 请求参数序列化为二进制帧，以及从二进制数据中解析响应。
 */

import { uuidToBytes } from '../../utils/uuid';
import { concatBuffers, uint16ToBuffer, stringToBuffer } from '../../utils/binary';
import { assert } from '../../utils/binary';
import {
  VLESS_VERSION,
  VlessCommand,
  VlessAddressType,
  type VlessRequestHeader,
} from './types';

/**
 * 构建 VLESS 请求头部的二进制数据
 *
 * WHY: 将结构化的请求参数转为 VLESS 协议规定的二进制格式
 *
 * 二进制格式：
 * [1B version] [16B uuid] [1B addOnLen] [addOn...] [1B cmd] [2B port] [1B addrType] [address...]
 */
export function buildRequestHeader(
  uuidStr: string,
  command: VlessCommand,
  targetAddress: string,
  targetPort: number,
): ArrayBuffer {
  // Step 1: 版本号（1 字节）
  const versionBuf = new Uint8Array([VLESS_VERSION]).buffer;

  // Step 2: UUID（16 字节）
  const uuidBytes = uuidToBytes(uuidStr);
  const uuidBuf = uuidBytes.buffer as ArrayBuffer;

  // Step 3: AddOn 长度（1 字节，当前为 0）
  // WHY: VLESS 协议预留的扩展字段，目前不使用
  const addOnLenBuf = new Uint8Array([0]).buffer;

  // Step 4: 命令类型（1 字节）
  const commandBuf = new Uint8Array([command]).buffer;

  // Step 5: 目标端口（2 字节，大端序）
  const portBuf = uint16ToBuffer(targetPort);

  // Step 6: 地址类型 + 地址
  const addressBuf = encodeAddress(targetAddress);

  return concatBuffers(
    versionBuf,
    uuidBuf,
    addOnLenBuf,
    commandBuf,
    portBuf,
    addressBuf,
  );
}

/**
 * 编码目标地址为 VLESS 格式
 *
 * WHY: 根据地址类型（IPv4/域名/IPv6）使用不同的编码方式
 */
function encodeAddress(address: string): ArrayBuffer {
  // 判断是否为 IPv4
  const ipv4Regex = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
  const ipv4Match = address.match(ipv4Regex);

  if (ipv4Match) {
    // IPv4: [类型 1B] [4B 地址]
    const typeBuf = new Uint8Array([VlessAddressType.IPV4]);
    const addrBuf = new Uint8Array([
      parseInt(ipv4Match[1]),
      parseInt(ipv4Match[2]),
      parseInt(ipv4Match[3]),
      parseInt(ipv4Match[4]),
    ]);
    return concatBuffers(typeBuf.buffer as ArrayBuffer, addrBuf.buffer as ArrayBuffer);
  }

  // 判断是否为 IPv6
  if (address.includes(':')) {
    // IPv6: [类型 1B] [16B 地址]
    const typeBuf = new Uint8Array([VlessAddressType.IPV6]);
    const addrBuf = parseIPv6(address);
    return concatBuffers(typeBuf.buffer as ArrayBuffer, addrBuf.buffer as ArrayBuffer);
  }

  // 域名: [类型 1B] [长度 1B] [域名字符串]
  const domainBytes = new TextEncoder().encode(address);
  assert(domainBytes.length <= 255, `Domain name too long: ${address}`);

  const typeBuf = new Uint8Array([VlessAddressType.DOMAIN]);
  const lenBuf = new Uint8Array([domainBytes.length]);

  return concatBuffers(typeBuf.buffer as ArrayBuffer, lenBuf.buffer as ArrayBuffer, domainBytes.buffer as ArrayBuffer);
}

/**
 * 解析 IPv6 地址字符串为 16 字节 Uint8Array
 */
function parseIPv6(address: string): Uint8Array {
  // 移除可能的方括号
  const clean = address.replace(/^\[|\]$/g, '');
  const parts = clean.split(':');
  const result = new Uint8Array(16);

  // WHY: 处理 IPv6 的 :: 缩写形式
  let expandIndex = parts.indexOf('');
  if (expandIndex !== -1) {
    const before = parts.slice(0, expandIndex).filter(Boolean);
    const after = parts.slice(expandIndex + 1).filter(Boolean);
    const missing = 8 - before.length - after.length;

    let offset = 0;
    for (const part of before) {
      const value = parseInt(part, 16);
      result[offset++] = (value >> 8) & 0xff;
      result[offset++] = value & 0xff;
    }
    offset += missing * 2;
    for (const part of after) {
      const value = parseInt(part, 16);
      result[offset++] = (value >> 8) & 0xff;
      result[offset++] = value & 0xff;
    }
  } else {
    let offset = 0;
    for (const part of parts) {
      const value = parseInt(part, 16);
      result[offset++] = (value >> 8) & 0xff;
      result[offset++] = value & 0xff;
    }
  }

  return result;
}

/**
 * 解析 VLESS 响应头部
 * WHY: VLESS 响应头部非常简单：[1B version] [1B addOnLen] [addOn...]
 *
 * 返回实际数据开始的偏移量
 */
export function parseResponseHeader(data: ArrayBuffer): number {
  const view = new DataView(data);

  // 版本号检查
  const version = view.getUint8(0);
  assert(version === VLESS_VERSION, `Unexpected VLESS version: ${version}`);

  // AddOn 长度
  const addOnLength = view.getUint8(1);

  // 数据从 header 之后开始
  const headerLength = 2 + addOnLength;
  return headerLength;
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - VLESS 请求头只在连接建立时发送一次
 *    - 后续数据直接通过 WebSocket 透传
 *    - AddOn 字段当前实现中始终为空
 * 2. Potential edge cases:
 *    - IPv6 的 :: 缩写需要正确展开
 *    - 域名编码使用 UTF-8，非 ASCII 域名需要注意
 * 3. Dependencies: ../../utils/uuid, ../../utils/binary, ./types
 */
