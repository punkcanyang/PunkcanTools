/**
 * __ai_context__: Service Worker 入口文件。
 * Chrome Extension MV3 的后台脚本，负责：
 * 1. 通过 Helper 管理协议连接（优先，支持所有协议）
 * 2. 回退到 WebSocket 直连（Phase1 兼容模式）
 * 3. 配置 chrome.proxy 规则
 * 4. 处理来自 Popup/Options 的消息
 * 5. 维持 Service Worker 保活
 */

import {
  ConnectionStatus,
  MessageAction,
  type AppState,
  type ExtensionMessage,
  type ExtensionResponse,
  type ServerConfig,
} from '../core/config';
import { getProtocol, type IConnection } from '../core/protocol';
import { ProxyManager } from '../core/proxy-manager';
import { initKeepAliveListener } from '../core/connection';
import { HelperClient, HelperStatus } from '../core/helper-client';
import { Logger } from '../utils/logger';

// WHY: 导入协议模块以触发自动注册（WebSocket 回退模式使用）
import '../protocols/vless/index';
import '../protocols/trojan/index';
import '../protocols/shadowsocks/index';

const logger = new Logger('ServiceWorker');
const proxyManager = new ProxyManager();
const helperClient = new HelperClient();

// ============================================================
// 全局状态
// ============================================================
let currentState: AppState = {
  status: ConnectionStatus.DISCONNECTED,
  activeServerId: null,
  errorMessage: '',
  connectedSince: null,
};

/** 当前分配的 Helper SOCKS5 端口（0 = 未使用 Helper） */
let helperProxyPort = 0;
/** WebSocket 回退连接 */
let activeConnection: IConnection | null = null;

// ============================================================
// 初始化
// ============================================================

// 初始化保活监听
initKeepAliveListener();

// 监听来自 Popup/Options 的消息
chrome.runtime.onMessage.addListener(
  (message: ExtensionMessage, _sender, sendResponse) => {
    // WHY: 使用 async IIFE 包装，因为 onMessage 需要同步返回 true 才能异步响应
    handleMessage(message)
      .then(sendResponse)
      .catch((error) => {
        sendResponse({
          success: false,
          error: (error as Error).message,
        } satisfies ExtensionResponse);
      });

    return true; // WHY: 返回 true 表示将异步发送响应
  },
);

// 安装时初始化存储
chrome.runtime.onInstalled.addListener(() => {
  logger.info('LCLLink extension installed');
  saveState();
});

logger.info('Service Worker started');

// ============================================================
// 消息处理
// ============================================================

async function handleMessage(message: ExtensionMessage): Promise<ExtensionResponse> {
  switch (message.action) {
    case MessageAction.CONNECT:
      return await handleConnect(message.payload as string);

    case MessageAction.DISCONNECT:
      return await handleDisconnect();

    case MessageAction.GET_STATUS:
      return {
        success: true,
        data: {
          ...currentState,
          helperPort: helperProxyPort,
        },
      };

    case MessageAction.PING:
      return await handlePing(message.payload as string);

    default:
      return {
        success: false,
        error: `Unknown action: ${message.action}`,
      };
  }
}

/**
 * 处理连接请求
 * WHY: 优先使用 Helper（支持所有协议），失败则回退到 WebSocket 直连
 *
 * 连接流程：
 *   1. 检查 Helper 是否运行
 *   2. 如果 Helper 可用 → 通过 HTTP API 创建 SOCKS5 代理实例
 *   3. 如果 Helper 不可用 → 尝试 WebSocket 直连（限 WebSocket 兼容协议）
 *   4. 配置 chrome.proxy 指向代理端口
 */
async function handleConnect(serverId: string): Promise<ExtensionResponse> {
  try {
    // Step 1: 更新状态为连接中
    updateState({
      status: ConnectionStatus.CONNECTING,
      activeServerId: serverId,
      errorMessage: '',
    });

    // Step 2: 获取服务器配置
    const server = await getServerConfig(serverId);
    if (!server) {
      throw new Error(`Server not found: ${serverId}`);
    }

    // Step 3: 断开已有连接
    await cleanupCurrentConnection();

    // Step 4: 尝试通过 Helper 连接（优先）
    const helperConnected = await tryConnectViaHelper(server);

    if (!helperConnected) {
      // Step 5: 回退到 WebSocket 直连
      logger.info('Helper 不可用，尝试 WebSocket 直连...');
      await connectViaWebSocket(server);
    }

    // Step 6: 更新状态为已连接
    updateState({
      status: ConnectionStatus.CONNECTED,
      connectedSince: Date.now(),
    });

    logger.info(`Connected to ${server.name} (${server.protocol})`);
    return { success: true };

  } catch (error) {
    const errorMsg = (error as Error).message;
    logger.error(`Connect failed: ${errorMsg}`);

    updateState({
      status: ConnectionStatus.ERROR,
      activeServerId: null,
      errorMessage: errorMsg,
      connectedSince: null,
    });

    return { success: false, error: errorMsg };
  }
}

/**
 * 通过 Helper 创建代理实例
 * WHY: Helper 使用 xray-core，支持 VLESS+Reality 等所有协议
 */
async function tryConnectViaHelper(server: ServerConfig): Promise<boolean> {
  try {
    // Step 1: 确保 Helper 运行
    const running = await helperClient.ensureRunning();
    if (!running) {
      logger.info('Helper 未运行或未安装');
      return false;
    }

    // Step 2: 创建代理实例
    const port = await helperClient.connect(server);
    helperProxyPort = port;

    // Step 3: 配置浏览器代理指向 Helper 分配的 SOCKS5 端口
    await proxyManager.setSocksProxy('127.0.0.1', port);

    logger.info(`通过 Helper 连接成功: SOCKS5 端口 ${port}`);
    return true;

  } catch (error) {
    logger.warn(`Helper 连接失败: ${(error as Error).message}`);
    helperProxyPort = 0;
    return false;
  }
}

/**
 * 通过 WebSocket 直连（回退模式）
 * WHY: Phase 1 兼容模式，仅支持 WS 传输的协议
 */
async function connectViaWebSocket(server: ServerConfig): Promise<void> {
  // Step 1: 获取协议实现
  const protocol = getProtocol(server.protocol);
  if (!protocol) {
    throw new Error(`Protocol not registered: ${server.protocol}`);
  }

  // Step 2: 验证配置
  const validation = protocol.validateConfig(server);
  if (!validation.valid) {
    const errorMsg = Object.values(validation.errors).join('; ');
    throw new Error(`Invalid config: ${errorMsg}`);
  }

  // Step 3: 建立连接
  activeConnection = await protocol.connect(server);

  // Step 4: 设置连接回调
  activeConnection.onClose = (reason) => {
    logger.warn(`WebSocket connection closed: ${reason}`);
    updateState({
      status: ConnectionStatus.DISCONNECTED,
      activeServerId: null,
      connectedSince: null,
    });
    proxyManager.clearProxy().catch((err) => {
      logger.error(`Failed to clear proxy: ${err}`);
    });
  };

  activeConnection.onError = (error) => {
    logger.error(`WebSocket connection error: ${error.message}`);
    updateState({
      status: ConnectionStatus.ERROR,
      errorMessage: error.message,
    });
  };

  // Step 5: 配置代理
  await proxyManager.setGlobalProxy('127.0.0.1', server.port);
}

/**
 * 处理断开连接请求
 */
async function handleDisconnect(): Promise<ExtensionResponse> {
  try {
    await cleanupCurrentConnection();

    updateState({
      status: ConnectionStatus.DISCONNECTED,
      activeServerId: null,
      errorMessage: '',
      connectedSince: null,
    });

    logger.info('Disconnected');
    return { success: true };
  } catch (error) {
    return { success: false, error: (error as Error).message };
  }
}

/**
 * 清理当前连接（Helper 或 WebSocket）
 */
async function cleanupCurrentConnection(): Promise<void> {
  // 清理 Helper 实例
  if (helperProxyPort > 0) {
    try {
      await helperClient.disconnect(helperProxyPort);
    } catch (error) {
      logger.warn(`Helper disconnect failed: ${(error as Error).message}`);
    }
    helperProxyPort = 0;
  }

  // 清理 WebSocket 连接
  if (activeConnection) {
    activeConnection.close();
    activeConnection = null;
  }

  await proxyManager.clearProxy();
}

/**
 * 处理 Ping 请求
 */
async function handlePing(serverId: string): Promise<ExtensionResponse> {
  try {
    const server = await getServerConfig(serverId);
    if (!server) {
      throw new Error(`Server not found: ${serverId}`);
    }

    const protocol = getProtocol(server.protocol);
    if (!protocol) {
      throw new Error(`Protocol not registered: ${server.protocol}`);
    }

    const latency = await protocol.ping(server);
    return { success: true, data: latency };
  } catch (error) {
    return { success: false, error: (error as Error).message };
  }
}

// ============================================================
// 辅助函数
// ============================================================

async function getServerConfig(serverId: string): Promise<ServerConfig | null> {
  const result = await chrome.storage.local.get('servers');
  const servers: ServerConfig[] = result.servers || [];
  return servers.find((s) => s.id === serverId) || null;
}

function updateState(partial: Partial<AppState>): void {
  currentState = { ...currentState, ...partial };
  saveState();

  // WHY: 广播状态变更，UI 层可以实时更新
  chrome.runtime.sendMessage({
    action: MessageAction.STATUS_CHANGED,
    payload: currentState,
  }).catch(() => {
    // WHY: 如果没有活跃的 Popup/Options 页面，发送会失败，静默忽略
  });
}

function saveState(): void {
  chrome.storage.local.set({ appState: currentState }).catch((err) => {
    logger.error(`Failed to save state: ${err}`);
  });
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - 连接优先使用 Helper（支持 VLESS+Reality 等原始 TCP 协议）
 *    - Helper 不可用时回退到 WebSocket 直连（仅 WS 兼容协议）
 *    - Helper 通过 SOCKS5 端口提供代理，chrome.proxy 指向该端口
 *    - helperProxyPort > 0 表示正在使用 Helper 连接
 * 2. Potential edge cases:
 *    - Helper 在连接期间崩溃（需要心跳检测）
 *    - Service Worker 重启后 helperProxyPort 状态丢失
 *    - 并发连接/断开请求的竞态
 * 3. Dependencies: helper-client, protocol, proxy-manager, connection, logger, 所有协议模块
 */
