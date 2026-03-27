/**
 * __ai_context__: Popup 弹出窗口逻辑。
 * 负责显示当前连接状态、服务器列表，以及处理用户交互。
 * 通过 chrome.runtime.sendMessage 与 Service Worker 通信。
 */

import {
  ConnectionStatus,
  MessageAction,
  type AppState,
  type ServerConfig,
  type ExtensionMessage,
  type ExtensionResponse,
} from '../core/config';

// ============================================================
// DOM 元素引用
// ============================================================
const statusIndicator = document.getElementById('statusIndicator')!;
const statusBadge = document.getElementById('statusBadge')!;
const statusText = document.getElementById('statusText')!;
const connDuration = document.getElementById('connDuration')!;
const connectBtn = document.getElementById('connectBtn')!;
const btnIcon = document.getElementById('btnIcon')!;
const btnText = document.getElementById('btnText')!;
const serverList = document.getElementById('serverList')!;
const openOptionsBtn = document.getElementById('openOptionsBtn')!;
const addServerBtn = document.getElementById('addServerBtn')!;

// ============================================================
// 状态
// ============================================================
let currentState: AppState | null = null;
let selectedServerId: string | null = null;
let servers: ServerConfig[] = [];
let durationTimer: ReturnType<typeof setInterval> | null = null;

// ============================================================
// 初始化
// ============================================================
async function init(): Promise<void> {
  // 加载服务器列表和状态
  await loadServers();
  await loadStatus();

  // 绑定事件
  connectBtn.addEventListener('click', handleConnectClick);
  openOptionsBtn.addEventListener('click', openOptions);
  addServerBtn?.addEventListener('click', openOptions);

  // 监听来自 Service Worker 的状态变更
  chrome.runtime.onMessage.addListener((message: ExtensionMessage) => {
    if (message.action === MessageAction.STATUS_CHANGED) {
      updateUI(message.payload as AppState);
    }
  });
}

// ============================================================
// 数据加载
// ============================================================

async function loadServers(): Promise<void> {
  const result = await chrome.storage.local.get('servers');
  servers = result.servers || [];
  renderServerList();
}

async function loadStatus(): Promise<void> {
  const response = await sendMessage({
    action: MessageAction.GET_STATUS,
  });

  if (response.success && response.data) {
    updateUI(response.data as AppState);
  }
}

// ============================================================
// UI 更新
// ============================================================

/**
 * 根据状态更新 UI
 * WHY: 集中管理所有 UI 状态变更，避免散落的 DOM 操作
 */
function updateUI(state: AppState): void {
  currentState = state;
  selectedServerId = state.activeServerId;

  // 更新状态指示器
  statusIndicator.className = 'logo-icon';
  statusBadge.className = 'status-badge';

  switch (state.status) {
    case ConnectionStatus.CONNECTED:
      statusIndicator.classList.add('connected');
      statusBadge.classList.add('connected');
      statusText.textContent = '已连接';
      connectBtn.className = 'connect-btn connected';
      btnIcon.textContent = '⏹';
      btnText.textContent = '断开连接';
      startDurationTimer(state.connectedSince);
      break;

    case ConnectionStatus.CONNECTING:
      statusBadge.classList.add('connecting');
      statusText.textContent = '连接中...';
      connectBtn.className = 'connect-btn connecting';
      connectBtn.setAttribute('disabled', 'true');
      btnIcon.textContent = '⏳';
      btnText.textContent = '连接中...';
      connDuration.textContent = '--:--:--';
      break;

    case ConnectionStatus.ERROR:
      statusIndicator.classList.add('error');
      statusBadge.classList.add('error');
      statusText.textContent = '连接错误';
      connectBtn.className = 'connect-btn';
      connectBtn.removeAttribute('disabled');
      btnIcon.textContent = '⚡';
      btnText.textContent = '重新连接';
      connDuration.textContent = state.errorMessage || '未知错误';
      stopDurationTimer();
      break;

    case ConnectionStatus.DISCONNECTED:
    default:
      statusText.textContent = '未连接';
      connectBtn.className = 'connect-btn';
      connectBtn.removeAttribute('disabled');
      btnIcon.textContent = '⚡';
      btnText.textContent = '连接';
      connDuration.textContent = '--:--:--';
      stopDurationTimer();
      break;
  }

  // 更新服务器列表中的选中状态
  renderServerList();
}

/**
 * 渲染服务器列表
 */
function renderServerList(): void {
  if (servers.length === 0) {
    serverList.innerHTML = `
      <div class="empty-state">
        <p>尚未添加服务器</p>
        <button class="link-btn" id="addServerBtn">+ 添加服务器</button>
      </div>
    `;
    // WHY: 重新绑定动态生成的按钮事件
    document.getElementById('addServerBtn')?.addEventListener('click', openOptions);
    return;
  }

  serverList.innerHTML = servers
    .map((server) => {
      const isActive = server.id === selectedServerId;
      const latencyClass = getLatencyClass(server.latency);
      const latencyText = server.latency >= 0 ? `${server.latency}ms` : '超时';

      return `
        <div class="server-item ${isActive ? 'active' : ''}" data-id="${server.id}">
          <span class="server-protocol">${server.protocol}</span>
          <div class="server-info">
            <div class="server-name">${escapeHtml(server.name)}</div>
            <div class="server-address">${escapeHtml(server.address)}:${server.port}</div>
          </div>
          <span class="server-latency ${latencyClass}">${latencyText}</span>
        </div>
      `;
    })
    .join('');

  // 绑定服务器点击事件
  serverList.querySelectorAll('.server-item').forEach((item) => {
    item.addEventListener('click', () => {
      const serverId = (item as HTMLElement).dataset.id;
      if (serverId) {
        selectServer(serverId);
      }
    });
  });
}

// ============================================================
// 交互处理
// ============================================================

function selectServer(serverId: string): void {
  selectedServerId = serverId;
  renderServerList();
}

async function handleConnectClick(): Promise<void> {
  if (!currentState) return;

  if (currentState.status === ConnectionStatus.CONNECTED) {
    // 断开连接
    await sendMessage({ action: MessageAction.DISCONNECT });
  } else {
    // 连接
    if (!selectedServerId && servers.length > 0) {
      selectedServerId = servers[0].id;
    }

    if (!selectedServerId) {
      // WHY: 没有服务器可连接时打开设置页
      openOptions();
      return;
    }

    await sendMessage({
      action: MessageAction.CONNECT,
      payload: selectedServerId,
    });
  }
}

function openOptions(): void {
  chrome.runtime.openOptionsPage();
}

// ============================================================
// 辅助函数
// ============================================================

async function sendMessage(message: ExtensionMessage): Promise<ExtensionResponse> {
  return chrome.runtime.sendMessage(message);
}

/**
 * 启动连接时长计时器
 */
function startDurationTimer(connectedSince: number | null): void {
  stopDurationTimer();

  if (!connectedSince) return;

  const update = () => {
    const elapsed = Math.floor((Date.now() - connectedSince) / 1000);
    const hours = Math.floor(elapsed / 3600);
    const minutes = Math.floor((elapsed % 3600) / 60);
    const seconds = elapsed % 60;

    connDuration.textContent = [
      hours.toString().padStart(2, '0'),
      minutes.toString().padStart(2, '0'),
      seconds.toString().padStart(2, '0'),
    ].join(':');
  };

  update();
  durationTimer = setInterval(update, 1000);
}

function stopDurationTimer(): void {
  if (durationTimer) {
    clearInterval(durationTimer);
    durationTimer = null;
  }
}

function getLatencyClass(latency: number): string {
  if (latency < 0) return 'timeout';
  if (latency > 300) return 'slow';
  return '';
}

function escapeHtml(str: string): string {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

// ============================================================
// 启动
// ============================================================
init().catch((error) => {
  console.error('[LCLLink Popup] Init failed:', error);
});

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - Popup 每次打开都会重新加载，不保持内存状态
 *    - 通过 chrome.runtime.sendMessage 与 Service Worker 同步
 *    - 服务器列表从 chrome.storage.local 读取
 * 2. Potential edge cases:
 *    - Service Worker 可能未启动，sendMessage 会失败
 *    - servers 为空时不应允许连接操作
 *    - 连接时长计时器需要在 Popup 关闭时自动停止（DOM 销毁）
 * 3. Dependencies: ../core/config（类型定义）
 */
