import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { renderPdfWithCdp } from './pdf-cdp.js';

const BROWSER_CANDIDATES = {
  chrome: [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
  ],
  brave: [
    '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
    '/usr/bin/brave-browser',
  ],
  edge: [
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '/usr/bin/microsoft-edge',
  ],
};

const CLI_OPTIONS = {
  '-o': 'output',
  '--output': 'output',
  '--browser': 'browser',
  '--browser-path': 'browserPath',
  '--wait': 'wait',
  '--page-selector': 'pageSelector',
  '--format': 'format',
  '--margin': 'margin',
  '--css': 'cssPath',
  '--keep-temp': 'keepTemp',
  '--verbose': 'verbose',
  '--help': 'help',
};

const BOOLEAN_OPTIONS = new Set(['keepTemp', 'verbose', 'help']);

export function parseCliArgs(argv) {
  const parsed = {
    browser: 'auto',
    wait: 1200,
    keepTemp: false,
    verbose: false,
    help: false,
  };

  const positionals = [];

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];

    if (!token.startsWith('-')) {
      positionals.push(token);
      continue;
    }

    const optionName = CLI_OPTIONS[token];
    if (!optionName) {
      throw new Error(`未知參數: ${token}`);
    }

    if (BOOLEAN_OPTIONS.has(optionName)) {
      parsed[optionName] = true;
      continue;
    }

    const value = argv[index + 1];
    if (!value || value.startsWith('-')) {
      throw new Error(`參數 ${token} 缺少值`);
    }

    parsed[optionName] = optionName === 'wait' ? Number(value) : value;
    index += 1;
  }

  if (Number.isNaN(parsed.wait) || parsed.wait < 0) {
    throw new Error('--wait 必須是大於等於 0 的毫秒數');
  }

  parsed.input = positionals[0];

  return parsed;
}

export function buildPrintCss({ format, margin, pageSelector, extraCss = '' }) {
  const cssBlocks = [
    `
html {
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}

body {
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
`.trim(),
  ];

  if (format || margin) {
    const declarations = [];
    if (format) {
      declarations.push(`size: ${format};`);
    }
    if (margin) {
      declarations.push(`margin: ${margin};`);
    }
    cssBlocks.push(`@page {\n  ${declarations.join('\n  ')}\n}`);
  }

  if (pageSelector) {
    cssBlocks.push(`
${pageSelector} {
  break-after: page;
  page-break-after: always;
}

${pageSelector}:last-child {
  break-after: auto;
  page-break-after: auto;
}
    `.trim());
  }

  if (extraCss.trim()) {
    cssBlocks.push(extraCss.trim());
  }

  return `${cssBlocks.join('\n\n')}\n`;
}

export function createPrintReadyHtml({ html, baseHref, printCss }) {
  const styleTag = `<style data-html-book-pdf>\n${printCss}\n</style>`;
  const baseTag = `<base href="${escapeHtmlAttribute(baseHref)}">`;

  let nextHtml = html;

  if (!/<head[\s>]/i.test(nextHtml)) {
    if (/<html[\s>]/i.test(nextHtml)) {
      nextHtml = nextHtml.replace(/<html([^>]*)>/i, '<html$1><head></head>');
    } else {
      nextHtml = `<html><head></head><body>${nextHtml}</body></html>`;
    }
  }

  if (/<base[\s>]/i.test(nextHtml)) {
    nextHtml = nextHtml.replace(/<base[^>]*>/i, baseTag);
  } else {
    nextHtml = nextHtml.replace(/<head([^>]*)>/i, `<head$1>${baseTag}`);
  }

  if (/<\/head>/i.test(nextHtml)) {
    nextHtml = nextHtml.replace(/<\/head>/i, `${styleTag}</head>`);
  } else {
    nextHtml = `${nextHtml}${styleTag}`;
  }

  return nextHtml;
}

export function resolveOutputPath({ inputPath, outputPath }) {
  if (outputPath) {
    return path.resolve(outputPath);
  }

  const inputDir = path.dirname(inputPath);
  const inputName = path.basename(inputPath, path.extname(inputPath));
  return path.join(inputDir, `${inputName}.pdf`);
}

export function createPageNumberFooterTemplate() {
  return `
<div style="width:100%;padding:0 0 6px;text-align:center;font-size:9px;color:#666;">
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
  };
}

export function printUsage() {
  return `
html-book-pdf <input.html> [options]

把已經排版好的 HTML 轉成可列印的分頁 PDF。

選項:
  -o, --output <file>          指定輸出 PDF 路徑
      --browser <name>         指定瀏覽器: chrome | brave | edge | auto
      --browser-path <path>    直接指定 Chromium 系瀏覽器執行檔
      --wait <ms>              載入後額外等待毫秒數，預設 1200
      --page-selector <css>    對指定區塊自動加上每頁斷頁規則
      --format <size>          強制指定紙張，例如 A4、A5、Letter
      --margin <value>         強制指定 @page 邊界，例如 20mm
      --css <file>             額外注入的 print CSS 檔案
      --keep-temp              保留暫存 HTML 方便除錯
      --verbose                顯示實際使用的瀏覽器與暫存檔
      --help                   顯示說明

範例:
  html-book-pdf ./book.html -o ./book.pdf
  html-book-pdf ./book.html -o ./book.pdf --page-selector .page
  html-book-pdf ./book.html -o ./book.pdf --format A4 --margin 20mm --css ./print-overrides.css
`.trim();
}

export async function convertHtmlToPdf(options) {
  if (!options.input) {
    throw new Error('請提供 HTML 檔案路徑');
  }

  const inputPath = await resolveInputPath(options.input);
  const outputPath = resolveOutputPath({
    inputPath,
    outputPath: options.output,
  });
  const browserPath = await detectBrowserPath(options);
  const extraCss = options.cssPath ? await fs.readFile(path.resolve(options.cssPath), 'utf8') : '';
  const printCss = buildPrintCss({
    format: options.format,
    margin: options.margin,
    pageSelector: options.pageSelector,
    extraCss,
  });

  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'html-book-pdf-'));
  const tempHtmlPath = path.join(
    tempRoot,
    `${path.basename(inputPath, path.extname(inputPath))}.print.html`,
  );

  try {
    await fs.mkdir(path.dirname(outputPath), { recursive: true });

    const originalHtml = await fs.readFile(inputPath, 'utf8');
    const baseHref = ensureTrailingSlash(pathToFileURL(`${path.dirname(inputPath)}${path.sep}`).href);
    const printReadyHtml = createPrintReadyHtml({
      html: originalHtml,
      baseHref,
      printCss,
    });

    await fs.writeFile(tempHtmlPath, printReadyHtml, 'utf8');

    const inputUrl = pathToFileURL(tempHtmlPath).href;
    const footerTemplate = createPageNumberFooterTemplate();
    const pdfOptions = buildPrintToPdfOptions({ footerTemplate });

    await renderPdfWithCdp({
      browserPath,
      inputUrl,
      outputPath,
      wait: options.wait ?? 1200,
      pdfOptions,
      verbose: options.verbose,
    });

    await fs.access(outputPath);

    return {
      browserPath,
      outputPath,
      tempHtmlPath,
      usedPrintCss: printCss,
    };
  } finally {
    if (!options.keepTemp) {
      await fs.rm(tempRoot, { recursive: true, force: true });
    }
  }
}

async function resolveInputPath(input) {
  const absolutePath = input.startsWith('file://')
    ? fileURLToPath(input)
    : path.resolve(input);

  await fs.access(absolutePath);
  return absolutePath;
}

async function detectBrowserPath(options) {
  if (options.browserPath) {
    const explicitPath = path.resolve(options.browserPath);
    await fs.access(explicitPath);
    return explicitPath;
  }

  const order = options.browser && options.browser !== 'auto'
    ? [options.browser]
    : ['chrome', 'brave', 'edge'];

  for (const browserName of order) {
    const candidates = BROWSER_CANDIDATES[browserName] ?? [];
    for (const candidate of candidates) {
      try {
        await fs.access(candidate);
        return candidate;
      } catch {
        // Try next candidate.
      }
    }
  }

  throw new Error(
    '找不到可用的 Chromium 瀏覽器。請安裝 Chrome / Brave / Edge，或用 --browser-path 指定執行檔。',
  );
}

function ensureTrailingSlash(value) {
  return value.endsWith('/') ? value : `${value}/`;
}

function escapeHtmlAttribute(value) {
  return value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
}
