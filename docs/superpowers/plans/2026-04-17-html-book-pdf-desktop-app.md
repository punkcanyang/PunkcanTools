# HTML Book PDF Desktop App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a packaged Electron desktop app for `html-book-pdf` that accepts dragged HTML files and exports paged PDFs with bottom-centered page numbers on macOS and Windows.

**Architecture:** Split the current single-file renderer into a small HTML-prep layer plus a Chromium CDP PDF layer so the CLI, HTTP API, and Electron shell all call the same conversion path. Add a lightweight local server for drag-and-drop uploads, then wrap it with an Electron window and `electron-builder` targets that match the repo's existing desktop-app pattern.

**Tech Stack:** Node.js ESM, Chromium DevTools Protocol, Electron, electron-builder, Express, Multer, node:test

---

## File Structure

- Modify: `html-book-pdf/package.json`
  Adds Electron entrypoint, build scripts, packaging metadata, and runtime deps for the local server.
- Modify: `html-book-pdf/src/book-pdf.js`
  Keeps CLI argument parsing and HTML preparation, but delegates PDF generation to a CDP renderer and exposes page-number helpers for tests.
- Create: `html-book-pdf/src/pdf-cdp.js`
  Launches local Chrome / Brave / Edge with remote debugging, creates a tab, prints via `Page.printToPDF`, and writes the PDF file.
- Modify: `html-book-pdf/src/cli.js`
  Keeps the CLI stable while routing through the new CDP-based implementation.
- Create: `html-book-pdf/src/server.js`
  Hosts the static GUI, accepts HTML uploads, runs the converter, and streams the PDF back as a download.
- Create: `html-book-pdf/src/main.js`
  Electron main process that boots the local server, opens the app window, and shuts the server down cleanly.
- Create: `html-book-pdf/public/index.html`
  Single-page desktop UI shell with drag-drop zone, file name area, status text, and export button.
- Create: `html-book-pdf/public/app.js`
  Frontend logic for drag-drop, upload, download, and status transitions.
- Create: `html-book-pdf/public/styles.css`
  Desktop-tool styling for the drop zone and conversion status.
- Modify: `html-book-pdf/README.md`
  Documents CLI usage, desktop app usage, and packaging commands.
- Modify: `README.md`
  Updates the repo tool list to mention the new desktop app packaging support.
- Modify: `html-book-pdf/test/book-pdf.test.js`
  Adds regression tests for footer template generation and CDP print options.
- Create: `html-book-pdf/test/server.test.js`
  Covers upload validation, `GET /`, and successful PDF response headers.
- Create: `html-book-pdf/test/package-config.test.js`
  Guards Electron entrypoint and cross-platform build targets in `package.json`.

### Task 1: Page-Numbered CDP PDF Core

**Files:**
- Create: `html-book-pdf/src/pdf-cdp.js`
- Modify: `html-book-pdf/src/book-pdf.js`
- Modify: `html-book-pdf/src/cli.js`
- Test: `html-book-pdf/test/book-pdf.test.js`

- [ ] **Step 1: Write the failing test**

```js
import {
  buildPrintToPdfOptions,
  createPageNumberFooterTemplate,
} from '../src/book-pdf.js';

test('createPageNumberFooterTemplate renders a centered page number footer', () => {
  const footer = createPageNumberFooterTemplate();

  assert.match(footer, /text-align:\s*center/);
  assert.match(footer, /class="pageNumber"/);
  assert.doesNotMatch(footer, /class="totalPages"/);
});

test('buildPrintToPdfOptions enables header footer printing with css page size', () => {
  const options = buildPrintToPdfOptions({
    footerTemplate: '<div><span class="pageNumber"></span></div>',
  });

  assert.equal(options.displayHeaderFooter, true);
  assert.equal(options.printBackground, true);
  assert.equal(options.preferCSSPageSize, true);
  assert.equal(options.headerTemplate, '<div></div>');
  assert.match(options.footerTemplate, /pageNumber/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test test/book-pdf.test.js`
Expected: FAIL with `does not provide an export named 'buildPrintToPdfOptions'` or `createPageNumberFooterTemplate`.

- [ ] **Step 3: Write minimal implementation**

```js
// html-book-pdf/src/book-pdf.js
import { renderPdfWithCdp } from './pdf-cdp.js';

export function createPageNumberFooterTemplate() {
  return `
    <div style="width:100%;font-size:10px;color:#666;text-align:center;padding:0 0 8px;">
      <span class="pageNumber"></span>
    </div>
  `.trim();
}

export function buildPrintToPdfOptions({ footerTemplate }) {
  return {
    printBackground: true,
    displayHeaderFooter: true,
    preferCSSPageSize: true,
    headerTemplate: '<div></div>',
    footerTemplate,
    marginTop: 0.4,
    marginBottom: 0.6,
  };
}

// inside convertHtmlToPdf()
const footerTemplate = createPageNumberFooterTemplate();
await renderPdfWithCdp({
  browserPath,
  inputUrl,
  outputPath,
  wait: options.wait ?? 1200,
  pdfOptions: buildPrintToPdfOptions({ footerTemplate }),
});
```

```js
// html-book-pdf/src/pdf-cdp.js
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

export async function renderPdfWithCdp({
  browserPath,
  inputUrl,
  outputPath,
  wait,
  pdfOptions,
}) {
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'html-book-pdf-cdp-'));
  const userDataDir = path.join(tempRoot, 'profile');
  const browser = spawn(browserPath, [
    '--headless=new',
    '--disable-gpu',
    '--no-first-run',
    '--no-default-browser-check',
    '--remote-debugging-port=0',
    `--user-data-dir=${userDataDir}`,
    inputUrl,
  ]);

  const debugPort = await readDebugPort(path.join(userDataDir, 'DevToolsActivePort'));
  const version = await fetch(`http://127.0.0.1:${debugPort}/json/version`).then((res) => res.json());
  const socket = new WebSocket(version.webSocketDebuggerUrl);

  await sendCdp(socket, 'Page.enable');
  await sendCdp(socket, 'Page.navigate', { url: inputUrl });
  await waitForLoad(socket);
  await new Promise((resolve) => setTimeout(resolve, wait));

  const pdf = await sendCdp(socket, 'Page.printToPDF', pdfOptions);
  await writeFile(outputPath, Buffer.from(pdf.data, 'base64'));

  socket.close();
  browser.kill('SIGTERM');
  await rm(tempRoot, { recursive: true, force: true });
}

async function readDebugPort(activePortPath) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    try {
      const [port] = (await readFile(activePortPath, 'utf8')).trim().split('\n');
      if (port) return Number(port);
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  throw new Error('Could not discover Chromium DevTools port');
}

async function sendCdp(socket, method, params = {}) {
  const id = Math.floor(Math.random() * 100000);
  const result = await new Promise((resolve, reject) => {
    socket.addEventListener('message', function onMessage(event) {
      const payload = JSON.parse(event.data);
      if (payload.id !== id) return;
      socket.removeEventListener('message', onMessage);
      payload.error ? reject(new Error(payload.error.message)) : resolve(payload.result);
    });
    socket.send(JSON.stringify({ id, method, params }));
  });

  return result;
}

async function waitForLoad(socket) {
  await new Promise((resolve) => {
    socket.addEventListener('message', function onMessage(event) {
      const payload = JSON.parse(event.data);
      if (payload.method !== 'Page.loadEventFired') return;
      socket.removeEventListener('message', onMessage);
      resolve();
    });
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test test/book-pdf.test.js`
Expected: PASS for the new footer-template and print-option assertions, and existing tests stay green.

- [ ] **Step 5: Commit**

```bash
git add html-book-pdf/src/book-pdf.js html-book-pdf/src/pdf-cdp.js html-book-pdf/src/cli.js html-book-pdf/test/book-pdf.test.js
git commit -m "feat: render html pdfs with centered page numbers"
```

### Task 2: Local Server and Drag-Drop API

**Files:**
- Modify: `html-book-pdf/package.json`
- Create: `html-book-pdf/src/server.js`
- Create: `html-book-pdf/public/index.html`
- Create: `html-book-pdf/public/app.js`
- Create: `html-book-pdf/public/styles.css`
- Test: `html-book-pdf/test/server.test.js`

- [ ] **Step 1: Write the failing test**

```js
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import { startServer } from '../src/server.js';

test('GET / serves the desktop app shell', async () => {
  const server = await startServer({ port: 0, renderHtmlFile: async () => { throw new Error('not used'); } });
  const response = await fetch(`${server.origin}/`);
  const html = await response.text();

  assert.equal(response.status, 200);
  assert.match(html, /Drop HTML Here/i);
  await server.close();
});

test('POST /api/render returns a pdf attachment for html uploads', async () => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), 'html-book-pdf-server-'));
  const fakePdfPath = path.join(tempDir, 'rendered.pdf');
  await writeFile(fakePdfPath, '%PDF-1.4\\n');

  const server = await startServer({
    port: 0,
    renderHtmlFile: async () => ({ outputPath: fakePdfPath }),
  });

  const form = new FormData();
  form.append('file', new Blob(['<html><body>Book</body></html>'], { type: 'text/html' }), 'book.html');

  const response = await fetch(`${server.origin}/api/render`, {
    method: 'POST',
    body: form,
  });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), 'application/pdf');
  assert.match(response.headers.get('content-disposition'), /attachment; filename="book.pdf"/);

  await server.close();
});

test('POST /api/render rejects non-html uploads', async () => {
  const server = await startServer({ port: 0, renderHtmlFile: async () => ({ outputPath: '/tmp/unused.pdf' }) });

  const form = new FormData();
  form.append('file', new Blob(['plain text'], { type: 'text/plain' }), 'notes.txt');

  const response = await fetch(`${server.origin}/api/render`, {
    method: 'POST',
    body: form,
  });

  assert.equal(response.status, 400);
  assert.match(await response.text(), /html/i);

  await server.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test test/server.test.js`
Expected: FAIL with `Cannot find module '../src/server.js'`.

- [ ] **Step 3: Write minimal implementation**

```json
// html-book-pdf/package.json
{
  "scripts": {
    "test": "node --test",
    "ui": "node src/server.js"
  },
  "dependencies": {
    "express": "^4.21.2",
    "multer": "^1.4.5-lts.1"
  }
}
```

```js
// html-book-pdf/src/server.js
import express from 'express';
import multer from 'multer';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { createReadStream } from 'node:fs';

import { convertHtmlToPdf } from './book-pdf.js';

const publicDir = fileURLToPath(new URL('../public/', import.meta.url));

export async function startServer({ port = 3457, renderHtmlFile = convertHtmlToPdf } = {}) {
  const app = express();
  const uploadDir = await mkdtemp(path.join(os.tmpdir(), 'html-book-pdf-upload-'));
  const upload = multer({ dest: uploadDir });

  app.use(express.static(publicDir));

  app.get('/', async (_req, res) => {
    res.type('html').send(await readFile(path.join(publicDir, 'index.html'), 'utf8'));
  });

  app.post('/api/render', upload.single('file'), async (req, res) => {
    if (!req.file || !req.file.originalname.toLowerCase().endsWith('.html')) {
      res.status(400).json({ error: '請上傳 .html 檔案' });
      return;
    }

    const result = await renderHtmlFile({
      input: req.file.path,
      output: path.join(uploadDir, `${path.parse(req.file.originalname).name}.pdf`),
    });

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${path.parse(req.file.originalname).name}.pdf"`);
    createReadStream(result.outputPath).pipe(res);
  });

  const server = await new Promise((resolve) => {
    const instance = app.listen(port, () => resolve(instance));
  });

  const address = server.address();
  return {
    app,
    server,
    origin: `http://127.0.0.1:${address.port}`,
    async close() {
      await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
      await rm(uploadDir, { recursive: true, force: true });
    },
  };
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  startServer().then(({ origin }) => {
    console.log(`HTML Book PDF UI running at ${origin}`);
  });
}
```

```html
<!-- html-book-pdf/public/index.html -->
<link rel="stylesheet" href="/styles.css">
<main class="app">
  <h1>Drop HTML Here</h1>
  <label class="dropzone" id="dropzone">
    <input id="file-input" type="file" accept=".html,text/html" hidden>
    <span id="file-name">拖曳單一 HTML 檔到這裡，或點一下選檔</span>
  </label>
  <button id="convert-button" disabled>匯出 PDF</button>
  <p id="status" role="status">尚未選擇檔案</p>
</main>
<script type="module" src="/app.js"></script>
```

```js
// html-book-pdf/public/app.js
const dropzone = document.querySelector('#dropzone');
const fileInput = document.querySelector('#file-input');
const fileName = document.querySelector('#file-name');
const convertButton = document.querySelector('#convert-button');
const status = document.querySelector('#status');

let currentFile = null;

function setFile(file) {
  currentFile = file;
  fileName.textContent = file ? file.name : '拖曳單一 HTML 檔到這裡，或點一下選檔';
  convertButton.disabled = !file;
  status.textContent = file ? '準備輸出 PDF' : '尚未選擇檔案';
}

async function convertCurrentFile() {
  if (!currentFile) return;

  status.textContent = '正在輸出 PDF...';
  const form = new FormData();
  form.append('file', currentFile, currentFile.name);

  const response = await fetch('/api/render', { method: 'POST', body: form });
  if (!response.ok) throw new Error(await response.text());

  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = currentFile.name.replace(/\.html?$/i, '.pdf');
  link.click();
  URL.revokeObjectURL(url);
  status.textContent = 'PDF 已下載';
}

dropzone.addEventListener('dragover', (event) => {
  event.preventDefault();
  dropzone.dataset.dragging = 'true';
});

dropzone.addEventListener('dragleave', () => {
  delete dropzone.dataset.dragging;
});

dropzone.addEventListener('drop', (event) => {
  event.preventDefault();
  delete dropzone.dataset.dragging;
  setFile(event.dataTransfer.files[0] ?? null);
});

fileInput.addEventListener('change', () => setFile(fileInput.files[0] ?? null));
convertButton.addEventListener('click', () => convertCurrentFile().catch((error) => {
  status.textContent = error.message;
}));
```

```css
/* html-book-pdf/public/styles.css */
:root {
  color-scheme: light;
  --bg: #f4efe5;
  --panel: rgba(255, 252, 247, 0.88);
  --ink: #1e1a16;
  --muted: #6d6256;
  --line: #d9cbb8;
  --accent: #9c4f2f;
}

body {
  margin: 0;
  min-height: 100vh;
  display: grid;
  place-items: center;
  background: radial-gradient(circle at top, #fff8ef 0%, var(--bg) 58%, #eadfcd 100%);
  color: var(--ink);
  font: 16px/1.5 -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
}

.app {
  width: min(560px, calc(100vw - 48px));
  padding: 32px;
  border: 1px solid var(--line);
  border-radius: 24px;
  background: var(--panel);
  box-shadow: 0 24px 80px rgba(49, 31, 11, 0.12);
}

.dropzone {
  display: grid;
  place-items: center;
  min-height: 220px;
  margin: 24px 0 16px;
  border: 2px dashed var(--line);
  border-radius: 20px;
  text-align: center;
  cursor: pointer;
}

.dropzone[data-dragging='true'] {
  border-color: var(--accent);
  background: rgba(156, 79, 47, 0.08);
}
```

- [ ] **Step 4: Install dependencies and run test to verify it passes**

Run: `npm install`
Then run: `node --test test/server.test.js`
Expected: PASS, with `GET /` serving HTML and `POST /api/render` returning a PDF attachment.

- [ ] **Step 5: Commit**

```bash
git add html-book-pdf/package.json html-book-pdf/package-lock.json html-book-pdf/src/server.js html-book-pdf/public/index.html html-book-pdf/public/app.js html-book-pdf/public/styles.css html-book-pdf/test/server.test.js
git commit -m "feat: add desktop html to pdf upload ui"
```

### Task 3: Electron Shell and Packaging

**Files:**
- Modify: `html-book-pdf/package.json`
- Create: `html-book-pdf/src/main.js`
- Test: `html-book-pdf/test/package-config.test.js`

- [ ] **Step 1: Write the failing test**

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('package.json exposes electron entrypoint and cross-platform build targets', async () => {
  const pkg = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8'));

  assert.equal(pkg.main, 'src/main.js');
  assert.equal(pkg.scripts.electron, 'electron .');
  assert.equal(pkg.scripts.build, 'electron-builder');
  assert.deepEqual(pkg.build.mac.target, ['dmg', 'zip']);
  assert.deepEqual(pkg.build.win.target, ['nsis', 'portable']);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test test/package-config.test.js`
Expected: FAIL because `main`, `scripts.electron`, or `build.mac.target` are missing.

- [ ] **Step 3: Write minimal implementation**

```json
// html-book-pdf/package.json
{
  "main": "src/main.js",
  "scripts": {
    "test": "node --test",
    "ui": "node src/server.js",
    "electron": "electron .",
    "build": "electron-builder",
    "build:mac": "electron-builder --mac",
    "build:win": "electron-builder --win"
  },
  "devDependencies": {
    "electron": "^35.2.1",
    "electron-builder": "^25.1.8"
  },
  "build": {
    "appId": "com.punkcan.htmlbookpdf",
    "productName": "HTML Book PDF",
    "directories": { "output": "dist" },
    "files": ["public/**/*", "src/**/*", "node_modules/**/*", "package.json"],
    "mac": {
      "category": "public.app-category.productivity",
      "target": ["dmg", "zip"]
    },
    "win": {
      "target": ["nsis", "portable"]
    }
  }
}
```

```js
// html-book-pdf/src/main.js
import { app, BrowserWindow, dialog } from 'electron';
import { startServer } from './server.js';

let mainWindow;
let localServer;

async function createWindow() {
  localServer = await startServer({ port: 0 });

  mainWindow = new BrowserWindow({
    width: 920,
    height: 720,
    minWidth: 760,
    minHeight: 560,
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  await mainWindow.loadURL(localServer.origin);
}

app.whenReady().then(createWindow).catch(async (error) => {
  await dialog.showErrorBox('HTML Book PDF', error.message);
  app.quit();
});

app.on('window-all-closed', async () => {
  if (localServer) await localServer.close();
  if (process.platform !== 'darwin') app.quit();
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test test/package-config.test.js`
Expected: PASS with the new Electron entrypoint and build targets.

- [ ] **Step 5: Commit**

```bash
git add html-book-pdf/package.json html-book-pdf/package-lock.json html-book-pdf/src/main.js html-book-pdf/test/package-config.test.js
git commit -m "feat: package html book pdf as electron app"
```

### Task 4: Documentation and Full Verification

**Files:**
- Modify: `html-book-pdf/README.md`
- Modify: `README.md`

- [ ] **Step 1: Update desktop-app documentation**

````md
## Desktop App

```bash
cd /Users/punkcan/SourceCode/PunkcanTools/html-book-pdf
npm install
npm run electron
```

## Packaging

```bash
npm run build:mac
npm run build:win
```

拖入 `.html` 後，app 會輸出帶有每頁底部置中頁碼的 PDF。
````

- [ ] **Step 2: Run the full automated test suite**

Run: `npm test`
Expected: PASS for `book-pdf.test.js`, `server.test.js`, and `package-config.test.js`.

- [ ] **Step 3: Run the CLI smoke test with the provided fixture**

Run: `node src/cli.js /Users/punkcan/OrbStack/kaliHermes/home/punkcan/output/ai-first-publication.html -o /Users/punkcan/SourceCode/PunkcanTools/html-book-pdf/output/ai-first-publication.pdf`
Expected: PASS and regenerate `html-book-pdf/output/ai-first-publication.pdf` with page numbers.

- [ ] **Step 4: Run the desktop app locally and verify drag-drop conversion**

Run: `npm run electron`
Expected: App window opens, the provided HTML file can be dragged into the window, and the downloaded PDF contains centered bottom page numbers.

- [ ] **Step 5: Run the macOS package build**

Run: `npm run build:mac`
Expected: PASS and create artifacts under `html-book-pdf/dist/`.

- [ ] **Step 6: Verify Windows target configuration**

Run: `npm run build:win`
Expected: If the current machine can cross-build, PASS with `nsis` and `portable` artifacts. If not, record the exact failure and keep the packaging config checked in.

- [ ] **Step 7: Commit**

```bash
git add README.md html-book-pdf/README.md
git commit -m "docs: add desktop html book pdf usage"
```
