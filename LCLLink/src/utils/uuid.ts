/**
 * __ai_context__: UUID 处理工具模块。
 * VLESS 协议需要将 UUID 字符串转为 16 字节的二进制数组。
 */

/**
 * 将标准 UUID 字符串（如 "550e8400-e29b-41d4-a716-446655440000"）转为 16 字节 Uint8Array
 * WHY: VLESS 协议头部使用 16 字节二进制格式的 UUID
 */
export function uuidToBytes(uuid: string): Uint8Array {
  // 移除所有连字符，得到 32 字符的十六进制字符串
  const hex = uuid.replace(/-/g, '');

  if (hex.length !== 32) {
    throw new Error(`Invalid UUID format: ${uuid}`);
  }

  const bytes = new Uint8Array(16);
  for (let i = 0; i < 16; i++) {
    bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  }

  return bytes;
}

/**
 * 将 16 字节 Uint8Array 转回标准 UUID 字符串
 * WHY: 从二进制数据中解析 UUID 便于日志和配置显示
 */
export function bytesToUuid(bytes: Uint8Array): string {
  if (bytes.length !== 16) {
    throw new Error(`Invalid UUID bytes length: ${bytes.length}, expected 16`);
  }

  const hex = Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  // WHY: UUID 格式为 8-4-4-4-12
  return [
    hex.substring(0, 8),
    hex.substring(8, 12),
    hex.substring(12, 16),
    hex.substring(16, 20),
    hex.substring(20, 32),
  ].join('-');
}

/**
 * 验证 UUID 格式是否正确
 */
export function isValidUuid(uuid: string): boolean {
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(uuid);
}

/**
 * 生成随机 UUID v4
 * WHY: 测试和配置生成时使用
 */
export function generateUuid(): string {
  return crypto.randomUUID();
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - UUID 格式遵循 RFC 4122
 *    - crypto.randomUUID() 在现代浏览器中可用
 * 2. Potential edge cases:
 *    - 大写/小写 hex 字符都应被接受
 *    - 无连字符的 UUID 不被 isValidUuid 接受（需完整格式）
 * 3. Dependencies: 无外部依赖
 */
