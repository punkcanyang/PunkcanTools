const tauriInvoke = window.__TAURI__?.core?.invoke ?? null;

const tabButtons = [...document.querySelectorAll('.tab-button')];
const panels = {
  html2pdf: document.querySelector('#panel-html2pdf'),
  docx2md: document.querySelector('#panel-docx2md'),
};

const htmlState = createConverterState({
  dropzone: '#html-dropzone',
  input: '#html-input',
  fileName: '#html-file-name',
  pageNumbersToggle: '#html-page-numbers',
  button: '#html-convert',
  status: '#html-status',
  accept: /\.html?$/i,
  idleText: '拖曳 HTML 檔案到這裡，或點擊選檔',
});

const docxState = createConverterState({
  dropzone: '#docx-dropzone',
  input: '#docx-input',
  fileName: '#docx-file-name',
  button: '#docx-convert',
  status: '#docx-status',
  accept: /\.docx$/i,
  idleText: '拖曳 DOCX 檔案到這裡，或點擊選檔',
});

bootstrap();

function bootstrap() {
  try {
    setupTabs();
    setupHtmlConverter();
    setupDocxConverter();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('Doc Tools 初始化失敗：', error);
    [htmlState.status, docxState.status].forEach((statusNode) => {
      if (statusNode) {
        statusNode.textContent = `介面初始化失敗：${message}`;
      }
    });
  }
}

function setupTabs() {
  tabButtons.forEach((button) => {
    button.addEventListener('click', () => {
      const tab = button.dataset.tab;
      tabButtons.forEach((node) => node.classList.toggle('active', node === button));
      Object.entries(panels).forEach(([key, panel]) => {
        panel.classList.toggle('active', key === tab);
      });
    });
  });
}

function setupHtmlConverter() {
  wireDropzone(htmlState);
  htmlState.button.addEventListener('click', () => {
    convertHtml().catch((error) => {
      htmlState.status.textContent = `轉換失敗：${error.message}`;
    });
  });
}

function setupDocxConverter() {
  wireDropzone(docxState);
  docxState.button.addEventListener('click', () => {
    convertDocx().catch((error) => {
      docxState.status.textContent = `轉換失敗：${error.message}`;
    });
  });
}

function createConverterState({
  dropzone,
  input,
  fileName,
  pageNumbersToggle,
  button,
  status,
  accept,
  idleText,
}) {
  return {
    dropzone: requireElement(dropzone),
    input: requireElement(input),
    fileName: requireElement(fileName),
    pageNumbersToggle: pageNumbersToggle ? requireElement(pageNumbersToggle) : null,
    button: requireElement(button),
    status: requireElement(status),
    accept,
    idleText,
    file: null,
  };
}

function requireElement(selector) {
  const element = document.querySelector(selector);
  if (!element) {
    throw new Error(`找不到必要元素：${selector}`);
  }
  return element;
}

function wireDropzone(state) {
  state.dropzone.addEventListener('click', () => {
    state.status.textContent = '已觸發選檔，請在對話框中選擇檔案。';
    state.input.click();
  });
  state.dropzone.addEventListener('dragover', (event) => {
    event.preventDefault();
    state.dropzone.dataset.dragging = 'true';
  });
  state.dropzone.addEventListener('dragleave', () => {
    delete state.dropzone.dataset.dragging;
  });
  state.dropzone.addEventListener('drop', (event) => {
    event.preventDefault();
    delete state.dropzone.dataset.dragging;
    const file = event.dataTransfer?.files?.[0] ?? null;
    updateSelectedFile(state, file);
  });
  state.input.addEventListener('change', () => {
    state.status.textContent = '已收到檔案變更事件，正在檢查格式...';
    updateSelectedFile(state, state.input.files?.[0] ?? null);
  });
}

function updateSelectedFile(state, file) {
  if (!file || !state.accept.test(file.name)) {
    state.file = null;
    state.fileName.textContent = state.idleText;
    state.button.disabled = true;
    state.status.textContent = file ? '檔案格式不符，請重新選擇。' : '尚未選擇檔案';
    return;
  }

  state.file = file;
  state.fileName.textContent = file.name;
  state.button.disabled = false;
  state.status.textContent = '檔案已就緒，點擊按鈕開始轉換。';
}

async function convertHtml() {
  if (!htmlState.file) {
    return;
  }

  if (!tauriInvoke) {
    throw new Error('找不到 Tauri API，請從桌面 App 啟動。');
  }

  htmlState.button.disabled = true;
  htmlState.status.textContent = '正在輸出 PDF...';

  try {
    const htmlContent = await htmlState.file.text();
    const includePageNumbers = htmlState.pageNumbersToggle?.checked ?? true;
    const pdfBase64 = await tauriInvoke('convert_html_to_pdf', {
      htmlContent,
      includePageNumbers,
    });
    const outputName = htmlState.file.name.replace(/\.html?$/i, '.pdf');
    saveBase64File(pdfBase64, outputName, 'application/pdf');
    htmlState.status.textContent = includePageNumbers
      ? `完成：${outputName}（含頁碼）`
      : `完成：${outputName}（不含頁碼）`;
  } finally {
    htmlState.button.disabled = !htmlState.file;
  }
}

async function convertDocx() {
  if (!docxState.file) {
    return;
  }

  if (!tauriInvoke) {
    throw new Error('找不到 Tauri API，請從桌面 App 啟動。');
  }

  docxState.button.disabled = true;
  docxState.status.textContent = '正在轉換 Markdown...';

  try {
    const buffer = await docxState.file.arrayBuffer();
    const docxBase64 = bytesToBase64(new Uint8Array(buffer));
    const markdown = await tauriInvoke('convert_docx_to_markdown', { docxBase64 });
    const outputName = docxState.file.name.replace(/\.docx$/i, '.md');
    saveTextFile(markdown, outputName, 'text/markdown;charset=utf-8');
    docxState.status.textContent = `完成：${outputName}`;
  } finally {
    docxState.button.disabled = !docxState.file;
  }
}

function saveBase64File(base64Content, filename, mimeType) {
  const bytes = base64ToBytes(base64Content);
  const blob = new Blob([bytes], { type: mimeType });
  triggerDownload(blob, filename);
}

function saveTextFile(content, filename, mimeType) {
  const blob = new Blob([content], { type: mimeType });
  triggerDownload(blob, filename);
}

function triggerDownload(blob, filename) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

function bytesToBase64(bytes) {
  let binary = '';
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    const chunk = bytes.subarray(offset, offset + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary);
}

function base64ToBytes(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}
