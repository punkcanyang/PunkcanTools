/**
 * 星盘 Web 服务
 */

const express = require('express');
const path = require('path');
const { calculateChart, formatChartAsText } = require('./calculator');

const app = express();
const PORT = process.env.PORT || 3000;

// 中间件
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, '../public')));

/**
 * API: 计算星盘
 * POST /api/chart
 */
app.post('/api/chart', (req, res) => {
  try {
    const { datetime, latitude, longitude, timezone } = req.body;
    
    // 验证输入
    if (!datetime) {
      return res.status(400).json({ error: '请提供日期时间' });
    }
    if (latitude === undefined || latitude === null) {
      return res.status(400).json({ error: '请提供纬度' });
    }
    if (longitude === undefined || longitude === null) {
      return res.status(400).json({ error: '请提供经度' });
    }
    
    // 计算星盘
    const chart = calculateChart({
      datetime,
      latitude: parseFloat(latitude),
      longitude: parseFloat(longitude),
      timezone
    });
    
    res.json({
      success: true,
      data: chart
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * API: 获取文本格式星盘
 * POST /api/chart/text
 */
app.post('/api/chart/text', (req, res) => {
  try {
    const { datetime, latitude, longitude, timezone } = req.body;
    
    const chart = calculateChart({
      datetime,
      latitude: parseFloat(latitude),
      longitude: parseFloat(longitude),
      timezone
    });
    
    const text = formatChartAsText(chart);
    
    res.type('text/plain').send(text);
  } catch (error) {
    res.status(500).type('text/plain').send('错误: ' + error.message);
  }
});

// 主页
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

// 启动服务器
app.listen(PORT, () => {
  console.log(`
╔═══════════════════════════════════════════════════╗
║           星盘计算工具 - Web 服务                 ║
╠═══════════════════════════════════════════════════╣
║  服务已启动: http://localhost:${PORT}               ║
║  API 文档:                                        ║
║    POST /api/chart      - 计算星盘 (JSON)         ║
║    POST /api/chart/text - 计算星盘 (文本)         ║
╚═══════════════════════════════════════════════════╝
`);
});

module.exports = app;
