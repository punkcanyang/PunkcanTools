#!/usr/bin/env node

import { program } from 'commander';
import path from 'path';
import fs from 'fs-extra';
import { convertFile, convertDirectory } from './converter.js';

// 获取 package.json 版本
const packageJson = JSON.parse(
  await fs.readFile(new URL('../package.json', import.meta.url), 'utf-8')
);

program
  .name('word2md')
  .description('将 Word 文档 (.docx) 转换为 Markdown 格式')
  .version(packageJson.version);

program
  .argument('<input>', 'Word 文件路径或包含 Word 文件的目录')
  .option('-o, --output <path>', '输出路径（文件或目录）')
  .option('-i, --no-images', '不提取图片')
  .option('-r, --recursive', '递归处理子目录（目录模式）')
  .action(async (input, options) => {
    try {
      const inputPath = path.resolve(input);
      const stats = await fs.stat(inputPath);

      if (stats.isFile()) {
        // 单文件模式
        if (!inputPath.endsWith('.docx')) {
          console.error('❌ 错误: 输入文件必须是 .docx 格式');
          process.exit(1);
        }

        const outputPath = options.output
          ? path.resolve(options.output)
          : inputPath.replace(/\.docx$/i, '.md');

        console.log('🔄 正在转换...');
        const result = await convertFile(inputPath, outputPath, {
          extractImages: options.images !== false
        });

        if (result.success) {
          console.log(`✅ ${result.message}`);
        } else {
          console.error(`❌ ${result.message}`);
          process.exit(1);
        }

      } else if (stats.isDirectory()) {
        // 目录模式
        const outputDir = options.output
          ? path.resolve(options.output)
          : inputPath;

        console.log(`🔄 正在扫描目录: ${inputPath}`);
        const result = await convertDirectory(inputPath, outputDir, {
          extractImages: options.images !== false,
          recursive: options.recursive
        });

        console.log(`\n📊 转换完成:`);
        console.log(`   总计: ${result.total} 个文件`);
        console.log(`   成功: ${result.success} 个`);
        console.log(`   失败: ${result.failed} 个`);

        if (result.total === 0) {
          console.log('\n⚠️  未找到 .docx 文件');
        } else {
          console.log('\n详细结果:');
          result.results.forEach(r => {
            const icon = r.success ? '✅' : '❌';
            console.log(`${icon} ${r.message}`);
          });
        }

        if (result.failed > 0) {
          process.exit(1);
        }

      } else {
        console.error('❌ 错误: 输入路径无效');
        process.exit(1);
      }

    } catch (error) {
      console.error(`❌ 错误: ${error.message}`);
      process.exit(1);
    }
  });

program.parse();
