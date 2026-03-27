/**
 * __ai_context__: chrome.proxy API 管理器。
 * 封装 Chrome 浏览器代理设置的所有操作。
 * 负责设置/清除代理规则，支持 PAC Script 模式实现按域名分流。
 */

// ============================================================
// 代理模式
// ============================================================
export enum ProxyMode {
  /** 直连（清除代理） */
  DIRECT = 'direct',
  /** 全局代理 */
  GLOBAL = 'global',
  /** PAC 脚本模式（按规则分流） */
  PAC = 'pac',
}

// ============================================================
// 代理管理器
// ============================================================
export class ProxyManager {
  private currentMode: ProxyMode = ProxyMode.DIRECT;

  /**
   * 设置全局 SOCKS5 代理
   * WHY: 所有浏览器流量都走代理服务器
   */
  async setGlobalProxy(host: string, port: number): Promise<void> {
    const config: chrome.proxy.ProxyConfig = {
      mode: 'fixed_servers',
      rules: {
        singleProxy: {
          scheme: 'socks5',
          host: host,
          port: port,
        },
        // WHY: 本地地址不走代理，避免死循环
        bypassList: [
          'localhost',
          '127.0.0.1',
          '::1',
          '10.0.0.0/8',
          '172.16.0.0/12',
          '192.168.0.0/16',
        ],
      },
    };

    await chrome.proxy.settings.set({
      value: config,
      scope: 'regular',
    });

    this.currentMode = ProxyMode.GLOBAL;
  }

  /**
   * 设置 SOCKS5 代理（Helper 模式专用）
   * WHY: Helper 分配的端口使用 SOCKS5 协议
   */
  async setSocksProxy(host: string, port: number): Promise<void> {
    return this.setGlobalProxy(host, port);
  }

  /**
   * 设置 PAC 脚本代理
   * WHY: 允许按域名规则决定是否走代理
   */
  async setPacProxy(
    proxyHost: string,
    proxyPort: number,
    proxyDomains: string[],
  ): Promise<void> {
    // WHY: 动态生成 PAC 脚本，将指定域名走代理，其余直连
    const domainConditions = proxyDomains
      .map((domain) => `dnsDomainIs(host, "${domain}")`)
      .join(' || ');

    const pacScript = `
      function FindProxyForURL(url, host) {
        if (${domainConditions || 'false'}) {
          return "SOCKS5 ${proxyHost}:${proxyPort}";
        }
        return "DIRECT";
      }
    `;

    const config: chrome.proxy.ProxyConfig = {
      mode: 'pac_script',
      pacScript: {
        data: pacScript,
      },
    };

    await chrome.proxy.settings.set({
      value: config,
      scope: 'regular',
    });

    this.currentMode = ProxyMode.PAC;
  }

  /**
   * 清除代理设置，恢复直连
   */
  async clearProxy(): Promise<void> {
    await chrome.proxy.settings.clear({ scope: 'regular' });
    this.currentMode = ProxyMode.DIRECT;
  }

  /**
   * 获取当前代理模式
   */
  getCurrentMode(): ProxyMode {
    return this.currentMode;
  }

  /**
   * 监听代理错误事件
   * WHY: 代理连接失败时需要通知 UI 层
   */
  onError(callback: (details: chrome.proxy.ErrorDetails) => void): void {
    chrome.proxy.onProxyError.addListener(callback);
  }
}

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - chrome.proxy API 在 Manifest V3 中可用
 *    - SOCKS5 代理地址指向本地的协议转换端口
 *    - bypassList 包含常见内网地址段
 * 2. Potential edge cases:
 *    - 用户可能已有其他代理扩展设置了 proxy，会产生冲突
 *    - PAC 脚本中的域名需要正确转义
 *    - chrome.proxy.settings.clear 可能需要权限确认
 * 3. Dependencies: chrome.proxy API（需要 manifest 中声明 proxy 权限）
 */
