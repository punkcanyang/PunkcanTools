const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

// DOM Elements
const networkInput = document.getElementById('network-input');
const detectBtn = document.getElementById('detect-btn');
const scanBtn = document.getElementById('scan-btn');
const stopBtn = document.getElementById('stop-btn');
const progressSection = document.getElementById('progress-section');
const progressPhase = document.getElementById('progress-phase');
const progressCount = document.getElementById('progress-count');
const progressBar = document.getElementById('progress-bar');
const devicesFound = document.getElementById('devices-found');
const scanTime = document.getElementById('scan-time');
const resultsEmpty = document.getElementById('results-empty');
const resultsGrid = document.getElementById('results-grid');
const resultCount = document.getElementById('result-count');
const deviceModal = document.getElementById('device-modal');
const modalClose = document.getElementById('modal-close');
const modalBody = document.getElementById('modal-body');
const nmapIndicator = document.getElementById('nmap-indicator');
const nmapText = document.getElementById('nmap-text');
const nmapInstallBtn = document.getElementById('nmap-install-btn');

// Scan mode checkboxes
const modePorts = document.getElementById('mode-ports');
const modeBanner = document.getElementById('mode-banner');
const modeOs = document.getElementById('mode-os');

// Profile elements
const saveProfileBtn = document.getElementById('save-profile-btn');
const loadProfileBtn = document.getElementById('load-profile-btn');
const profileModal = document.getElementById('profile-modal');
const profileModalClose = document.getElementById('profile-modal-close');
const profileList = document.getElementById('profile-list');
const saveModal = document.getElementById('save-modal');
const saveModalClose = document.getElementById('save-modal-close');
const profileNameInput = document.getElementById('profile-name-input');
const saveConfirmBtn = document.getElementById('save-confirm-btn');
const skipIpsSection = document.getElementById('skip-ips-section');
const skipKnownIps = document.getElementById('skip-known-ips');
const skipProfileName = document.getElementById('skip-profile-name');

// State
let isScanning = false;
let scanStartTime = null;
let scanTimer = null;
let devices = [];
let nmapInstalled = false;
let loadedProfile = null; // Currently loaded profile for skip-ips feature

// Port → connection tool mapping
const CONNECTABLE_PORTS = new Set([22, 80, 443, 8080, 8443, 3389, 5900, 445, 139, 21]);
const PORT_TOOL_LABELS = {
    22: '🔗 SSH',
    80: '🌐 瀏覽器', 443: '🌐 瀏覽器',
    8080: '🌐 瀏覽器', 8443: '🌐 瀏覽器',
    3389: '🖥️ RDP', 5900: '🖥️ VNC',
    445: '📁 SMB', 139: '📁 SMB',
    21: '📂 FTP',
};

// Initialize
document.addEventListener('DOMContentLoaded', async () => {
    await detectLocalNetwork();
    setupEventListeners();
    await setupTauriListeners();
    await checkNmapStatus();
});

// Check nmap status
async function checkNmapStatus() {
    try {
        const status = await invoke('check_nmap_status');
        nmapInstalled = status.installed;
        
        if (status.installed) {
            nmapIndicator.className = 'nmap-indicator installed';
            nmapText.textContent = `nmap ${status.version || ''} ✓ 精確模式`;
            nmapInstallBtn.style.display = 'none';
        } else {
            nmapIndicator.className = 'nmap-indicator not-installed';
            nmapText.textContent = 'nmap 未安裝 — 使用基本模式（TTL + Banner）';
            nmapInstallBtn.style.display = 'inline-flex';
        }
    } catch (error) {
        console.error('Check nmap error:', error);
        nmapIndicator.className = 'nmap-indicator not-installed';
        nmapText.textContent = 'nmap 狀態未知';
    }
}

// Install nmap
async function installNmap() {
    nmapInstallBtn.disabled = true;
    nmapInstallBtn.textContent = '安裝中...';
    nmapIndicator.className = 'nmap-indicator installing';
    nmapText.textContent = '正在安裝 nmap（透過 Homebrew）...';
    
    try {
        const result = await invoke('install_nmap_cmd');
        nmapIndicator.className = 'nmap-indicator installed';
        nmapText.textContent = result;
        nmapInstallBtn.style.display = 'none';
        nmapInstalled = true;
        setTimeout(checkNmapStatus, 1000);
    } catch (error) {
        nmapIndicator.className = 'nmap-indicator not-installed';
        nmapText.textContent = '安裝失敗: ' + error;
        nmapInstallBtn.disabled = false;
        nmapInstallBtn.textContent = '重試安裝';
    }
}

// Detect local network
async function detectLocalNetwork() {
    try {
        const network = await invoke('get_local_network');
        if (network) {
            networkInput.value = network;
        }
    } catch (error) {
        console.log('Could not detect local network:', error);
    }
}

// ===== Copy IP to clipboard =====
async function copyIp(ip, event) {
    event.stopPropagation();
    try {
        await navigator.clipboard.writeText(ip);
        const btn = event.currentTarget;
        const originalText = btn.textContent;
        btn.classList.add('copied');
        btn.textContent = '✓';
        setTimeout(() => {
            btn.classList.remove('copied');
            btn.textContent = originalText;
        }, 1200);
    } catch (e) {
        console.error('Copy failed:', e);
    }
}
window.copyIp = copyIp;

// ===== Copy text to clipboard (generic) =====
async function copyText(text, btn) {
    try {
        await navigator.clipboard.writeText(text);
        const originalText = btn.textContent;
        btn.classList.add('copied');
        btn.textContent = '✓ 已複製';
        setTimeout(() => {
            btn.classList.remove('copied');
            btn.textContent = originalText;
        }, 1200);
    } catch (e) {
        console.error('Copy failed:', e);
    }
}

// Set up event listeners
function setupEventListeners() {
    detectBtn.addEventListener('click', detectLocalNetwork);
    scanBtn.addEventListener('click', startScan);
    stopBtn.addEventListener('click', stopScan);
    nmapInstallBtn.addEventListener('click', installNmap);
    
    // Profile buttons
    saveProfileBtn.addEventListener('click', showSaveModal);
    loadProfileBtn.addEventListener('click', showProfileModal);
    
    // Profile modal close
    profileModalClose.addEventListener('click', () => profileModal.classList.remove('active'));
    profileModal.addEventListener('click', (e) => { if (e.target === profileModal) profileModal.classList.remove('active'); });
    
    // Save modal
    saveModalClose.addEventListener('click', () => saveModal.classList.remove('active'));
    saveModal.addEventListener('click', (e) => { if (e.target === saveModal) saveModal.classList.remove('active'); });
    saveConfirmBtn.addEventListener('click', saveCurrentProfile);
    
    // Preset buttons
    document.querySelectorAll('.preset-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const suffix = btn.dataset.suffix;
            const currentValue = networkInput.value.trim();
            
            let baseIp = currentValue.split('/')[0].split('-')[0];
            
            if (!baseIp) {
                baseIp = '192.168.1.0';
            } else {
                const parts = baseIp.split('.');
                if (parts.length === 4) {
                    parts[3] = '0';
                    baseIp = parts.join('.');
                }
            }
            
            networkInput.value = baseIp + suffix;
        });
    });
    
    // Modal close
    modalClose.addEventListener('click', closeModal);
    deviceModal.addEventListener('click', (e) => {
        if (e.target === deviceModal) closeModal();
    });
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            closeModal();
            profileModal.classList.remove('active');
            saveModal.classList.remove('active');
        }
    });
}

// Set up Tauri event listeners
async function setupTauriListeners() {
    await listen('scan-progress', (event) => {
        updateProgress(event.payload);
    });
    
    await listen('device-found', (event) => {
        addDeviceCard(event.payload);
    });

    await listen('device-updated', (event) => {
        updateDeviceCard(event.payload);
    });
    
    await listen('scan-complete', () => {
        onScanComplete();
    });
}

// Start scan
async function startScan() {
    const networkValue = networkInput.value.trim();
    
    if (!networkValue) {
        alert('請輸入網路區塊');
        return;
    }
    
    isScanning = true;
    devices = [];
    resultsGrid.innerHTML = '';
    resultsEmpty.style.display = 'none';
    progressSection.style.display = 'block';
    scanBtn.disabled = true;
    stopBtn.disabled = false;
    saveProfileBtn.disabled = true;
    
    scanStartTime = Date.now();
    scanTimer = setInterval(updateTimer, 100);
    
    // Determine skip IPs
    let skipIps = null;
    if (loadedProfile && skipKnownIps.checked) {
        skipIps = loadedProfile.devices.map(d => d.ip);
    }
    
    try {
        await invoke('start_scan', { 
            networkInput: networkValue,
            scanPorts: modePorts.checked,
            scanBanner: modeBanner.checked,
            scanOs: modeOs.checked,
            skipIps: skipIps,
        });
    } catch (error) {
        console.error('Scan error:', error);
        alert('掃描錯誤: ' + error);
        onScanComplete();
    }
}

// Stop scan
async function stopScan() {
    try {
        await invoke('stop_scan');
    } catch (error) {
        console.error('Stop error:', error);
    }
    onScanComplete();
}

// Update progress
function updateProgress(progress) {
    progressPhase.textContent = progress.phase;
    progressCount.textContent = `${progress.current} / ${progress.total}`;
    
    const percent = progress.total > 0 ? (progress.current / progress.total) * 100 : 0;
    progressBar.style.width = `${percent}%`;
    
    devicesFound.textContent = progress.found_devices;
}

// Update timer
function updateTimer() {
    if (scanStartTime) {
        const elapsed = (Date.now() - scanStartTime) / 1000;
        scanTime.textContent = `${elapsed.toFixed(1)}s`;
    }
}

// On scan complete
function onScanComplete() {
    isScanning = false;
    scanBtn.disabled = false;
    stopBtn.disabled = true;
    saveProfileBtn.disabled = devices.length === 0;
    
    if (scanTimer) {
        clearInterval(scanTimer);
        scanTimer = null;
    }
    
    resultCount.textContent = `${devices.length} 個設備`;
    
    if (devices.length === 0) {
        resultsEmpty.style.display = 'flex';
    }
}

// Get OS method badge HTML
function getOsMethodBadge(method) {
    const labels = { 'nmap': 'nmap', 'nmap-sV': 'nmap', 'banner': 'banner', 'ttl': 'ttl' };
    const label = labels[method] || method;
    const cssClass = method.startsWith('nmap') ? 'nmap' : method;
    return `<span class="os-method-badge ${cssClass}">${label}</span>`;
}

// Render device card inner HTML
function renderCardContent(device, isPreliminary = false) {
    const portTags = device.open_ports.slice(0, 5).map(p => 
        `<span class="port-tag">${p.port}/${p.service}</span>`
    ).join('');
    
    const morePorts = device.open_ports.length > 5 
        ? `<span class="port-tag">+${device.open_ports.length - 5}</span>` 
        : '';
    
    const osMethodBadge = getOsMethodBadge(device.os_method);
    const loadingDot = '<span class="loading-dot">⏳</span>';
    
    return `
        <div class="device-header">
            <div class="device-ip-row">
                <span class="device-ip">${device.ip}</span>
                <button class="copy-btn" title="複製 IP" onclick="copyIp('${device.ip}', event)">📋</button>
            </div>
            <span class="device-status">${isPreliminary ? '掃描中...' : '在線'}</span>
        </div>
        <div class="device-info">
            <div class="device-info-item">
                <span class="device-info-label">設備類型</span>
                <span class="device-info-value">${isPreliminary ? loadingDot : device.device_type}</span>
            </div>
            <div class="device-info-item">
                <span class="device-info-label">作業系統</span>
                <span class="device-info-value">${device.os_guess} ${osMethodBadge}</span>
            </div>
            <div class="device-info-item">
                <span class="device-info-label">延遲</span>
                <span class="device-info-value">${device.latency_ms ? device.latency_ms.toFixed(1) + ' ms' : 'N/A'}</span>
            </div>
            <div class="device-info-item">
                <span class="device-info-label">TTL</span>
                <span class="device-info-value">${device.ttl || 'N/A'}</span>
            </div>
        </div>
        ${isPreliminary ? `
        <div class="device-ports">
            <div class="port-tags">
                <span class="port-tag scanning">${loadingDot} 端口掃描中</span>
            </div>
        </div>
        ` : (device.open_ports.length > 0 ? `
        <div class="device-ports">
            <div class="port-tags">
                ${portTags}
                ${morePorts}
            </div>
        </div>
        ` : '')}
    `;
}

// Add device card (preliminary, from ping phase)
function addDeviceCard(device) {
    devices.push(device);
    
    const card = document.createElement('div');
    card.className = 'device-card device-preliminary';
    card.dataset.ip = device.ip;
    card.onclick = () => showDeviceDetail(device);
    card.innerHTML = renderCardContent(device, true);
    
    resultsGrid.appendChild(card);
    resultCount.textContent = `${devices.length} 個設備`;
}

// Update device card with full details (from detail scan phase)
function updateDeviceCard(device) {
    // Update device in state array
    const idx = devices.findIndex(d => d.ip === device.ip);
    if (idx >= 0) {
        devices[idx] = device;
    }
    
    // Find and update existing card
    const card = resultsGrid.querySelector(`.device-card[data-ip="${device.ip}"]`);
    if (card) {
        card.className = 'device-card';
        card.onclick = () => showDeviceDetail(device);
        card.innerHTML = renderCardContent(device, false);
    }
}

// ===== Show device detail modal =====
function showDeviceDetail(device) {
    // Get fresh device data from state
    const freshDevice = devices.find(d => d.ip === device.ip) || device;
    
    const portsHtml = freshDevice.open_ports.length > 0 
        ? freshDevice.open_ports.map(p => {
            const canConnect = CONNECTABLE_PORTS.has(p.port);
            const toolLabel = PORT_TOOL_LABELS[p.port] || '';
            return `
            <div class="modal-port-item" id="port-item-${p.port}">
                <div class="port-info-row">
                    <span class="modal-port-number">${p.port}</span>
                    <span class="modal-port-service">${p.service}</span>
                    <div class="port-actions">
                        ${canConnect ? `<button class="btn btn-xs btn-connect" data-ip="${freshDevice.ip}" data-port="${p.port}" title="啟動連線工具">${toolLabel}</button>` : ''}
                        <button class="btn btn-xs btn-copy-cmd" data-ip="${freshDevice.ip}" data-port="${p.port}" title="複製連線指令">📋 指令</button>
                        <button class="btn btn-xs btn-grab-banner" data-ip="${freshDevice.ip}" data-port="${p.port}" title="取回連線資訊">📡 資訊</button>
                    </div>
                </div>
                <div class="port-banner-result" id="banner-${p.port}" style="display: none;"></div>
            </div>
            `;
        }).join('')
        : '<p style="color: var(--text-muted);">未發現開放端口</p>';
    
    const bannersHtml = freshDevice.banners && freshDevice.banners.length > 0
        ? freshDevice.banners.map(b => `
            <div class="banner-item">
                <strong>Port ${b.port}</strong> — ${b.service_info}
                ${b.os_hint ? `<br>🖥️ OS: ${b.os_hint}` : ''}
            </div>
        `).join('')
        : '<p style="color: var(--text-muted);">無 Banner 資訊</p>';
    
    const osMethodBadge = getOsMethodBadge(freshDevice.os_method);
    
    modalBody.innerHTML = `
        <div class="modal-device-header">
            <div class="modal-device-ip-row">
                <div class="modal-device-ip">${freshDevice.ip}</div>
                <button class="copy-btn copy-btn-lg" onclick="copyIp('${freshDevice.ip}', event)" title="複製 IP">📋</button>
            </div>
            <div class="modal-device-type">${freshDevice.device_type}</div>
        </div>
        
        <div class="modal-section">
            <div class="modal-section-title">設備資訊</div>
            <div class="modal-info-grid">
                <div class="modal-info-item">
                    <span class="modal-info-label">作業系統 ${osMethodBadge}</span>
                    <span class="modal-info-value">${freshDevice.os_guess}</span>
                </div>
                <div class="modal-info-item">
                    <span class="modal-info-label">OS 詳情</span>
                    <span class="modal-info-value">${freshDevice.os_detail || 'N/A'}</span>
                </div>
                <div class="modal-info-item">
                    <span class="modal-info-label">延遲</span>
                    <span class="modal-info-value">${freshDevice.latency_ms ? freshDevice.latency_ms.toFixed(2) + ' ms' : 'N/A'}</span>
                </div>
                <div class="modal-info-item">
                    <span class="modal-info-label">TTL</span>
                    <span class="modal-info-value">${freshDevice.ttl || 'N/A'}</span>
                </div>
                <div class="modal-info-item">
                    <span class="modal-info-label">MAC 地址</span>
                    <span class="modal-info-value">${freshDevice.mac || 'N/A'}</span>
                </div>
                <div class="modal-info-item">
                    <span class="modal-info-label">製造商</span>
                    <span class="modal-info-value">${freshDevice.vendor}</span>
                </div>
                ${freshDevice.os_accuracy ? `
                <div class="modal-info-item">
                    <span class="modal-info-label">OS 準確度</span>
                    <span class="modal-info-value">${freshDevice.os_accuracy}%</span>
                </div>
                ` : ''}
            </div>
        </div>
        
        <div class="modal-section">
            <div class="modal-section-title" style="display: flex; justify-content: space-between; align-items: center;">
                <span>開放端口 (${freshDevice.open_ports.length})</span>
                <button class="btn btn-sm btn-primary" id="rescan-ports-btn" style="font-size: 0.8rem;">
                    🔍 重新掃描端口
                </button>
            </div>
            <div class="modal-ports-list" id="modal-ports-list">
                ${portsHtml}
            </div>
        </div>
        
        <div class="modal-section">
            <div class="modal-section-title">Banner 資訊</div>
            ${bannersHtml}
        </div>
    `;
    
    // Rescan ports button
    const rescanBtn = document.getElementById('rescan-ports-btn');
    rescanBtn.addEventListener('click', () => rescanPorts(freshDevice.ip));
    
    // Connect buttons
    modalBody.querySelectorAll('.btn-connect').forEach(btn => {
        btn.addEventListener('click', async (e) => {
            e.stopPropagation();
            const ip = btn.dataset.ip;
            const port = parseInt(btn.dataset.port);
            try {
                const result = await invoke('open_connection', { ip, port });
                btn.textContent = '✓ 已開啟';
                setTimeout(() => { btn.textContent = PORT_TOOL_LABELS[port] || '🔗'; }, 1500);
            } catch (error) {
                alert('連線失敗: ' + error);
            }
        });
    });
    
    // Copy command buttons
    modalBody.querySelectorAll('.btn-copy-cmd').forEach(btn => {
        btn.addEventListener('click', async (e) => {
            e.stopPropagation();
            const ip = btn.dataset.ip;
            const port = parseInt(btn.dataset.port);
            try {
                const cmd = await invoke('get_connection_string', { ip, port });
                await copyText(cmd, btn);
            } catch (error) {
                btn.textContent = '❌';
                setTimeout(() => { btn.textContent = '📋 指令'; }, 1500);
            }
        });
    });
    
    // Grab banner buttons
    modalBody.querySelectorAll('.btn-grab-banner').forEach(btn => {
        btn.addEventListener('click', async (e) => {
            e.stopPropagation();
            const ip = btn.dataset.ip;
            const port = parseInt(btn.dataset.port);
            const resultDiv = document.getElementById(`banner-${port}`);
            
            btn.disabled = true;
            btn.textContent = '⏳ 獲取中...';
            resultDiv.style.display = 'block';
            resultDiv.innerHTML = '<span style="color: var(--accent-secondary);">正在取回資訊...</span>';
            
            try {
                const banner = await invoke('grab_port_banner', { ip, port });
                resultDiv.innerHTML = `
                    <div class="banner-result-content">
                        <strong>${banner.service_info}</strong>
                        ${banner.os_hint ? `<br>🖥️ OS: ${banner.os_hint}` : ''}
                        ${banner.banner ? `<pre class="banner-raw">${escapeHtml(banner.banner)}</pre>` : ''}
                    </div>
                `;
            } catch (error) {
                resultDiv.innerHTML = `<span style="color: var(--text-muted);">${error}</span>`;
            }
            
            btn.disabled = false;
            btn.textContent = '📡 資訊';
        });
    });
    
    deviceModal.classList.add('active');
}

// Escape HTML for safe display
function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

// Rescan ports for a device
async function rescanPorts(ip) {
    const rescanBtn = document.getElementById('rescan-ports-btn');
    const portsList = document.getElementById('modal-ports-list');
    
    rescanBtn.disabled = true;
    rescanBtn.textContent = '⏳ 掃描中...';
    portsList.innerHTML = '<p style="color: var(--accent-secondary);">正在掃描端口...</p>';
    
    try {
        const ports = await invoke('scan_device_ports', { ip });
        
        // Update modal ports list
        const openPorts = ports.filter(p => p.is_open);
        
        if (openPorts.length > 0) {
            portsList.innerHTML = openPorts.map(p => `
                <div class="modal-port-item">
                    <span class="modal-port-number">${p.port}</span>
                    <span class="modal-port-service">${p.service}</span>
                </div>
            `).join('');
        } else {
            portsList.innerHTML = '<p style="color: var(--text-muted);">未發現開放端口</p>';
        }
        
        // Update section title
        const titleSpan = rescanBtn.parentElement.querySelector('span');
        titleSpan.textContent = `開放端口 (${openPorts.length})`;
        
        // Also update the device in our local state
        const deviceIdx = devices.findIndex(d => d.ip === ip);
        if (deviceIdx >= 0) {
            devices[deviceIdx].open_ports = openPorts;
            // Re-render the detail to get full action buttons
            showDeviceDetail(devices[deviceIdx]);
            return;
        }
        
        rescanBtn.disabled = false;
        rescanBtn.textContent = '🔍 重新掃描端口';
    } catch (error) {
        console.error('Port scan error:', error);
        portsList.innerHTML = `<p style="color: var(--accent-danger);">掃描失敗: ${error}</p>`;
        rescanBtn.disabled = false;
        rescanBtn.textContent = '🔍 重試';
    }
}

// Close modal
function closeModal() {
    deviceModal.classList.remove('active');
}

// ===== Profile Functions =====

// Show save profile modal
function showSaveModal() {
    profileNameInput.value = '';
    saveModal.classList.add('active');
    profileNameInput.focus();
}

// Save current scan results as profile
async function saveCurrentProfile() {
    const name = profileNameInput.value.trim();
    if (!name) {
        alert('請輸入檔案名稱');
        return;
    }
    
    const network = networkInput.value.trim();
    
    try {
        saveConfirmBtn.disabled = true;
        saveConfirmBtn.textContent = '保存中...';
        
        const summary = await invoke('save_profile', {
            name,
            network,
            devices,
        });
        
        saveModal.classList.remove('active');
        saveConfirmBtn.disabled = false;
        saveConfirmBtn.textContent = '保存';
        
        // Show success feedback
        saveProfileBtn.textContent = '✓ 已保存';
        setTimeout(() => { saveProfileBtn.textContent = '💾 保存'; }, 2000);
    } catch (error) {
        alert('保存失敗: ' + error);
        saveConfirmBtn.disabled = false;
        saveConfirmBtn.textContent = '保存';
    }
}

// Show profile list modal
async function showProfileModal() {
    profileList.innerHTML = '<p style="color: var(--accent-secondary);">載入中...</p>';
    profileModal.classList.add('active');
    
    try {
        const profiles = await invoke('list_profiles');
        
        if (profiles.length === 0) {
            profileList.innerHTML = '<p style="color: var(--text-muted);">尚無保存的檔案</p>';
            return;
        }
        
        profileList.innerHTML = profiles.map(p => `
            <div class="profile-item" data-id="${p.id}">
                <div class="profile-item-info">
                    <div class="profile-item-name">${p.name}</div>
                    <div class="profile-item-meta">
                        ${p.network} · ${p.device_count} 個設備 · ${formatDate(p.updated_at)}
                    </div>
                </div>
                <div class="profile-item-actions">
                    <button class="btn btn-xs btn-primary profile-load-btn" data-id="${p.id}" data-name="${p.name}">載入</button>
                    <button class="btn btn-xs btn-danger profile-delete-btn" data-id="${p.id}" data-name="${p.name}">刪除</button>
                </div>
            </div>
        `).join('');
        
        // Load buttons
        profileList.querySelectorAll('.profile-load-btn').forEach(btn => {
            btn.addEventListener('click', async () => {
                const id = btn.dataset.id;
                const name = btn.dataset.name;
                await loadProfile(id, name);
            });
        });
        
        // Delete buttons
        profileList.querySelectorAll('.profile-delete-btn').forEach(btn => {
            btn.addEventListener('click', async () => {
                const id = btn.dataset.id;
                const name = btn.dataset.name;
                if (confirm(`確定要刪除「${name}」嗎？`)) {
                    await deleteProfile(id);
                }
            });
        });
    } catch (error) {
        profileList.innerHTML = `<p style="color: var(--accent-danger);">載入失敗: ${error}</p>`;
    }
}

// Load a profile
async function loadProfile(id, name) {
    try {
        const profile = await invoke('load_profile', { id });
        
        // Display the devices
        devices = profile.devices;
        resultsGrid.innerHTML = '';
        resultsEmpty.style.display = 'none';
        
        devices.forEach(device => {
            const card = document.createElement('div');
            card.className = 'device-card';
            card.dataset.ip = device.ip;
            card.onclick = () => showDeviceDetail(device);
            card.innerHTML = renderCardContent(device, false);
            resultsGrid.appendChild(card);
        });
        
        resultCount.textContent = `${devices.length} 個設備`;
        networkInput.value = profile.network;
        saveProfileBtn.disabled = false;
        
        // Enable skip-ips feature
        loadedProfile = profile;
        skipIpsSection.style.display = 'flex';
        skipProfileName.textContent = `(${name}: ${profile.devices.length} IPs)`;
        
        profileModal.classList.remove('active');
    } catch (error) {
        alert('載入失敗: ' + error);
    }
}

// Delete a profile
async function deleteProfile(id) {
    try {
        await invoke('delete_profile', { id });
        // Refresh list
        await showProfileModal();
    } catch (error) {
        alert('刪除失敗: ' + error);
    }
}

// Format ISO date for display
function formatDate(isoDate) {
    if (!isoDate) return '';
    return isoDate.replace('T', ' ').replace('Z', '');
}
