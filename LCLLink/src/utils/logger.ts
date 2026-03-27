/**
 * __ai_context__: 分级日志系统模块。
 * 提供 debug/info/warn/error 四个级别的日志，支持存储到 chrome.storage.local。
 * 日志用于调试协议连接问题。
 */

import { LogLevel, type LogEntry } from '../core/config';

// ============================================================
// 日志配置
// ============================================================
const MAX_LOG_ENTRIES = 500; // WHY: 限制存储空间，避免 storage 溢出
const LOG_STORAGE_KEY = 'logs';

// ============================================================
// Logger 类
// ============================================================
export class Logger {
  private source: string;
  private static activeLevel: LogLevel = LogLevel.INFO;

  /**
   * 创建一个带来源标签的 Logger 实例
   * WHY: 每个模块使用自己的 Logger 实例，方便追踪日志来源
   */
  constructor(source: string) {
    this.source = source;
  }

  /**
   * 设置全局日志级别
   */
  static setLevel(level: LogLevel): void {
    Logger.activeLevel = level;
  }

  debug(message: string): void {
    this.log(LogLevel.DEBUG, message);
  }

  info(message: string): void {
    this.log(LogLevel.INFO, message);
  }

  warn(message: string): void {
    this.log(LogLevel.WARN, message);
  }

  error(message: string): void {
    this.log(LogLevel.ERROR, message);
  }

  /**
   * 内部日志处理
   * WHY: 同时输出到 console 和 chrome.storage，双重记录
   */
  private log(level: LogLevel, message: string): void {
    // WHY: 级别过滤，避免 DEBUG 日志在生产环境堆积
    const levels = [LogLevel.DEBUG, LogLevel.INFO, LogLevel.WARN, LogLevel.ERROR];
    const activeIndex = levels.indexOf(Logger.activeLevel);
    const currentIndex = levels.indexOf(level);

    if (currentIndex < activeIndex) {
      return;
    }

    const entry: LogEntry = {
      timestamp: Date.now(),
      level,
      source: this.source,
      message,
    };

    // 输出到 console
    const prefix = `[LCLLink][${this.source}]`;
    switch (level) {
      case LogLevel.DEBUG:
        console.debug(prefix, message);
        break;
      case LogLevel.INFO:
        console.info(prefix, message);
        break;
      case LogLevel.WARN:
        console.warn(prefix, message);
        break;
      case LogLevel.ERROR:
        console.error(prefix, message);
        break;
    }

    // 异步存储到 chrome.storage.local
    this.persistLog(entry).catch((err) => {
      console.error('[LCLLink][Logger] Failed to persist log:', err);
    });
  }

  /**
   * 将日志存储到 chrome.storage.local
   * WHY: Service Worker 重启后可以读取历史日志
   */
  private async persistLog(entry: LogEntry): Promise<void> {
    try {
      const result = await chrome.storage.local.get(LOG_STORAGE_KEY);
      const logs: LogEntry[] = result[LOG_STORAGE_KEY] || [];

      logs.push(entry);

      // WHY: 超过上限时移除最旧的日志
      while (logs.length > MAX_LOG_ENTRIES) {
        logs.shift();
      }

      await chrome.storage.local.set({ [LOG_STORAGE_KEY]: logs });
    } catch {
      // WHY: 在非 Chrome Extension 环境（如测试）中静默失败
    }
  }

  /**
   * 读取所有存储的日志
   */
  static async getStoredLogs(): Promise<LogEntry[]> {
    try {
      const result = await chrome.storage.local.get(LOG_STORAGE_KEY);
      return result[LOG_STORAGE_KEY] || [];
    } catch {
      return [];
    }
  }

  /**
   * 清除所有存储的日志
   */
  static async clearLogs(): Promise<void> {
    try {
      await chrome.storage.local.remove(LOG_STORAGE_KEY);
    } catch {
      // 静默失败
    }
  }
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - chrome.storage.local 在 Service Worker 和 Popup 中都可用
 *    - 日志数量上限 500 条，足够调试但不会占用过多空间
 * 2. Potential edge cases:
 *    - 多个并发日志写入可能产生竞态条件（但影响很小）
 *    - 在非 Chrome Extension 环境中 chrome.storage 不可用
 * 3. Dependencies: ../core/config（LogLevel, LogEntry 类型）
 */
