/**
 * __ai_context__: 二进制数据处理工具模块。
 * 提供 ArrayBuffer/Uint8Array 的常用操作函数。
 * 协议解析和構建過程中頻繁使用。
 */

/**
 * 将多个 ArrayBuffer 合并为一个
 * WHY: 协议头部 + 数据载荷需要拼接为完整的二进制帧
 */
export function concatBuffers(...buffers: ArrayBuffer[]): ArrayBuffer {
  const totalLength = buffers.reduce((sum, buf) => sum + buf.byteLength, 0);
  const result = new Uint8Array(totalLength);
  let offset = 0;

  for (const buf of buffers) {
    result.set(new Uint8Array(buf), offset);
    offset += buf.byteLength;
  }

  return result.buffer;
}

/**
 * 将 16 位无符号整数写入大端序 ArrayBuffer
 * WHY: 网络协议使用大端序（Big-Endian）
 */
export function uint16ToBuffer(value: number): ArrayBuffer {
  const buffer = new ArrayBuffer(2);
  const view = new DataView(buffer);
  view.setUint16(0, value, false); // false = 大端序
  return buffer;
}

/**
 * 从 ArrayBuffer 读取大端序 16 位无符号整数
 */
export function bufferToUint16(buffer: ArrayBuffer, offset: number = 0): number {
  const view = new DataView(buffer);
  return view.getUint16(offset, false);
}

/**
 * 将字符串编码为 UTF-8 ArrayBuffer
 */
export function stringToBuffer(str: string): ArrayBuffer {
  return new TextEncoder().encode(str).buffer;
}

/**
 * 将 ArrayBuffer 解码为 UTF-8 字符串
 */
export function bufferToString(buffer: ArrayBuffer): string {
  return new TextDecoder().decode(buffer);
}

/**
 * 将 Uint8Array 转为十六进制字符串
 * WHY: 调试和日志输出时使用
 */
export function toHex(data: Uint8Array): string {
  return Array.from(data)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * 将十六进制字符串转为 Uint8Array
 */
export function fromHex(hex: string): Uint8Array {
  const cleanHex = hex.replace(/\s/g, '');
  assert(cleanHex.length % 2 === 0, 'Hex string must have even length');

  const bytes = new Uint8Array(cleanHex.length / 2);
  for (let i = 0; i < cleanHex.length; i += 2) {
    bytes[i / 2] = parseInt(cleanHex.substring(i, i + 2), 16);
  }
  return bytes;
}

/**
 * 防御性断言
 * WHY: 在关键逻辑节点做显式检查，帮助 AI 和开发者快速定位问题
 */
export function assert(condition: boolean, message: string): asserts condition {
  if (!condition) {
    throw new Error(`[LCLLink Assertion] ${message}`);
  }
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - 所有网络协议使用大端序（Big-Endian）
 *    - TextEncoder/TextDecoder 在所有现代浏览器中可用
 * 2. Potential edge cases:
 *    - concatBuffers 传入空数组时返回空 ArrayBuffer
 *    - fromHex 不验证字符是否为有效十六进制
 * 3. Dependencies: 无外部依赖
 */
