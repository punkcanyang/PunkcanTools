const dropzone = document.querySelector('#dropzone');
const fileInput = document.querySelector('#file-input');
const fileName = document.querySelector('#file-name');
const convertButton = document.querySelector('#convert-button');
const statusText = document.querySelector('#status');

let currentFile = null;

function setFile(file) {
  currentFile = file;
  fileName.textContent = file ? file.name : '拖曳單一 HTML 檔案到此處，或點擊選檔';
  convertButton.disabled = !file;
  statusText.textContent = file ? '已就緒，按下匯出 PDF。' : '尚未選擇檔案';
}

function isHtmlFile(file) {
  if (!file) {
    return false;
  }

  return /\.html?$/i.test(file.name);
}

async function convertCurrentFile() {
  if (!currentFile) {
    return;
  }

  statusText.textContent = '正在輸出 PDF...';
  convertButton.disabled = true;

  try {
    const formData = new FormData();
    formData.append('file', currentFile, currentFile.name);

    const response = await fetch('/api/render', {
      method: 'POST',
      body: formData,
    });

    if (!response.ok) {
      throw new Error(await response.text());
    }

    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = currentFile.name.replace(/\.html?$/i, '.pdf');
    link.click();
    URL.revokeObjectURL(url);

    statusText.textContent = '完成，PDF 已下載。';
  } catch (error) {
    statusText.textContent = `轉檔失敗：${error.message}`;
  } finally {
    convertButton.disabled = !currentFile;
  }
}

dropzone.addEventListener('click', () => {
  fileInput.click();
});

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

  const file = event.dataTransfer?.files?.[0] ?? null;
  if (!isHtmlFile(file)) {
    setFile(null);
    statusText.textContent = '只接受 .html 或 .htm 檔案。';
    return;
  }

  setFile(file);
});

fileInput.addEventListener('change', () => {
  const file = fileInput.files?.[0] ?? null;
  if (!isHtmlFile(file)) {
    setFile(null);
    statusText.textContent = '只接受 .html 或 .htm 檔案。';
    return;
  }

  setFile(file);
});

convertButton.addEventListener('click', () => {
  convertCurrentFile().catch((error) => {
    statusText.textContent = `轉檔失敗：${error.message}`;
  });
});
