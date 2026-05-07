import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildPrintToPdfOptions,
  buildPrintCss,
  createPageNumberFooterTemplate,
  createPrintReadyHtml,
  parseCliArgs,
  resolveOutputPath,
} from '../src/book-pdf.js';

test('parseCliArgs parses input, output, browser, and wait options', () => {
  const parsed = parseCliArgs([
    'chapter.html',
    '--output',
    'chapter.pdf',
    '--browser',
    'brave',
    '--wait',
    '1500',
    '--page-selector',
    '.page',
    '--format',
    'A4',
    '--margin',
    '20mm',
  ]);

  assert.equal(parsed.input, 'chapter.html');
  assert.equal(parsed.output, 'chapter.pdf');
  assert.equal(parsed.browser, 'brave');
  assert.equal(parsed.wait, 1500);
  assert.equal(parsed.pageSelector, '.page');
  assert.equal(parsed.format, 'A4');
  assert.equal(parsed.margin, '20mm');
});

test('buildPrintCss only emits the requested publication overrides', () => {
  const css = buildPrintCss({
    format: 'A5',
    margin: '18mm',
    pageSelector: '.sheet',
    extraCss: '.cover { color: #222; }',
  });

  assert.match(css, /@page\s*\{\s*size:\s*A5;/);
  assert.match(css, /margin:\s*18mm;/);
  assert.match(css, /\.sheet\s*\{/);
  assert.match(css, /break-after:\s*page;/);
  assert.match(css, /\.cover\s*\{\s*color:\s*#222;/);
});

test('createPrintReadyHtml injects base and print css into existing head', () => {
  const html = createPrintReadyHtml({
    html: '<html><head><title>Demo</title></head><body><h1>Demo</h1></body></html>',
    baseHref: 'file:///Users/punkcan/book/',
    printCss: 'body { color: black; }',
  });

  assert.match(html, /<base href="file:\/\/\/Users\/punkcan\/book\/">/);
  assert.match(html, /<style data-html-book-pdf>/);
  assert.match(html, /body \{ color: black; \}/);
  assert.match(html, /<title>Demo<\/title>/);
});

test('resolveOutputPath defaults beside the source html', () => {
  const outputPath = resolveOutputPath({
    inputPath: '/tmp/books/issue-01.html',
  });

  assert.equal(outputPath, '/tmp/books/issue-01.pdf');
});

test('createPageNumberFooterTemplate renders centered page numbers', () => {
  const footer = createPageNumberFooterTemplate();

  assert.match(footer, /text-align:\s*center/);
  assert.match(footer, /class="pageNumber"/);
  assert.doesNotMatch(footer, /class="totalPages"/);
});

test('buildPrintToPdfOptions enables header footer with css page size', () => {
  const options = buildPrintToPdfOptions({
    footerTemplate: '<div><span class="pageNumber"></span></div>',
  });

  assert.equal(options.displayHeaderFooter, true);
  assert.equal(options.printBackground, true);
  assert.equal(options.preferCSSPageSize, true);
  assert.equal(options.headerTemplate, '<div></div>');
  assert.match(options.footerTemplate, /pageNumber/);
});
