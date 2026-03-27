/**
 * __ai_context__: Options 设置页面逻辑。
 * 负责服务器配置的增删改查、URI 链接导入、日志查看、Tab 切换。
 * 数据存储在 chrome.storage.local 中。
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
  type LogEntry,
} from '../core/config';
import { Logger } from '../utils/logger';
import { parseMultipleUris } from '../utils/uri-parser';

// ============================================================
// DOM 元素引用
// ============================================================
const serverModal = document.getElementById('serverModal')!;
const serverForm = document.getElementById('serverForm') as HTMLFormElement;
const serverTable = document.getElementById('serverTable')!;
const addServerBtn = document.getElementById('addServerBtn')!;
const closeModalBtn = document.getElementById('closeModalBtn')!;
const cancelBtn = document.getElementById('cancelBtn')!;
const modalTitle = document.getElementById('modalTitle')!;
const clearLogsBtn = document.getElementById('clearLogsBtn')!;
const logOutput = document.getElementById('logOutput')!;

// URI 导入面板
const importUriBtn = document.getElementById('importUriBtn')!;
const importPanel = document.getElementById('importPanel')!;
const closeImportPanel = document.getElementById('closeImportPanel')!;
const importTextarea = document.getElementById('importTextarea') as HTMLTextAreaElement;
const doImportBtn = document.getElementById('doImportBtn')!;
const importResult = document.getElementById('importResult')!;

// 表单字段
const serverNameInput = document.getElementById('serverName') as HTMLInputElement;
const serverProtocolSelect = document.getElementById('serverProtocol') as HTMLSelectElement;
const serverAddressInput = document.getElementById('serverAddress') as HTMLInputElement;
const serverPortInput = document.getElementById('serverPort') as HTMLInputElement;

// VLESS 字段
const vlessSection = document.getElementById('vlessSection')!;
const vlessUuidInput = document.getElementById('vlessUuid') as HTMLInputElement;
const vlessEncryptionSelect = document.getElementById('vlessEncryption') as HTMLSelectElement;
const vlessFlowSelect = document.getElementById('vlessFlow') as HTMLSelectElement;

// Trojan 字段
const trojanSection = document.getElementById('trojanSection')!;
const trojanPasswordInput = document.getElementById('trojanPassword') as HTMLInputElement;

// SS 字段
const ssSection = document.getElementById('ssSection')!;
const ssMethodSelect = document.getElementById('ssMethod') as HTMLSelectElement;
const ssPasswordInput = document.getElementById('ssPassword') as HTMLInputElement;

// 传输字段
const wsPathInput = document.getElementById('wsPath') as HTMLInputElement;
const wsHostInput = document.getElementById('wsHost') as HTMLInputElement;

// TLS 字段
const tlsEnabledCheckbox = document.getElementById('tlsEnabled') as HTMLInputElement;
const tlsAllowInsecureCheckbox = document.getElementById('tlsAllowInsecure') as HTMLInputElement;
const tlsSniInput = document.getElementById('tlsSni') as HTMLInputElement;
const tlsFingerprintSelect = document.getElementById('tlsFingerprint') as HTMLSelectElement;

// ============================================================
// 状态
// ============================================================
let servers: ServerConfig[] = [];
let editingServerId: string | null = null;

// ============================================================
// 初始化
// ============================================================
async function init(): Promise<void> {
  await loadServers();
  renderServerTable();

  // Tab 切换
  document.querySelectorAll('.nav-item').forEach((item) => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const tab = (item as HTMLElement).dataset.tab;
      if (tab) switchTab(tab);
    });
  });

  // 服务器管理
  addServerBtn.addEventListener('click', openAddModal);
  closeModalBtn.addEventListener('click', closeModal);
  cancelBtn.addEventListener('click', closeModal);
  serverForm.addEventListener('submit', handleFormSubmit);

  // 协议选择联动
  serverProtocolSelect.addEventListener('change', handleProtocolChange);

  // URI 导入
  importUriBtn.addEventListener('click', toggleImportPanel);
  closeImportPanel.addEventListener('click', () => { importPanel.style.display = 'none'; });
  doImportBtn.addEventListener('click', handleImport);

  // 日志
  clearLogsBtn.addEventListener('click', handleClearLogs);

  // 点击模态框外部关闭
  serverModal.addEventListener('click', (e) => {
    if (e.target === serverModal) closeModal();
  });
}

// ============================================================
// Tab 切换
// ============================================================
function switchTab(tabName: string): void {
  // 更新导航高亮
  document.querySelectorAll('.nav-item').forEach((item) => {
    item.classList.toggle('active', (item as HTMLElement).dataset.tab === tabName);
  });

  // 切换内容
  document.querySelectorAll('.tab-content').forEach((content) => {
    content.classList.toggle('active', content.id === `tab-${tabName}`);
  });

  // 切换到日志页时加载日志
  if (tabName === 'logs') {
    loadLogs();
  }
}

// ============================================================
// 服务器管理
// ============================================================

async function loadServers(): Promise<void> {
  const result = await chrome.storage.local.get('servers');
  servers = result.servers || [];
}

async function saveServers(): Promise<void> {
  await chrome.storage.local.set({ servers });
}

function renderServerTable(): void {
  if (servers.length === 0) {
    serverTable.innerHTML = `
      <div class="table-empty">
        <p>尚未添加任何服务器配置</p>
        <p class="hint">点击「添加服务器」手动配置，或「导入链接」粘贴分享 URI</p>
      </div>
    `;
    return;
  }

  serverTable.innerHTML = servers
    .map(
      (server) => `
      <div class="server-row" data-id="${server.id}">
        <span class="protocol-badge">${server.protocol}</span>
        <div class="server-details">
          <div class="server-title">${escapeHtml(server.name)}</div>
          <div class="server-addr">${escapeHtml(server.address)}:${server.port}</div>
        </div>
        <div class="actions">
          <button class="action-btn edit" title="编辑" data-action="edit" data-id="${server.id}">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
              <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
            </svg>
          </button>
          <button class="action-btn delete" title="删除" data-action="delete" data-id="${server.id}">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <polyline points="3 6 5 6 21 6"/>
              <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
            </svg>
          </button>
        </div>
      </div>
    `,
    )
    .join('');

  // 绑定操作按钮
  serverTable.querySelectorAll('.action-btn').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const el = btn as HTMLElement;
      const action = el.dataset.action;
      const id = el.dataset.id;
      if (!id) return;

      if (action === 'edit') openEditModal(id);
      if (action === 'delete') deleteServer(id);
    });
  });
}

// ============================================================
// 模态框
// ============================================================

function openAddModal(): void {
  editingServerId = null;
  modalTitle.textContent = '添加服务器';
  serverForm.reset();
  wsPathInput.value = '/';
  tlsEnabledCheckbox.checked = true;
  handleProtocolChange();
  serverModal.classList.add('visible');
}

function openEditModal(serverId: string): void {
  const server = servers.find((s) => s.id === serverId);
  if (!server) return;

  editingServerId = serverId;
  modalTitle.textContent = '编辑服务器';

  // 填充基础字段
  serverNameInput.value = server.name;
  serverProtocolSelect.value = server.protocol;
  serverAddressInput.value = server.address;
  serverPortInput.value = server.port.toString();

  // 填充传输配置
  wsPathInput.value = server.websocket.path;
  wsHostInput.value = server.websocket.headers['Host'] || '';

  // 填充 TLS 配置
  tlsEnabledCheckbox.checked = server.tls.enabled;
  tlsAllowInsecureCheckbox.checked = server.tls.allowInsecure;
  tlsSniInput.value = server.tls.serverName;
  tlsFingerprintSelect.value = server.tls.fingerprint;

  // 填充协议专有配置
  switch (server.protocol) {
    case ProtocolType.VLESS: {
      const config = server.protocolConfig as VlessSpecificConfig;
      vlessUuidInput.value = config.uuid;
      vlessEncryptionSelect.value = config.encryption;
      vlessFlowSelect.value = config.flow;
      break;
    }
    case ProtocolType.TROJAN: {
      const config = server.protocolConfig as TrojanSpecificConfig;
      trojanPasswordInput.value = config.password;
      break;
    }
    case ProtocolType.SHADOWSOCKS:
    case ProtocolType.SHADOWSOCKS_2022: {
      const config = server.protocolConfig as ShadowsocksSpecificConfig;
      ssMethodSelect.value = config.method;
      ssPasswordInput.value = config.password;
      break;
    }
  }

  handleProtocolChange();
  serverModal.classList.add('visible');
}

function closeModal(): void {
  serverModal.classList.remove('visible');
  editingServerId = null;
}

// ============================================================
// 表单处理
// ============================================================

function handleProtocolChange(): void {
  const protocol = serverProtocolSelect.value;

  // WHY: 根据选择的协议显示/隐藏对应的配置区域
  vlessSection.style.display = protocol === 'vless' ? '' : 'none';
  trojanSection.style.display = protocol === 'trojan' ? '' : 'none';
  ssSection.style.display = protocol === 'shadowsocks' ? '' : 'none';
}

async function handleFormSubmit(e: Event): Promise<void> {
  e.preventDefault();

  const protocol = serverProtocolSelect.value as ProtocolType;

  // 构建协议特定配置
  let protocolConfig: VlessSpecificConfig | TrojanSpecificConfig | ShadowsocksSpecificConfig;

  switch (protocol) {
    case ProtocolType.VLESS:
      protocolConfig = {
        uuid: vlessUuidInput.value,
        encryption: vlessEncryptionSelect.value,
        flow: vlessFlowSelect.value,
        reality: {
          enabled: false,
          publicKey: '',
          shortId: '',
          spiderX: '',
        } satisfies RealityConfig,
      } satisfies VlessSpecificConfig;
      break;

    case ProtocolType.TROJAN:
      protocolConfig = {
        password: trojanPasswordInput.value,
      } satisfies TrojanSpecificConfig;
      break;

    case ProtocolType.SHADOWSOCKS:
    case ProtocolType.SHADOWSOCKS_2022:
    default:
      protocolConfig = {
        method: ssMethodSelect.value as ShadowsocksMethod,
        password: ssPasswordInput.value,
      } satisfies ShadowsocksSpecificConfig;
      break;
  }

  // 构建 TLS 配置
  const tls: TlsConfig = {
    enabled: tlsEnabledCheckbox.checked,
    serverName: tlsSniInput.value || serverAddressInput.value,
    allowInsecure: tlsAllowInsecureCheckbox.checked,
    alpn: ['h2', 'http/1.1'],
    fingerprint: tlsFingerprintSelect.value,
  };

  // 构建 WebSocket 配置
  const websocket: WebSocketConfig = {
    path: wsPathInput.value || '/',
    headers: wsHostInput.value ? { Host: wsHostInput.value } : {},
    maxEarlyData: 0,
    earlyDataHeaderName: '',
  };

  const now = Date.now();

  const serverConfig: ServerConfig = {
    id: editingServerId || crypto.randomUUID(),
    name: serverNameInput.value,
    protocol,
    address: serverAddressInput.value,
    port: parseInt(serverPortInput.value),
    transport: TransportType.WEBSOCKET,
    tls,
    websocket,
    protocolConfig,
    createdAt: editingServerId
      ? (servers.find((s) => s.id === editingServerId)?.createdAt || now)
      : now,
    updatedAt: now,
    latency: -1,
  };

  // 保存
  if (editingServerId) {
    const index = servers.findIndex((s) => s.id === editingServerId);
    if (index !== -1) {
      servers[index] = serverConfig;
    }
  } else {
    servers.push(serverConfig);
  }

  await saveServers();
  renderServerTable();
  closeModal();
}

async function deleteServer(serverId: string): Promise<void> {
  if (!confirm('确定要删除这个服务器吗？')) return;

  servers = servers.filter((s) => s.id !== serverId);
  await saveServers();
  renderServerTable();
}

// ============================================================
// 日志
// ============================================================

async function loadLogs(): Promise<void> {
  const logs = await Logger.getStoredLogs();

  if (logs.length === 0) {
    logOutput.textContent = '暂无日志';
    return;
  }

  logOutput.innerHTML = logs
    .map((log: LogEntry) => {
      const time = new Date(log.timestamp).toLocaleTimeString('zh-CN', { hour12: false });
      const levelClass = log.level;
      return `<span class="log-line ${levelClass}">[${time}][${log.level.toUpperCase()}][${log.source}] ${escapeHtml(log.message)}</span>`;
    })
    .join('\n');

  // 滚动到底部
  logOutput.scrollTop = logOutput.scrollHeight;
}

async function handleClearLogs(): Promise<void> {
  await Logger.clearLogs();
  logOutput.textContent = '日志已清除';
}

// ============================================================
// 辅助函数
// ============================================================

function escapeHtml(str: string): string {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

// ============================================================
// URI 导入
// ============================================================

function toggleImportPanel(): void {
  const isVisible = importPanel.style.display !== 'none';
  importPanel.style.display = isVisible ? 'none' : 'block';
  if (!isVisible) {
    importTextarea.focus();
    importResult.innerHTML = '';
  }
}

/**
 * 解析并导入 URI 链接
 * WHY: 用户粘贴 vless:// / trojan:// / ss:// 链接后一键导入
 */
async function handleImport(): Promise<void> {
  const text = importTextarea.value.trim();
  if (!text) {
    importResult.innerHTML = '<span class="error-text">请粘贴至少一条链接</span>';
    return;
  }

  const results = parseMultipleUris(text);
  const successes = results.filter((r) => r.success && r.config);
  const failures = results.filter((r) => !r.success);

  if (successes.length === 0) {
    // 全部失败
    const errorMessages = failures.map((f) => f.error).join('<br>');
    importResult.innerHTML = `<span class="error-text">导入失败</span><div class="detail-text">${errorMessages}</div>`;
    return;
  }

  // 将成功的配置添加到服务器列表
  for (const result of successes) {
    if (result.config) {
      servers.push(result.config);
    }
  }

  await saveServers();
  renderServerTable();

  // 显示结果
  let resultHtml = `<span class="success-text">✓ 成功导入 ${successes.length} 个服务器</span>`;
  if (failures.length > 0) {
    resultHtml += `<div class="detail-text">${failures.length} 个链接解析失败</div>`;
  }
  importResult.innerHTML = resultHtml;

  // 清空输入
  importTextarea.value = '';

  // 3 秒后自动隐藏面板
  setTimeout(() => {
    importPanel.style.display = 'none';
    importResult.innerHTML = '';
  }, 3000);
}

// ============================================================
// 启动
// ============================================================
init().catch((error) => {
  console.error('[LCLLink Options] Init failed:', error);
});

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - 表单数据直接序列化为 ServerConfig 存入 chrome.storage.local
 *    - 编辑时使用 editingServerId 判断是新增还是修改
 *    - 协议切换时动态显示/隐藏对应的配置区块
 *    - URI 导入支持批量解析（每行一个 URI）
 * 2. Potential edge cases:
 *    - 端口输入可能为浮点数（parseInt 处理）
 *    - 服务器名称可能包含 XSS 攻击内容（escapeHtml 处理）
 *    - chrome.storage.local 有 10MB 限制
 *    - URI 解析失败时需要向用户显示具体错误原因
 * 3. Dependencies: ../core/config, ../utils/logger, ../utils/uri-parser
 */
