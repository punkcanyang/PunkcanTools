#!/usr/bin/env node
const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs-extra');
const os = require('os');
const mammoth = require('mammoth');

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

// HTML to Markdown 转换函数
function stripHtml(html) {
  return html
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .trim();
}

function convertTable(tableHtml) {
  const rows = [];
  const rowMatches = tableHtml.match(/<tr[^>]*>[\s\S]*?<\/tr>/gi) || [];
  
  for (const rowHtml of rowMatches) {
    const cells = [];
    const cellMatches = rowHtml.match(/<(th|td)[^>]*>([\s\S]*?)<\/\1>/gi) || [];
    
    for (const cellHtml of cellMatches) {
      const content = cellHtml.replace(/<(th|td)[^>]*>([\s\S]*?)<\/\1>/i, '$2');
      const cleanContent = stripHtml(content).replace(/\n/g, ' ');
      cells.push(cleanContent);
    }
    
    if (cells.length > 0) rows.push(cells);
  }
  
  if (rows.length === 0) return '';
  
  const maxCols = Math.max(...rows.map(r => r.length));
  let md = '\n';
  
  rows.forEach((row, rowIndex) => {
    while (row.length < maxCols) row.push('');
    md += '| ' + row.join(' | ') + ' |\n';
    if (rowIndex === 0) {
      md += '| ' + row.map(() => '---').join(' | ') + ' |\n';
    }
  });
  
  return md + '\n';
}

function htmlToMarkdown(html) {
  let md = html;
  md = md.replace(/<table[^>]*>[\s\S]*?<\/table>/gi, (match) => convertTable(match));
  md = md.replace(/<h1[^>]*>(.*?)<\/h1>/gi, '# $1\n\n');
  md = md.replace(/<h2[^>]*>(.*?)<\/h2>/gi, '## $1\n\n');
  md = md.replace(/<h3[^>]*>(.*?)<\/h3>/gi, '### $1\n\n');
  md = md.replace(/<h4[^>]*>(.*?)<\/h4>/gi, '#### $1\n\n');
  md = md.replace(/<h5[^>]*>(.*?)<\/h5>/gi, '##### $1\n\n');
  md = md.replace(/<h6[^>]*>(.*?)<\/h6>/gi, '###### $1\n\n');
  md = md.replace(/<strong>(.*?)<\/strong>/gi, '**$1**');
  md = md.replace(/<b>(.*?)<\/b>/gi, '**$1**');
  md = md.replace(/<em>(.*?)<\/em>/gi, '*$1*');
  md = md.replace(/<i>(.*?)<\/i>/gi, '*$1*');
  md = md.replace(/<a[^>]*href="([^"]*)"[^>]*>(.*?)<\/a>/gi, '[$2]($1)');
  md = md.replace(/<img[^>]*src="([^"]*)"[^>]*alt="([^"]*)"[^>]*\/?>/gi, '![$2]($1)');
  md = md.replace(/<img[^>]*src="([^"]*)"[^>]*\/?>/gi, '![]($1)');
  md = md.replace(/<ul>/gi, '\n');
  md = md.replace(/<\/ul>/gi, '\n');
  md = md.replace(/<li>(.*?)<\/li>/gi, '- $1\n');
  md = md.replace(/<ol>/gi, '\n');
  md = md.replace(/<\/ol>/gi, '\n');
  md = md.replace(/<p>(.*?)<\/p>/gi, '$1\n\n');
  md = md.replace(/<br\s*\/?>/gi, '\n');
  md = md.replace(/<code>(.*?)<\/code>/gi, '`$1`');
  md = md.replace(/<pre>(.*?)<\/pre>/gis, '```\n$1\n```\n');
  md = md.replace(/<hr\s*\/?>/gi, '\n---\n');
  md = md.replace(/<[^>]+>/g, '');
  md = md.replace(/\n{3,}/g, '\n\n');
  md = md.replace(/&nbsp;/g, ' ');
  md = md.replace(/&amp;/g, '&');
  md = md.replace(/&lt;/g, '<');
  md = md.replace(/&gt;/g, '>');
  md = md.replace(/&quot;/g, '"');
  return md.trim();
}

// 转换 API
app.post('/api/convert', upload.single('file'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: '请上传 .docx 文件' });
  }

  const inputPath = req.file.path;
  const originalName = Buffer.from(req.file.originalname, 'latin1').toString('utf8');

  try {
    const result = await mammoth.convertToHtml({ path: inputPath });
    const markdown = htmlToMarkdown(result.value);
    
    // 清理临时文件
    await fs.remove(inputPath);
    
    res.json({ 
      success: true, 
      markdown,
      filename: originalName.replace('.docx', '.md')
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const server = app.listen(PORT, () => {
  console.log(`\n🚀 Word2MD UI 已启动`);
  console.log(`   访问: http://localhost:${PORT}\n`);
});

module.exports = { app, server };
