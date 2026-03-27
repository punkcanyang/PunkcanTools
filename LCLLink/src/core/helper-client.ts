/**
 * __ai_context__: Native Helper HTTP API 客户端。
 * 负责与本地 Go Helper 进程通信：
 *   - 健康检查（Helper 是否运行）
 *   - 通过 Native Messaging 自动启动 Helper
 *   - 请求创建/销毁 SOCKS5 代理实例
 * 这是 Chrome 扩展与 Helper 的唯一通信通道。
 */

import { Logger } from '../utils/logger';
import type { ServerConfig } from './config';

const logger = new Logger('HelperClient');

// ============================================================
// 常量
// ============================================================

/** Helper HTTP API 基础地址 */
const API_BASE = 'http://127.0.0.1:19527';
/** Native Messaging Host 名称（必须与 NM Host manifest 一致） */
const NM_HOST_NAME = 'com.punkcan.lcllink.helper';
/** 健康检查超时时间 */
const HEALTH_CHECK_TIMEOUT_MS = 2000;
/** 启动 Helper 后的等待时间 */
const STARTUP_WAIT_MS = 1500;
/** 启动 Helper 后最大重试次数 */
const STARTUP_MAX_RETRIES = 5;

// ============================================================
// 类型定义
// ============================================================

/** Helper 状态 */
export enum HelperStatus {
  /** 运行中，可以正常使用 */
  RUNNING = 'running',
  /** 未运行（需要启动） */
  NOT_RUNNING = 'not_running',
  /** 未安装（需要安装） */
  NOT_INSTALLED = 'not_installed',
  /** 检查中 */
  CHECKING = 'checking',
}

/** 代理实例信息 */
export interface ProxyInstance {
  port: number;
  server: ServerConfig;
  status: string;
  startedAt: number;
  error?: string;
}

/** Helper 状态响应 */
interface StatusResponse {
  instances: ProxyInstance[];
  version: string;
  uptime: number;
}

/** 连接响应 */
interface ConnectResponse {
  port: number;
}

// ============================================================
// HelperClient 类
// ============================================================

export class HelperClient {
  private nmPort: chrome.runtime.Port | null = null;

  // ============================================================
  // 健康检查
  // WHY: 在连接前先确认 Helper 是否可用
  // ============================================================

  /**
   * 检查 Helper 是否运行中
   */
  async checkHealth(): Promise<HelperStatus> {
    try {
      const response = await fetchWithTimeout(
        `${API_BASE}/api/health`,
        { method: 'GET' },
        HEALTH_CHECK_TIMEOUT_MS,
      );

      if (response.ok) {
        return HelperStatus.RUNNING;
      }

      return HelperStatus.NOT_RUNNING;
    } catch {
      // WHY: fetch 失败可能是 Helper 未运行或未安装
      return HelperStatus.NOT_RUNNING;
    }
  }

  // ============================================================
  // 启动 Helper
  // WHY: 通过 Chrome Native Messaging 自动启动 Helper 进程
  // ============================================================

  /**
   * 确保 Helper 正在运行
   * 如果未运行，尝试通过 NM 启动
   */
  async ensureRunning(): Promise<boolean> {
    // Step 1: 先检查是否已运行
    const status = await this.checkHealth();
    if (status === HelperStatus.RUNNING) {
      logger.info('Helper 已运行');
      return true;
    }

    // Step 2: 尝试通过 NM 启动
    logger.info('尝试启动 Helper...');

    try {
      this.startViaNativeMessaging();
    } catch (error) {
      logger.error(`NM 启动失败: ${(error as Error).message}`);
      return false;
    }

    // Step 3: 等待 Helper 启动并重试检查
    for (let i = 0; i < STARTUP_MAX_RETRIES; i++) {
      await sleep(STARTUP_WAIT_MS);

      const retryStatus = await this.checkHealth();
      if (retryStatus === HelperStatus.RUNNING) {
        logger.info(`Helper 启动成功 (尝试 ${i + 1})`);
        return true;
      }

      logger.info(`等待 Helper 启动... (${i + 1}/${STARTUP_MAX_RETRIES})`);
    }

    logger.error('Helper 启动超时');
    return false;
  }

  /**
   * 通过 Native Messaging 启动 Helper 进程
   * WHY: Chrome 会自动启动 NM Host 指定的可执行文件
   */
  private startViaNativeMessaging(): void {
    // 关闭之前的连接
    if (this.nmPort) {
      try { this.nmPort.disconnect(); } catch { /* ignore */ }
    }

    // WHY: connectNative 会让 Chrome 启动 NM Host 进程
    this.nmPort = chrome.runtime.connectNative(NM_HOST_NAME);

    this.nmPort.onDisconnect.addListener(() => {
      const error = chrome.runtime.lastError;
      if (error) {
        logger.warn(`NM 断开: ${error.message}`);
      }
      this.nmPort = null;
    });

    // 发送 ping 确认连接
    this.nmPort.postMessage({ action: 'ping' });
  }

  // ============================================================
  // 代理实例管理
  // ============================================================

  /**
   * 创建代理实例（连接到远端服务器）
   * WHY: 告诉 Helper 开一个 SOCKS5 端口连接指定服务器
   */
  async connect(server: ServerConfig, preferredPort?: number): Promise<number> {
    const body = {
      server,
      preferredPort: preferredPort || 0,
    };

    const response = await fetchJSON<ConnectResponse>(
      `${API_BASE}/api/connect`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      },
    );

    logger.info(`代理实例已创建: SOCKS5 端口 ${response.port}`);
    return response.port;
  }

  /**
   * 断开指定端口的代理实例
   */
  async disconnect(port: number): Promise<void> {
    await fetchJSON(
      `${API_BASE}/api/disconnect/${port}`,
      { method: 'DELETE' },
    );

    logger.info(`代理实例已断开: 端口 ${port}`);
  }

  /**
   * 获取所有运行中的实例状态
   */
  async getStatus(): Promise<StatusResponse> {
    return fetchJSON<StatusResponse>(
      `${API_BASE}/api/status`,
      { method: 'GET' },
    );
  }

  /**
   * 关闭 NM 连接
   */
  close(): void {
    if (this.nmPort) {
      try { this.nmPort.disconnect(); } catch { /* ignore */ }
      this.nmPort = null;
    }
  }
}

// ============================================================
// 工具函数
// ============================================================

/**
 * 带超时的 fetch
 */
async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, { ...init, signal: controller.signal });
    return response;
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * fetch + JSON 解析 + 错误处理
 */
async function fetchJSON<T>(url: string, init: RequestInit): Promise<T> {
  const response = await fetch(url, init);

  if (!response.ok) {
    const errorBody = await response.text();
    let errorMsg: string;

    try {
      const errorObj = JSON.parse(errorBody);
      errorMsg = errorObj.error || errorBody;
    } catch {
      errorMsg = errorBody;
    }

    throw new Error(`Helper API 错误 (${response.status}): ${errorMsg}`);
  }

  return response.json() as Promise<T>;
}

/**
 * 延迟
 */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - Helper 的 HTTP API 只监听 127.0.0.1:19527（本地安全）
 *    - NM Host 名称必须与 manifest 中的 name 字段一致
 *    - Chrome 会自动启动 NM Host 进程（connectNative）
 *    - Service Worker 重启后 nmPort 会丢失，需要重建
 * 2. Potential edge cases:
 *    - Helper 未安装时 connectNative 会立即触发 onDisconnect
 *    - 并发调用 ensureRunning 可能导致多次 NM 连接
 *    - Service Worker 休眠后 fetch 请求可能超时
 * 3. Dependencies: config（类型）, logger
 */
