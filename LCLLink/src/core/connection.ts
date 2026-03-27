/**
 * __ai_context__: WebSocket 连接管理与 Service Worker 保活模块。
 * 处理 WebSocket 连接的建立、心跳、重连，以及防止 Service Worker 休眠。
 * 这是 Chrome Extension MV3 环境下维持长连接的关键模块。
 */

// ============================================================
// 连接管理器配置
// ============================================================
interface ConnectionManagerConfig {
  /** 心跳间隔（毫秒），默认 25 秒 */
  heartbeatInterval: number;
  /** 重连间隔（毫秒），默认 3 秒 */
  reconnectInterval: number;
  /** 最大重连次数，默认 5 */
  maxReconnectAttempts: number;
  /** Service Worker 保活 alarm 间隔（秒），默认 25 秒 */
  keepAliveIntervalSec: number;
}

const DEFAULT_CONFIG: ConnectionManagerConfig = {
  heartbeatInterval: 25_000,
  reconnectInterval: 3_000,
  maxReconnectAttempts: 5,
  keepAliveIntervalSec: 25,
};

// ============================================================
// 保活 Alarm 名称常量
// ============================================================
const KEEP_ALIVE_ALARM_NAME = 'lcllink-keep-alive';

// ============================================================
// 连接管理器
// ============================================================
export class ConnectionManager {
  private ws: WebSocket | null = null;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private reconnectAttempts: number = 0;
  private config: ConnectionManagerConfig;
  private shouldReconnect: boolean = false;
  private currentUrl: string = '';

  /** 连接成功回调 */
  onConnected: (() => void) | null = null;
  /** 连接断开回调 */
  onDisconnected: ((reason: string) => void) | null = null;
  /** 数据接收回调 */
  onMessage: ((data: ArrayBuffer) => void) | null = null;
  /** 错误回调 */
  onError: ((error: Event) => void) | null = null;

  constructor(config: Partial<ConnectionManagerConfig> = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  /**
   * 建立 WebSocket 连接
   * WHY: 将 WebSocket URL 构建和连接逻辑集中管理
   */
  async connect(url: string): Promise<void> {
    this.currentUrl = url;
    this.shouldReconnect = true;
    this.reconnectAttempts = 0;

    await this.createConnection();
    await this.startKeepAlive();
  }

  /**
   * 断开连接并清理所有资源
   */
  async disconnect(): Promise<void> {
    this.shouldReconnect = false;
    this.stopHeartbeat();
    await this.stopKeepAlive();

    if (this.ws) {
      this.ws.onclose = null; // WHY: 避免触发自动重连
      this.ws.close(1000, 'User disconnect');
      this.ws = null;
    }

    this.onDisconnected?.('User disconnect');
  }

  /**
   * 发送二进制数据
   */
  send(data: ArrayBuffer): boolean {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return false;
    }
    this.ws.send(data);
    return true;
  }

  /**
   * 当前连接是否活跃
   */
  get isConnected(): boolean {
    return this.ws !== null && this.ws.readyState === WebSocket.OPEN;
  }

  // ============================================================
  // 私有方法
  // ============================================================

  /**
   * 创建 WebSocket 连接实例
   */
  private async createConnection(): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      try {
        this.ws = new WebSocket(this.currentUrl);
        this.ws.binaryType = 'arraybuffer';

        this.ws.onopen = () => {
          this.reconnectAttempts = 0;
          this.startHeartbeat();
          this.onConnected?.();
          resolve();
        };

        this.ws.onmessage = (event: MessageEvent) => {
          if (event.data instanceof ArrayBuffer) {
            this.onMessage?.(event.data);
          }
        };

        this.ws.onclose = (event: CloseEvent) => {
          this.stopHeartbeat();
          const reason = event.reason || `Code: ${event.code}`;

          if (this.shouldReconnect) {
            this.attemptReconnect();
          } else {
            this.onDisconnected?.(reason);
          }
        };

        this.ws.onerror = (event: Event) => {
          this.onError?.(event);
          reject(new Error('WebSocket connection failed'));
        };
      } catch (error) {
        reject(error);
      }
    });
  }

  /**
   * 尝试自动重连
   * WHY: 网络不稳定时自动恢复连接，提升用户体验
   */
  private async attemptReconnect(): Promise<void> {
    if (this.reconnectAttempts >= this.config.maxReconnectAttempts) {
      this.shouldReconnect = false;
      this.onDisconnected?.('Max reconnect attempts reached');
      return;
    }

    this.reconnectAttempts++;

    // WHY: 使用指数退避策略避免服务端过载
    const delay = this.config.reconnectInterval * Math.pow(1.5, this.reconnectAttempts - 1);

    await new Promise((resolve) => setTimeout(resolve, delay));

    if (this.shouldReconnect) {
      try {
        await this.createConnection();
      } catch {
        // WHY: 重连失败会在 onclose 中再次触发 attemptReconnect
      }
    }
  }

  /**
   * 启动心跳定时器
   * WHY: WebSocket 需要定期发送数据防止连接被中间设备断开
   */
  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        // WHY: 发送空的 ping 帧保持连接活跃
        this.ws.send(new ArrayBuffer(0));
      }
    }, this.config.heartbeatInterval);
  }

  /**
   * 停止心跳定时器
   */
  private stopHeartbeat(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  /**
   * 启动 Service Worker 保活 Alarm
   * WHY: Chrome MV3 的 Service Worker 会在 30 秒无活动后休眠，
   *      使用 chrome.alarms API 定期唤醒，防止 WebSocket 连接丢失
   */
  private async startKeepAlive(): Promise<void> {
    await chrome.alarms.create(KEEP_ALIVE_ALARM_NAME, {
      periodInMinutes: this.config.keepAliveIntervalSec / 60,
    });
  }

  /**
   * 停止 Service Worker 保活 Alarm
   */
  private async stopKeepAlive(): Promise<void> {
    await chrome.alarms.clear(KEEP_ALIVE_ALARM_NAME);
  }
}

/**
 * 初始化 Alarm 监听（在 Service Worker 中调用）
 * WHY: Alarm 触发时 Service Worker 会被唤醒，保持 WebSocket 连接
 */
export function initKeepAliveListener(): void {
  chrome.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === KEEP_ALIVE_ALARM_NAME) {
      // WHY: Alarm 回调本身就会让 Service Worker 保持活跃
      // 不需要额外操作，但可以在这里检查连接状态
      console.debug('[LCLLink] Keep-alive alarm triggered');
    }
  });
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - Chrome 116+ 支持 Service Worker 中的 WebSocket
 *    - chrome.alarms 最小间隔为 1 分钟（但实际可能会被调整）
 *    - WebSocket 心跳使用空 ArrayBuffer
 * 2. Potential edge cases:
 *    - chrome.alarms 的最小间隔限制可能导致 25 秒间隔不生效
 *    - Service Worker 在某些情况下仍可能被杀死
 *    - 指数退避的重连延迟可能累计到很大的值
 * 3. Dependencies: chrome.alarms API（需要 manifest 中声明 alarms 权限）
 */
