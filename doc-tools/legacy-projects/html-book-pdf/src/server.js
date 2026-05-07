import express from 'express';
import multer from 'multer';
import { createReadStream } from 'node:fs';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { convertHtmlToPdf } from './book-pdf.js';

const publicDir = fileURLToPath(new URL('../public/', import.meta.url));

export async function startServer({ port = 3457, renderHtmlFile = convertHtmlToPdf } = {}) {
  const app = express();
  const uploadDir = await fs.mkdtemp(path.join(os.tmpdir(), 'html-book-pdf-upload-'));
  const upload = multer({ dest: uploadDir });

  app.use(express.static(publicDir));

  app.get('/', async (_req, res) => {
    const htmlPath = path.join(publicDir, 'index.html');
    res.type('html').send(await fs.readFile(htmlPath, 'utf8'));
  });

  app.post('/api/render', upload.single('file'), async (req, res) => {
    try {
      if (!req.file || !isHtmlFilename(req.file.originalname)) {
        res.status(400).json({ error: '請上傳 .html 檔案' });
        return;
      }

      const parsedName = path.parse(req.file.originalname);
      const outputPath = path.join(uploadDir, `${parsedName.name}.pdf`);
      const result = await renderHtmlFile({
        input: req.file.path,
        output: outputPath,
      });

      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-Disposition', `attachment; filename="${parsedName.name}.pdf"`);
      createReadStream(result.outputPath).pipe(res);
    } catch (error) {
      res.status(500).json({ error: error.message });
    } finally {
      if (req.file?.path) {
        await fs.rm(req.file.path, { force: true });
      }
    }
  });

  const server = await new Promise((resolve, reject) => {
    const instance = app.listen(port, '127.0.0.1', () => {
      resolve(instance);
    });
    instance.on('error', reject);
  });

  const address = server.address();
  if (!address || typeof address !== 'object') {
    throw new Error('無法取得本機 server 連線資訊');
  }

  return {
    app,
    server,
    origin: `http://127.0.0.1:${address.port}`,
    async close() {
      await new Promise((resolve, reject) => {
        server.close((error) => {
          if (error) {
            reject(error);
            return;
          }
          resolve();
        });
      });
      await fs.rm(uploadDir, { recursive: true, force: true });
    },
  };
}

function isHtmlFilename(name) {
  const lower = name.toLowerCase();
  return lower.endsWith('.html') || lower.endsWith('.htm');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  startServer().then(({ origin }) => {
    // Keep this line for local desktop startup debugging.
    console.log(`HTML Book PDF UI running at ${origin}`);
  }).catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}
