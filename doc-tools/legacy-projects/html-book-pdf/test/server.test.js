import { mkdtemp, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import { startServer } from '../src/server.js';

test('GET / serves the desktop shell html', async () => {
  const server = await startServer({
    port: 0,
    renderHtmlFile: async () => {
      throw new Error('render should not be called');
    },
  });

  try {
    const response = await fetch(`${server.origin}/`);
    const html = await response.text();

    assert.equal(response.status, 200);
    assert.match(html, /Drop HTML Here/i);
  } finally {
    await server.close();
  }
});

test('POST /api/render returns a pdf attachment for html upload', async () => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), 'html-book-pdf-server-test-'));
  const fakePdfPath = path.join(tempDir, 'rendered.pdf');
  await writeFile(fakePdfPath, '%PDF-1.4\n');

  const server = await startServer({
    port: 0,
    renderHtmlFile: async () => ({ outputPath: fakePdfPath }),
  });

  try {
    const form = new FormData();
    form.append('file', new Blob(['<html><body>Hello</body></html>'], { type: 'text/html' }), 'demo.html');

    const response = await fetch(`${server.origin}/api/render`, {
      method: 'POST',
      body: form,
    });

    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), 'application/pdf');
    assert.match(response.headers.get('content-disposition'), /attachment; filename="demo.pdf"/);
  } finally {
    await server.close();
  }
});

test('POST /api/render rejects non-html uploads', async () => {
  const server = await startServer({
    port: 0,
    renderHtmlFile: async () => ({ outputPath: '/tmp/unused.pdf' }),
  });

  try {
    const form = new FormData();
    form.append('file', new Blob(['plain text'], { type: 'text/plain' }), 'demo.txt');

    const response = await fetch(`${server.origin}/api/render`, {
      method: 'POST',
      body: form,
    });

    assert.equal(response.status, 400);
    const body = await response.text();
    assert.match(body, /html/i);
  } finally {
    await server.close();
  }
});
