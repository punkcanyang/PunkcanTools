import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

const DEVTOOLS_PORT_FILE = 'DevToolsActivePort';
const DEFAULT_TIMEOUT_MS = 30000;

export async function renderPdfWithCdp({
  browserPath,
  inputUrl,
  outputPath,
  wait = 1200,
  pdfOptions,
  verbose = false,
}) {
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'html-book-pdf-cdp-'));
  const userDataDir = path.join(tempRoot, 'profile');
  const browserArgs = [
    '--headless=new',
    '--no-sandbox',
    '--disable-gpu',
    '--disable-dev-shm-usage',
    '--allow-file-access-from-files',
    '--no-first-run',
    '--no-default-browser-check',
    '--remote-debugging-port=0',
    `--user-data-dir=${userDataDir}`,
    'about:blank',
  ];

  let browserProcess;
  let connection;

  try {
    await fs.mkdir(userDataDir, { recursive: true });

    browserProcess = launchBrowser({
      browserPath,
      browserArgs,
      verbose,
    });

    const port = await waitForDevToolsPort(userDataDir);
    const wsUrl = await readBrowserWebSocketUrl(port);
    connection = await connectToBrowser(wsUrl);

    const { targetId } = await connection.send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await connection.send('Target.attachToTarget', {
      targetId,
      flatten: true,
    });

    await connection.send('Page.enable', {}, sessionId);
    await connection.send('Runtime.enable', {}, sessionId);
    await connection.send('Page.navigate', { url: inputUrl }, sessionId);
    await connection.waitForEvent(
      (message) => message.sessionId === sessionId && message.method === 'Page.loadEventFired',
    );

    if (wait > 0) {
      await delay(wait);
    }

    const { data } = await connection.send('Page.printToPDF', pdfOptions, sessionId);
    await fs.writeFile(outputPath, Buffer.from(data, 'base64'));

    await connection.send('Target.closeTarget', { targetId });
  } finally {
    if (connection) {
      connection.close();
    }

    if (browserProcess) {
      await terminateProcess(browserProcess);
    }

    await fs.rm(tempRoot, { recursive: true, force: true });
  }
}

function launchBrowser({ browserPath, browserArgs, verbose }) {
  const stdio = verbose ? 'inherit' : ['ignore', 'pipe', 'pipe'];
  const child = spawn(browserPath, browserArgs, { stdio });

  let stderr = '';
  if (child.stderr && !verbose) {
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });
  }

  child.once('error', (error) => {
    error.message = `啟動瀏覽器失敗：${error.message}`;
  });

  child.on('exit', (code) => {
    if (code !== 0 && !verbose) {
      child._exitErrorText = stderr.trim();
    }
  });

  return child;
}

async function waitForDevToolsPort(userDataDir, timeoutMs = DEFAULT_TIMEOUT_MS) {
  const deadline = Date.now() + timeoutMs;
  const portFile = path.join(userDataDir, DEVTOOLS_PORT_FILE);

  while (Date.now() < deadline) {
    try {
      const content = await fs.readFile(portFile, 'utf8');
      const [portValue] = content.trim().split('\n');
      const port = Number(portValue);
      if (Number.isFinite(port) && port > 0) {
        return port;
      }
    } catch {
      // Browser still booting.
    }
    await delay(100);
  }

  throw new Error('無法取得 Chromium DevTools 連線埠。');
}

async function readBrowserWebSocketUrl(port) {
  const controller = AbortSignal.timeout(DEFAULT_TIMEOUT_MS);
  const response = await fetch(`http://127.0.0.1:${port}/json/version`, {
    signal: controller,
  });

  if (!response.ok) {
    throw new Error(`無法讀取 DevTools 版本資訊（HTTP ${response.status}）。`);
  }

  const payload = await response.json();
  const wsUrl = payload.webSocketDebuggerUrl;
  if (!wsUrl) {
    throw new Error('DevTools 版本資訊缺少 webSocketDebuggerUrl。');
  }

  return wsUrl;
}

async function connectToBrowser(wsUrl) {
  const socket = new WebSocket(wsUrl);
  const inflight = new Map();
  const eventListeners = new Set();
  let nextId = 1;
  let opened = false;

  const openedPromise = new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error('連線 DevTools WebSocket 逾時。'));
    }, DEFAULT_TIMEOUT_MS);

    socket.addEventListener('open', () => {
      clearTimeout(timer);
      opened = true;
      resolve();
    });

    socket.addEventListener('error', (event) => {
      clearTimeout(timer);
      reject(new Error(`DevTools WebSocket 連線失敗：${event.message ?? 'unknown error'}`));
    });
  });

  socket.addEventListener('message', (event) => {
    const payload = JSON.parse(event.data);
    if (payload.id) {
      const pending = inflight.get(payload.id);
      if (!pending) {
        return;
      }
      inflight.delete(payload.id);
      if (payload.error) {
        pending.reject(new Error(payload.error.message ?? 'DevTools command failed'));
        return;
      }
      pending.resolve(payload.result);
      return;
    }

    for (const listener of eventListeners) {
      listener(payload);
    }
  });

  socket.addEventListener('close', () => {
    for (const pending of inflight.values()) {
      pending.reject(new Error('DevTools WebSocket 已關閉。'));
    }
    inflight.clear();
  });

  await openedPromise;

  return {
    async send(method, params = {}, sessionId) {
      if (!opened) {
        throw new Error('DevTools WebSocket 尚未建立。');
      }

      const id = nextId;
      nextId += 1;

      const payload = { id, method, params };
      if (sessionId) {
        payload.sessionId = sessionId;
      }

      const resultPromise = new Promise((resolve, reject) => {
        inflight.set(id, { resolve, reject });
      });

      socket.send(JSON.stringify(payload));
      return resultPromise;
    },
    waitForEvent(predicate, timeoutMs = DEFAULT_TIMEOUT_MS) {
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          eventListeners.delete(listener);
          reject(new Error('等待 DevTools 事件逾時。'));
        }, timeoutMs);

        const listener = (message) => {
          if (!predicate(message)) {
            return;
          }
          clearTimeout(timer);
          eventListeners.delete(listener);
          resolve(message);
        };

        eventListeners.add(listener);
      });
    },
    close() {
      if (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING) {
        socket.close();
      }
    },
  };
}

async function terminateProcess(child) {
  if (child.exitCode !== null) {
    return;
  }

  child.kill('SIGTERM');

  await new Promise((resolve) => {
    const timer = setTimeout(() => {
      if (child.exitCode === null) {
        child.kill('SIGKILL');
      }
      resolve();
    }, 3000);

    child.once('exit', () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

function delay(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}
