#!/usr/bin/env node

import { convertHtmlToPdf, parseCliArgs, printUsage } from './book-pdf.js';

async function main() {
  const options = parseCliArgs(process.argv.slice(2));

  if (options.help || !options.input) {
    console.log(printUsage());
    process.exit(options.help ? 0 : 1);
  }

  const result = await convertHtmlToPdf(options);

  console.log(`PDF 已產生：${result.outputPath}`);

  if (options.verbose) {
    console.log(`使用瀏覽器：${result.browserPath}`);
  }

  if (options.keepTemp) {
    console.log(`暫存 HTML：${result.tempHtmlPath}`);
  }
}

main().catch((error) => {
  console.error(`html-book-pdf: ${error.message}`);
  process.exit(1);
});
