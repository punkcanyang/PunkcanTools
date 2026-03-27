/**
 * __ai_context__: Trojan 协议类型定义。
 */

/**
 * Trojan 命令类型
 */
export enum TrojanCommand {
  /** TCP 连接 */
  CONNECT = 0x01,
  /** UDP ASSOCIATE */
  UDP_ASSOCIATE = 0x03,
}

/**
 * Trojan 地址类型（与 SOCKS5 相同）
 */
export enum TrojanAddressType {
  IPV4 = 0x01,
  DOMAIN = 0x03,
  IPV6 = 0x04,
}

/**
 * [For Future AI]
 * 1. Key assumptions: Trojan 头部格式兼容 SOCKS5 地址编码
 * 2. Potential edge cases: 无
 * 3. Dependencies: 无
 */
