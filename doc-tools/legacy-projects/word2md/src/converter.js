import mammoth from 'mammoth';
import fs from 'fs-extra';
import path from 'path';

/**
 * 解析单元格内容，去除 HTML 标签
 */
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

/**
 * 将 HTML 表格转换为 Markdown 表格
 */
function convertTable(tableHtml) {
  const rows = [];
  
  // 匹配所有行
  const rowMatches = tableHtml.match(/<tr[^>]*>[\s\S]*?<\/tr>/gi) || [];
  
  for (const rowHtml of rowMatches) {
    const cells = [];
    
    // 匹配所有单元格 (th 或 td)
    const cellMatches = rowHtml.match(/<(th|td)[^>]*>([\s\S]*?)<\/\1>/gi) || [];
    
    for (const cellHtml of cellMatches) {
      // 提取单元格内容
      const content = cellHtml.replace(/<(th|td)[^>]*>([\s\S]*?)<\/\1>/i, '$2');
      // 清理内容：去除 HTML 标签，处理换行
      const cleanContent = stripHtml(content).replace(/\n/g, ' ');
      cells.push(cleanContent);
    }
    
    if (cells.length > 0) {
      rows.push(cells);
    }
  }
  
  if (rows.length === 0) {
    return '';
  }
  
  // 计算最大列数
  const maxCols = Math.max(...rows.map(r => r.length));
  
  // 构建 Markdown 表格
  let md = '\n';
  
  rows.forEach((row, rowIndex) => {
    // 补齐列数
    while (row.length < maxCols) {
      row.push('');
    }
    
    // 生成行
    md += '| ' + row.join(' | ') + ' |\n';
    
    // 第一行后添加分隔行
    if (rowIndex === 0) {
      md += '| ' + row.map(() => '---').join(' | ') + ' |\n';
    }
  });
  
  return md + '\n';
}

/**
 * 将 HTML 转换为 Markdown
 * mammoth 输出 HTML，我们需要将其转换为 Markdown
 */
function htmlToMarkdown(html) {
  let md = html;

  // 先处理表格（在其他处理之前，因为表格内可能有其他标签）
  md = md.replace(/<table[^>]*>[\s\S]*?<\/table>/gi, (match) => {
    return convertTable(match);
  });

  // 处理标题
  md = md.replace(/<h1[^>]*>(.*?)<\/h1>/gi, '# $1\n\n');
  md = md.replace(/<h2[^>]*>(.*?)<\/h2>/gi, '## $1\n\n');
  md = md.replace(/<h3[^>]*>(.*?)<\/h3>/gi, '### $1\n\n');
  md = md.replace(/<h4[^>]*>(.*?)<\/h4>/gi, '#### $1\n\n');
  md = md.replace(/<h5[^>]*>(.*?)<\/h5>/gi, '##### $1\n\n');
  md = md.replace(/<h6[^>]*>(.*?)<\/h6>/gi, '###### $1\n\n');

  // 处理粗体和斜体
  md = md.replace(/<strong>(.*?)<\/strong>/gi, '**$1**');
  md = md.replace(/<b>(.*?)<\/b>/gi, '**$1**');
  md = md.replace(/<em>(.*?)<\/em>/gi, '*$1*');
  md = md.replace(/<i>(.*?)<\/i>/gi, '*$1*');

  // 处理链接
  md = md.replace(/<a[^>]*href="([^"]*)"[^>]*>(.*?)<\/a>/gi, '[$2]($1)');

  // 处理图片
  md = md.replace(/<img[^>]*src="([^"]*)"[^>]*alt="([^"]*)"[^>]*\/?>/gi, '![$2]($1)');
  md = md.replace(/<img[^>]*src="([^"]*)"[^>]*\/?>/gi, '![]($1)');

  // 处理无序列表
  md = md.replace(/<ul>/gi, '\n');
  md = md.replace(/<\/ul>/gi, '\n');
  md = md.replace(/<li>(.*?)<\/li>/gi, '- $1\n');

  // 处理有序列表 (简化处理，全部用 1.)
  md = md.replace(/<ol>/gi, '\n');
  md = md.replace(/<\/ol>/gi, '\n');

  // 处理段落
  md = md.replace(/<p>(.*?)<\/p>/gi, '$1\n\n');

  // 处理换行
  md = md.replace(/<br\s*\/?>/gi, '\n');

  // 处理代码
  md = md.replace(/<code>(.*?)<\/code>/gi, '`$1`');
  md = md.replace(/<pre>(.*?)<\/pre>/gis, '```\n$1\n```\n');

  // 处理水平线
  md = md.replace(/<hr\s*\/?>/gi, '\n---\n');

  // 清理剩余的 HTML 标签
  md = md.replace(/<[^>]+>/g, '');

  // 清理多余的空行
  md = md.replace(/\n{3,}/g, '\n\n');

  // 清理 HTML 实体
  md = md.replace(/&nbsp;/g, ' ');
  md = md.replace(/&amp;/g, '&');
  md = md.replace(/&lt;/g, '<');
  md = md.replace(/&gt;/g, '>');
  md = md.replace(/&quot;/g, '"');

  return md.trim();
}

/**
 * 转换单个 Word 文件为 Markdown
 * @param {string} inputPath - 输入的 docx 文件路径
 * @param {string} outputPath - 输出的 md 文件路径
 * @param {Object} options - 转换选项
 * @returns {Promise<{success: boolean, message: string, images: string[]}>}
 */
export async function convertFile(inputPath, outputPath, options = {}) {
  const { extractImages = true } = options;

  try {
    // 确保输入文件存在
    if (!await fs.pathExists(inputPath)) {
      return { success: false, message: `文件不存在: ${inputPath}`, images: [] };
    }

    // 确保输出目录存在
    const outputDir = path.dirname(outputPath);
    await fs.ensureDir(outputDir);

    // 图片保存目录
    const imagesDir = path.join(outputDir, 'images');
    const extractedImages = [];

    // 配置 mammoth 选项
    const mammothOptions = {
      path: inputPath
    };

    // 如果需要提取图片
    if (extractImages) {
      await fs.ensureDir(imagesDir);
      let imageIndex = 0;
      
      mammothOptions.convertImage = mammoth.images.imgElement(async (image) => {
        const extension = image.contentType.split('/')[1] || 'png';
        const imageName = `image_${++imageIndex}.${extension}`;
        const imagePath = path.join(imagesDir, imageName);
        
        const buffer = await image.read();
        await fs.writeFile(imagePath, buffer);
        
        extractedImages.push(imagePath);
        
        // 返回相对路径
        return { src: `./images/${imageName}` };
      });
    }

    // 执行转换
    const result = await mammoth.convertToHtml(mammothOptions);

    // 转换 HTML 为 Markdown
    const markdown = htmlToMarkdown(result.value);

    // 写入输出文件
    await fs.writeFile(outputPath, markdown, 'utf-8');

    // 返回警告信息
    const warnings = result.messages
      .filter(m => m.type === 'warning')
      .map(m => m.message);

    let message = `转换成功: ${path.basename(inputPath)} -> ${path.basename(outputPath)}`;
    if (warnings.length > 0) {
      message += `\n  警告: ${warnings.join(', ')}`;
    }
    if (extractedImages.length > 0) {
      message += `\n  提取了 ${extractedImages.length} 张图片`;
    }

    return { success: true, message, images: extractedImages };

  } catch (error) {
    return { success: false, message: `转换失败: ${error.message}`, images: [] };
  }
}

/**
 * 批量转换目录中的 Word 文件
 * @param {string} inputDir - 输入目录
 * @param {string} outputDir - 输出目录
 * @param {Object} options - 转换选项
 * @returns {Promise<{total: number, success: number, failed: number, results: Array}>}
 */
export async function convertDirectory(inputDir, outputDir, options = {}) {
  const { recursive = false } = options;

  try {
    // 确保输入目录存在
    if (!await fs.pathExists(inputDir)) {
      throw new Error(`目录不存在: ${inputDir}`);
    }

    // 获取所有 docx 文件
    const pattern = recursive ? '**/*.docx' : '*.docx';
    const files = await fs.readdir(inputDir);
    const docxFiles = files.filter(f => f.endsWith('.docx') && !f.startsWith('~$'));

    const results = [];
    let successCount = 0;
    let failedCount = 0;

    for (const file of docxFiles) {
      const inputPath = path.join(inputDir, file);
      const outputFileName = file.replace(/\.docx$/i, '.md');
      const outputPath = path.join(outputDir, outputFileName);

      const result = await convertFile(inputPath, outputPath, options);
      results.push(result);

      if (result.success) {
        successCount++;
      } else {
        failedCount++;
      }
    }

    return {
      total: docxFiles.length,
      success: successCount,
      failed: failedCount,
      results
    };

  } catch (error) {
    throw new Error(`批量转换失败: ${error.message}`);
  }
}
