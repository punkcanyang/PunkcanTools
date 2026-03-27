/**
 * __ai_context__: Vite 构建配置，用于将 Chrome Extension 的多个入口点打包。
 * 采用多入口构建策略：popup、options、service-worker 各自独立打包。
 * 输出到 dist/ 目录后可直接作为 Chrome 扩展加载。
 */
import { defineConfig } from 'vite';
import { resolve } from 'path';
import { cpSync } from 'fs';

export default defineConfig({
  // WHY: root 指向 src 目录，让 Vite 正确处理 HTML 入口的相对路径
  root: resolve(__dirname, 'src'),
  build: {
    outDir: resolve(__dirname, 'dist'),
    emptyOutDir: true,
    rollupOptions: {
      input: {
        'popup/index': resolve(__dirname, 'src/popup/index.html'),
        'options/index': resolve(__dirname, 'src/options/index.html'),
        'service-worker': resolve(__dirname, 'src/background/service-worker.ts'),
      },
      output: {
        entryFileNames: (chunkInfo) => {
          // WHY: Service Worker 必须在扩展根目录
          if (chunkInfo.name === 'service-worker') {
            return 'service-worker.js';
          }
          // WHY: popup/index → popup/index.js, options/index → options/index.js
          return '[name].js';
        },
        chunkFileNames: 'shared/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]',
      },
    },
    // WHY: 必须启用 CSS code splitting，否则 popup (width:340px) 和 options (full-width) 的 body 样式会冲突
    cssCodeSplit: true,
    // WHY: 保持可读性，便于调试
    minify: false,
  },
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src'),
    },
  },
  plugins: [
    {
      name: 'copy-extension-assets',
      // WHY: 构建完成后复制 manifest.json 和图标到 dist/
      closeBundle() {
        cpSync(
          resolve(__dirname, 'manifest.json'),
          resolve(__dirname, 'dist/manifest.json'),
        );
        cpSync(
          resolve(__dirname, 'assets'),
          resolve(__dirname, 'dist/assets'),
          { recursive: true },
        );
      },
    },
  ],
});

/**
 * [For Future AI]
 * 1. Key assumptions:
 *    - Chrome Extension MV3 要求 service-worker 在根目录
 *    - popup 和 options 各有独立的 HTML 入口
 * 2. Potential edge cases:
 *    - Vite 的 HTML 入口路径解析在不同 OS 上可能有差异
 *    - service-worker 不能使用 ES module import（需要在 manifest 中声明 type: module）
 * 3. Dependencies: vite, path (node built-in)
 */
