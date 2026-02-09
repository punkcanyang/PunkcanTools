# 星盘计算工具 (astro-chart)

⭐ 输入时间和地点，生成详细的星盘数据，包括行星位置、宫位和相位。

## ✨ 功能特性

- 🌍 **行星位置**: 太阳、月亮及八大行星的黄道位置
- 🏠 **宫位系统**: Placidus 宫位制计算
- 📐 **相位分析**: 主要相位（合、六合、四分、三合、对冲）
- ↩️ **逆行检测**: 自动标记逆行行星
- 🌐 **Web UI**: 现代化网页界面
- 💻 **CLI 工具**: 命令行快速查询

## 🚀 快速开始

### 安装

```bash
cd astro-chart
npm install
```

### 使用 Web 界面

```bash
npm start
# 访问 http://localhost:3000
```

### 使用命令行

```bash
# 文本格式输出
node src/cli.js --date "2026-01-13 00:23" --lat 39.9 --lon 116.4 --timezone "Asia/Shanghai"

# JSON 格式输出
node src/cli.js --date "2026-01-13 00:23" --lat 39.9 --lon 116.4 --format json
```

## 📖 API 接口

### POST /api/chart

计算星盘，返回 JSON 格式数据。

**请求体:**
```json
{
  "datetime": "2026-01-13T00:23:00",
  "latitude": 39.9042,
  "longitude": 116.4074,
  "timezone": "Asia/Shanghai"
}
```

**响应:**
```json
{
  "success": true,
  "data": {
    "planets": [...],
    "houses": [...],
    "angles": {...},
    "aspects": [...]
  }
}
```

## 📦 作为模块使用

```javascript
const { calculateChart, formatChartAsText } = require('./src');

const chart = calculateChart({
  datetime: '2026-01-13T00:23:00',
  latitude: 39.9042,
  longitude: 116.4074,
  timezone: 'Asia/Shanghai'
});

console.log(formatChartAsText(chart));
```

## 🔧 技术栈

- [ephemeris](https://www.npmjs.com/package/ephemeris) - 星历计算
- [Express](https://expressjs.com/) - Web 服务框架
- [moment-timezone](https://momentjs.com/timezone/) - 时区处理

## 📄 许可证

MIT
