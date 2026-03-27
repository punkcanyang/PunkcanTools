/**
 * __ai_context__: VLESS 协议类型定义。
 * 定义 VLESS 协议头部格式和相关常量。
 */

/**
 * VLESS 协议版本
 * WHY: 当前 VLESS 协议规范只定义了版本 0
 */
export const VLESS_VERSION = 0;

/**
 * VLESS 命令类型
 */
export enum VlessCommand {
  /** TCP 连接 */
  TCP = 0x01,
  /** UDP 连接 */
  UDP = 0x02,
  /** MUX 复用 */
  MUX = 0x03,
}

/**
 * VLESS 地址类型
 */
export enum VlessAddressType {
  /** IPv4 地址（4 字节） */
  IPV4 = 0x01,
  /** 域名（1 字节长度 + 域名字符串） */
  DOMAIN = 0x02,
  /** IPv6 地址（16 字节） */
  IPV6 = 0x03,
}

/**
 * VLESS 请求头部结构
 *
 * 格式：
 * ┌──────────┬──────────┬──────────┬──────────┬──────┬──────────┬─────────┐
 * │ Version  │  UUID    │ AddOn    │ Command  │ Port │ AddrType │ Address │
 * │ (1 byte) │(16 bytes)│ (N bytes)│ (1 byte) │(2 B) │ (1 byte) │ (N B)   │
 * └──────────┴──────────┴──────────┴──────────┴──────┴──────────┴─────────┘
 */
export interface VlessRequestHeader {
  /** 协议版本（固定为 0） */
  version: number;
  /** 用户 UUID（16 字节） */
  uuid: Uint8Array;
  /** 附加元数据长度 */
  addOnLength: number;
  /** 命令类型 */
  command: VlessCommand;
  /** 目标端口 */
  port: number;
  /** 地址类型 */
  addressType: VlessAddressType;
  /** 目标地址 */
  address: string;
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - VLESS 头部使用大端序
 *    - Version 目前固定为 0
 *    - AddOn 在当前实现中长度为 0
 * 2. Potential edge cases:
 *    - IPv6 地址解析需要 16 字节
 *    - 域名长度不能超过 255 字节
 * 3. Dependencies: 无
 */
