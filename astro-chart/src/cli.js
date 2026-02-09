#!/usr/bin/env node

/**
 * 星盘命令行工具
 */

const { calculateChart, formatChartAsText } = require('./calculator');

// 解析命令行参数
function parseArgs(args) {
  const options = {
    datetime: null,
    latitude: null,
    longitude: null,
    timezone: null,
    format: 'text',
    help: false
  };
  
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    const value = args[i + 1];
    
    switch (arg) {
      case '--date':
      case '-d':
        options.datetime = value;
        i++;
        break;
      case '--lat':
      case '-la':
        options.latitude = parseFloat(value);
        i++;
        break;
      case '--lon':
      case '-lo':
        options.longitude = parseFloat(value);
        i++;
        break;
      case '--timezone':
      case '-tz':
        options.timezone = value;
        i++;
        break;
      case '--format':
      case '-f':
        options.format = value;
        i++;
        break;
      case '--help':
      case '-h':
        options.help = true;
        break;
    }
  }
  
  return options;
}

function showHelp() {
  console.log(`
星盘计算工具 (astro-chart)

用法:
  astro-chart --date <datetime> --lat <latitude> --lon <longitude> [选项]

参数:
  --date, -d      日期时间 (ISO 格式，如 "2026-01-13 00:23" 或 "2026-01-13T00:23:00")
  --lat, -la      纬度 (-90 到 90)
  --lon, -lo      经度 (-180 到 180)
  --timezone, -tz 时区 (如 "Asia/Shanghai")
  --format, -f    输出格式: text 或 json (默认: text)
  --help, -h      显示帮助信息

示例:
  # 计算北京时间的星盘
  astro-chart --date "2026-01-13 00:23" --lat 39.9 --lon 116.4 --timezone "Asia/Shanghai"

  # 输出 JSON 格式
  astro-chart --date "2026-01-13T00:23:00" --lat 39.9 --lon 116.4 --format json
`);
}

function main() {
  const args = process.argv.slice(2);
  const options = parseArgs(args);
  
  if (options.help) {
    showHelp();
    return;
  }
  
  // 验证必需参数
  if (!options.datetime) {
    console.error('错误: 请提供日期时间 (--date)');
    showHelp();
    process.exit(1);
  }
  
  if (options.latitude === null || isNaN(options.latitude)) {
    console.error('错误: 请提供有效的纬度 (--lat)');
    showHelp();
    process.exit(1);
  }
  
  if (options.longitude === null || isNaN(options.longitude)) {
    console.error('错误: 请提供有效的经度 (--lon)');
    showHelp();
    process.exit(1);
  }
  
  try {
    // 计算星盘
    const chart = calculateChart({
      datetime: options.datetime,
      latitude: options.latitude,
      longitude: options.longitude,
      timezone: options.timezone
    });
    
    // 输出结果
    if (options.format === 'json') {
      console.log(JSON.stringify(chart, null, 2));
    } else {
      console.log(formatChartAsText(chart));
    }
  } catch (error) {
    console.error('计算错误:', error.message);
    process.exit(1);
  }
}

main();
