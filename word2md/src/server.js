#!/usr/bin/env node
import express from 'express';
import multer from 'multer';
import path from 'path';
import { fileURLToPath } from 'url';
import { convertFile } from './converter.js';
import fs from 'fs-extra';
import os from 'os';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 3456;

// 临时文件目录
const tempDir = path.join(os.tmpdir(), 'word2md-temp');
fs.ensureDirSync(tempDir);

// 文件上传配置
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, tempDir),
  filename: (req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`)
});
const upload = multer({ 
  storage,
  fileFilter: (req, file, cb) => {
    if (file.mimetype === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
      cb(null, true);
    } else {
      cb(new Error('只支持 .docx 文件'));
    }
  }
});

// 静态文件
app.use(express.static(path.join(__dirname, '../public')));

// 转换 API
app.post('/api/convert', upload.single('file'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: '请上传 .docx 文件' });
  }

  const inputPath = req.file.path;
  const outputPath = inputPath.replace('.docx', '.md');
  
  // 修复 multer 中文文件名编码问题 (Latin-1 -> UTF-8)
  const originalName = Buffer.from(req.file.originalname, 'latin1').toString('utf8');

  try {
    const result = await convertFile(inputPath, outputPath, { extractImages: false });
    
    if (result.success) {
      const markdown = await fs.readFile(outputPath, 'utf-8');
      // 清理临时文件
      await fs.remove(inputPath);
      await fs.remove(outputPath);
      
      res.json({ 
        success: true, 
        markdown,
        filename: originalName.replace('.docx', '.md')
      });
    } else {
      res.status(500).json({ error: result.message });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, () => {
  console.log(`\n🚀 Word2MD UI 已启动`);
  console.log(`   访问: http://localhost:${PORT}\n`);
});
