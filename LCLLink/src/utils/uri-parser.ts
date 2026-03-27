/**
 * __ai_context__: 代理协议 URI 解析器。
 * 支持解析 vless://, trojan://, ss:// 格式的分享链接为 ServerConfig。
 *
 * URI 格式参考：
 * - VLESS: vless://uuid@host:port?type=ws&security=tls&sni=xxx&path=/ws#name
 * - Trojan: trojan://password@host:port?type=ws&security=tls&sni=xxx&path=/ws#name
 * - SS: ss://base64(method:password)@host:port#name
 * - SS (SIP002): ss://base64(method:password)@host:port?plugin=v2ray-plugin;tls;path=/ws#name
 */

import {
  ProtocolType,
  TransportType,
  type ServerConfig,
  type VlessSpecificConfig,
  type TrojanSpecificConfig,
  type ShadowsocksSpecificConfig,
  type ShadowsocksMethod,
  type TlsConfig,
  type WebSocketConfig,
  type RealityConfig,
} from '../core/config';

// ============================================================
// 解析结果
// ============================================================
export interface ParseResult {
  success: boolean;
  config?: ServerConfig;
  error?: string;
}

// ============================================================
// 主解析入口
// ============================================================

/**
 * 解析代理 URI 字符串为 ServerConfig
 * WHY: 统一入口，根据协议前缀分发到各自的解析函数
 */
export function parseUri(uri: string): ParseResult {
  const trimmed = uri.trim();

  if (trimmed.startsWith('vless://')) {
    return parseVlessUri(trimmed);
  }

  if (trimmed.startsWith('trojan://')) {
    return parseTrojanUri(trimmed);
  }

  if (trimmed.startsWith('ss://')) {
    return parseShadowsocksUri(trimmed);
  }

  return {
    success: false,
    error: `不支持的 URI 格式。支持的协议：vless://, trojan://, ss://`,
  };
}

/**
 * 批量解析多行 URI（每行一个）
 * WHY: 用户可能一次粘贴多个链接
 */
export function parseMultipleUris(text: string): ParseResult[] {
  const lines = text
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('#'));

  return lines.map(parseUri);
}

// ============================================================
// VLESS URI 解析
// 支持两种格式：
//   标准: vless://uuid@host:port?type=ws&security=tls&sni=xxx#name
//   非标准: vless://base64_or_raw?remarks=name&tls=1&peer=sni&xtls=2&pbk=xxx&sid=xxx
// ============================================================

function parseVlessUri(uri: string): ParseResult {
  try {
    // Step 1: 提取 fragment（名称，标准格式用 #name）
    const [mainPart, fragment] = splitFragment(uri);

    // Step 2: 移除协议前缀
    const withoutScheme = mainPart.replace('vless://', '');

    // Step 3: 分离主体和查询参数
    const [body, queryString] = splitQuery(withoutScheme);
    const params = parseQueryParams(queryString);

    // Step 4: 判断格式 — 有 @ 是标准格式，无 @ 是非标准格式
    const atIndex = body.indexOf('@');

    let uuid: string;
    let host: string;
    let port: number;

    if (atIndex !== -1) {
      // ===== 标准格式: uuid@host:port =====
      uuid = body.substring(0, atIndex);
      const hostPort = body.substring(atIndex + 1);
      const parsed = parseHostPort(hostPort);
      host = parsed.host;
      port = parsed.port;
    } else {
      // ===== 非标准格式: 无 @ 分隔符 =====
      // WHY: 某些面板（如 x-ui, 3x-ui, ShadowRocket）生成的链接
      //       将 uuid:host:port 直接拼接或 Base64 编码

      // 尝试方案 1: Base64 解码后查找 @
      const decoded = tryBase64Decode(body);
      if (decoded) {
        const decodedAt = decoded.indexOf('@');
        if (decodedAt !== -1) {
          uuid = decoded.substring(0, decodedAt);
          const parsed = parseHostPort(decoded.substring(decodedAt + 1));
          host = parsed.host;
          port = parsed.port;
        } else {
          // Base64 解码成功但仍无 @，尝试按冒号分割
          const parts = splitColonParts(decoded);
          uuid = parts.uuid;
          host = parts.host;
          port = parts.port;
        }
      } else {
        // 尝试方案 2: 直接按冒号分割（可能是 uuid:host:port 格式）
        const parts = splitColonParts(body);
        uuid = parts.uuid;
        host = parts.host;
        port = parts.port;
      }
    }

    // Step 5: 提取节点名称
    // WHY: 标准用 #fragment，非标准用 remarks 查询参数
    const name = fragment
      ? decodeURIComponent(fragment)
      : (params.get('remarks') || params.get('name') || '未命名');

    // Step 6: 判断 TLS/安全模式
    // WHY: 非标准格式使用 tls=1 和 xtls=2 而非 security=tls/reality
    const security = resolveSecurityType(params);
    const tls = buildTlsConfig(security, params, host);

    // Step 7: 构建 WebSocket 配置
    const websocket = buildWebSocketConfig(params, host);

    // Step 8: 判断 flow（XTLS 模式）
    // WHY: 非标准格式使用 xtls=2 表示 xtls-rprx-vision
    const flow = resolveFlow(params);

    // Step 9: 构建 Reality 配置
    const reality: RealityConfig = {
      enabled: security === 'reality' || params.has('pbk'),
      publicKey: params.get('pbk') || '',
      shortId: params.get('sid') || '',
      spiderX: params.get('spx') || '',
    };

    const config: ServerConfig = {
      id: crypto.randomUUID(),
      name,
      protocol: ProtocolType.VLESS,
      address: host,
      port,
      transport: TransportType.WEBSOCKET,
      tls,
      websocket,
      protocolConfig: {
        uuid,
        encryption: params.get('encryption') || 'none',
        flow,
        reality,
      } satisfies VlessSpecificConfig,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      latency: -1,
    };

    return { success: true, config };
  } catch (error) {
    return { success: false, error: `VLESS URI 解析失败: ${(error as Error).message}` };
  }
}

/**
 * 解析安全类型
 * WHY: 标准用 security=tls，非标准用 tls=1, tls=0
 */
function resolveSecurityType(params: Map<string, string>): string {
  // 标准参数优先
  if (params.has('security')) {
    return params.get('security')!;
  }

  // 非标准参数: tls=1 表示 TLS 开启
  const tlsParam = params.get('tls');
  if (tlsParam === '1') {
    // WHY: 如果有 pbk 参数说明是 Reality 模式
    if (params.has('pbk')) {
      return 'reality';
    }
    return 'tls';
  }

  return 'none';
}

/**
 * 解析 flow 字段
 * WHY: 标准用 flow=xtls-rprx-vision，非标准用 xtls=2
 * xtls=1 → xtls-rprx-direct, xtls=2 → xtls-rprx-vision
 */
function resolveFlow(params: Map<string, string>): string {
  if (params.has('flow')) {
    return params.get('flow')!;
  }

  const xtls = params.get('xtls');
  if (xtls === '2') return 'xtls-rprx-vision';
  if (xtls === '1') return 'xtls-rprx-direct';

  return '';
}

/**
 * 尝试 Base64 解码（不抛出异常）
 */
function tryBase64Decode(str: string): string | null {
  try {
    return safeBase64Decode(str);
  } catch {
    return null;
  }
}

/**
 * 按冒号分割 uuid:host:port 格式
 * WHY: 某些非标准 URI 使用冒号分隔而非 @ 分隔
 *
 * UUID 格式为 xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx（36字符含连字符）
 * 也可能是无连字符的 32 字符 hex
 */
function splitColonParts(str: string): { uuid: string; host: string; port: number } {
  // 尝试匹配 UUID 格式（有连字符，36 字符）
  const uuidRegex = /^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/;
  const uuidMatch = str.match(uuidRegex);

  if (uuidMatch) {
    const uuid = uuidMatch[1];
    // UUID 后面应该是 :host:port 或 @host:port
    const remaining = str.substring(uuid.length);

    // 跳过分隔符（: 或 @）
    const sep = remaining.charAt(0);
    if (sep === ':' || sep === '@') {
      const hostPort = remaining.substring(1);
      const parsed = parseHostPort(hostPort);
      return { uuid, host: parsed.host, port: parsed.port };
    }
  }

  // 尝试无连字符 UUID（32 字符 hex）
  const hexUuidRegex = /^([0-9a-fA-F]{32})/;
  const hexMatch = str.match(hexUuidRegex);

  if (hexMatch) {
    const rawHex = hexMatch[1];
    // 格式化为标准 UUID
    const uuid = [
      rawHex.substring(0, 8),
      rawHex.substring(8, 12),
      rawHex.substring(12, 16),
      rawHex.substring(16, 20),
      rawHex.substring(20, 32),
    ].join('-');

    const remaining = str.substring(32);
    const sep = remaining.charAt(0);
    if (sep === ':' || sep === '@') {
      const hostPort = remaining.substring(1);
      const parsed = parseHostPort(hostPort);
      return { uuid, host: parsed.host, port: parsed.port };
    }
  }

  throw new Error('无法从 URI 中提取 UUID、主机和端口（缺少 @ 分隔符，且无法识别为 Base64 或 uuid:host:port 格式）');
}

// ============================================================
// Trojan URI 解析
// 格式: trojan://password@host:port?params#name
// ============================================================

function parseTrojanUri(uri: string): ParseResult {
  try {
    const [mainPart, fragment] = splitFragment(uri);
    const name = fragment ? decodeURIComponent(fragment) : '未命名';

    const withoutScheme = mainPart.replace('trojan://', '');

    const atIndex = withoutScheme.indexOf('@');
    if (atIndex === -1) {
      return { success: false, error: 'Trojan URI 缺少 @ 分隔符' };
    }

    const password = decodeURIComponent(withoutScheme.substring(0, atIndex));
    const remaining = withoutScheme.substring(atIndex + 1);

    const [hostPort, queryString] = splitQuery(remaining);
    const { host, port } = parseHostPort(hostPort);

    const params = parseQueryParams(queryString);
    const security = params.get('security') || 'tls';
    const tls = buildTlsConfig(security, params, host);
    const websocket = buildWebSocketConfig(params, host);

    const config: ServerConfig = {
      id: crypto.randomUUID(),
      name,
      protocol: ProtocolType.TROJAN,
      address: host,
      port,
      transport: TransportType.WEBSOCKET,
      tls,
      websocket,
      protocolConfig: {
        password,
      } satisfies TrojanSpecificConfig,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      latency: -1,
    };

    return { success: true, config };
  } catch (error) {
    return { success: false, error: `Trojan URI 解析失败: ${(error as Error).message}` };
  }
}

// ============================================================
// Shadowsocks URI 解析
// 格式 1 (Legacy): ss://base64(method:password)@host:port#name
// 格式 2 (SIP002): ss://base64(method:password)@host:port?plugin=...#name
// ============================================================

function parseShadowsocksUri(uri: string): ParseResult {
  try {
    const [mainPart, fragment] = splitFragment(uri);
    const name = fragment ? decodeURIComponent(fragment) : '未命名';

    const withoutScheme = mainPart.replace('ss://', '');

    let method: string;
    let password: string;
    let host: string;
    let port: number;
    let queryString = '';

    // WHY: SS URI 有两种格式，需要分别处理
    const atIndex = withoutScheme.indexOf('@');

    if (atIndex !== -1) {
      // SIP002 格式: base64(method:password)@host:port?plugin=...
      const userInfo = withoutScheme.substring(0, atIndex);
      const decoded = safeBase64Decode(userInfo);
      const colonIdx = decoded.indexOf(':');

      if (colonIdx === -1) {
        return { success: false, error: 'SS URI 用户信息格式无效（缺少 method:password）' };
      }

      method = decoded.substring(0, colonIdx);
      password = decoded.substring(colonIdx + 1);

      const remaining = withoutScheme.substring(atIndex + 1);
      const parts = splitQuery(remaining);
      const parsed = parseHostPort(parts[0]);
      host = parsed.host;
      port = parsed.port;
      queryString = parts[1];
    } else {
      // Legacy 格式: base64(method:password@host:port)
      const decoded = safeBase64Decode(withoutScheme);
      const atIdx = decoded.indexOf('@');

      if (atIdx === -1) {
        return { success: false, error: 'SS URI 格式无效（解码后缺少 @）' };
      }

      const userPart = decoded.substring(0, atIdx);
      const hostPart = decoded.substring(atIdx + 1);

      const colonIdx = userPart.indexOf(':');
      if (colonIdx === -1) {
        return { success: false, error: 'SS URI 用户信息格式无效' };
      }

      method = userPart.substring(0, colonIdx);
      password = userPart.substring(colonIdx + 1);

      const parsed = parseHostPort(hostPart);
      host = parsed.host;
      port = parsed.port;
    }

    // 解析插件参数（WebSocket 配置）
    const params = parseQueryParams(queryString);
    const websocket = buildWebSocketConfigFromSsPlugin(params);

    // WHY: 判断是否为 SS-2022
    const isSs2022 = method.startsWith('2022-');
    const protocol = isSs2022 ? ProtocolType.SHADOWSOCKS_2022 : ProtocolType.SHADOWSOCKS;

    const config: ServerConfig = {
      id: crypto.randomUUID(),
      name,
      protocol,
      address: host,
      port,
      transport: TransportType.WEBSOCKET,
      tls: {
        enabled: false,
        serverName: host,
        allowInsecure: false,
        alpn: [],
        fingerprint: 'chrome',
      },
      websocket,
      protocolConfig: {
        method: method as ShadowsocksMethod,
        password,
      } satisfies ShadowsocksSpecificConfig,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      latency: -1,
    };

    return { success: true, config };
  } catch (error) {
    return { success: false, error: `SS URI 解析失败: ${(error as Error).message}` };
  }
}

// ============================================================
// 工具函数
// ============================================================

/**
 * 分离 URI 的 fragment（#之后的部分）
 */
function splitFragment(uri: string): [string, string] {
  const hashIndex = uri.indexOf('#');
  if (hashIndex === -1) return [uri, ''];
  return [uri.substring(0, hashIndex), uri.substring(hashIndex + 1)];
}

/**
 * 分离查询字符串（?之后的部分）
 */
function splitQuery(str: string): [string, string] {
  const qIndex = str.indexOf('?');
  if (qIndex === -1) return [str, ''];
  return [str.substring(0, qIndex), str.substring(qIndex + 1)];
}

/**
 * 解析 host:port
 * WHY: 需要处理 IPv6 地址的方括号格式 [::1]:443
 */
function parseHostPort(hostPort: string): { host: string; port: number } {
  let host: string;
  let portStr: string;

  if (hostPort.startsWith('[')) {
    // IPv6: [host]:port
    const closeIdx = hostPort.indexOf(']');
    host = hostPort.substring(1, closeIdx);
    portStr = hostPort.substring(closeIdx + 2); // skip ]:
  } else {
    const lastColon = hostPort.lastIndexOf(':');
    host = hostPort.substring(0, lastColon);
    portStr = hostPort.substring(lastColon + 1);
  }

  const port = parseInt(portStr, 10);
  if (isNaN(port) || port < 1 || port > 65535) {
    throw new Error(`无效端口: ${portStr}`);
  }

  return { host, port };
}

/**
 * 解析查询参数为 Map
 */
function parseQueryParams(queryString: string): Map<string, string> {
  const params = new Map<string, string>();
  if (!queryString) return params;

  for (const pair of queryString.split('&')) {
    const eqIdx = pair.indexOf('=');
    if (eqIdx === -1) {
      params.set(pair, '');
    } else {
      const key = pair.substring(0, eqIdx);
      const value = decodeURIComponent(pair.substring(eqIdx + 1));
      params.set(key, value);
    }
  }

  return params;
}

/**
 * 构建 TLS 配置
 */
function buildTlsConfig(
  security: string,
  params: Map<string, string>,
  defaultHost: string,
): TlsConfig {
  const tlsEnabled = security === 'tls' || security === 'reality';
  return {
    enabled: tlsEnabled,
    serverName: params.get('sni') || params.get('peer') || defaultHost,
    allowInsecure: params.get('allowInsecure') === '1',
    alpn: params.get('alpn') ? params.get('alpn')!.split(',') : ['h2', 'http/1.1'],
    fingerprint: params.get('fp') || 'chrome',
  };
}

/**
 * 构建 WebSocket 配置
 */
function buildWebSocketConfig(
  params: Map<string, string>,
  defaultHost: string,
): WebSocketConfig {
  return {
    path: params.get('path') || '/',
    headers: {
      Host: params.get('host') || defaultHost,
    },
    maxEarlyData: parseInt(params.get('ed') || '0', 10),
    earlyDataHeaderName: params.get('eh') || '',
  };
}

/**
 * 从 SS plugin 参数构建 WebSocket 配置
 * WHY: SS 的 WebSocket 配置通过 plugin 参数传递，格式不同于 VLESS/Trojan
 */
function buildWebSocketConfigFromSsPlugin(
  params: Map<string, string>,
): WebSocketConfig {
  const plugin = params.get('plugin') || '';
  // WHY: plugin 格式如 "v2ray-plugin;tls;path=/ws;host=example.com"
  const pluginOpts = new Map<string, string>();

  if (plugin) {
    for (const part of plugin.split(';')) {
      const eqIdx = part.indexOf('=');
      if (eqIdx === -1) {
        pluginOpts.set(part, 'true');
      } else {
        pluginOpts.set(part.substring(0, eqIdx), part.substring(eqIdx + 1));
      }
    }
  }

  return {
    path: pluginOpts.get('path') || '/',
    headers: pluginOpts.get('host') ? { Host: pluginOpts.get('host')! } : {},
    maxEarlyData: 0,
    earlyDataHeaderName: '',
  };
}

/**
 * 安全的 Base64 解码
 * WHY: SS URI 可能使用标准 Base64 或 URL-safe Base64
 */
function safeBase64Decode(encoded: string): string {
  // 将 URL-safe Base64 转为标准 Base64
  let standard = encoded
    .replace(/-/g, '+')
    .replace(/_/g, '/');

  // 补齐 padding
  const paddingNeeded = (4 - (standard.length % 4)) % 4;
  standard += '='.repeat(paddingNeeded);

  return atob(standard);
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - VLESS URI 遵循 XTLS/Xray-core 的标准格式
 *    - Trojan URI 遵循 trojan-go 的格式
 *    - SS URI 支持 Legacy 和 SIP002 两种格式
 *    - 所有 URI 的 fragment 部分（#后面）为节点名称
 * 2. Potential edge cases:
 *    - UUID 可能包含大小写混合
 *    - SS password 可能包含特殊字符（需要 URL 解码）
 *    - IPv6 地址需要方括号格式
 *    - 某些客户端生成的 URI 可能不完全符合标准
 * 3. Dependencies: ../core/config（类型定义）
 */
