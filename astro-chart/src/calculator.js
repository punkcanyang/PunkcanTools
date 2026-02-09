/**
 * 星盘核心计算模块
 */

const ephemeris = require('ephemeris');
const moment = require('moment-timezone');
const { longitudeToZodiac } = require('./utils/zodiac');
const { extractPlanetPositions, getPlanetById } = require('./utils/planets');
const { calculateAspects } = require('./utils/aspects');
const { calculatePlacidusHouses, getAngles } = require('./utils/houses');

/**
 * 计算完整星盘
 * @param {Object} options - 计算选项
 * @param {string|Date} options.datetime - 日期时间（ISO 格式或 Date 对象）
 * @param {number} options.latitude - 纬度 (-90 到 90)
 * @param {number} options.longitude - 经度 (-180 到 180)
 * @param {string} [options.timezone] - 时区（如 'Asia/Shanghai'）
 * @returns {Object} 完整星盘数据
 */
function calculateChart(options) {
  const { datetime, latitude, longitude, timezone } = options;
  
  // 解析日期时间
  let date;
  if (typeof datetime === 'string') {
    if (timezone) {
      date = moment.tz(datetime, timezone).toDate();
    } else {
      date = new Date(datetime);
    }
  } else if (datetime instanceof Date) {
    date = datetime;
  } else {
    throw new Error('Invalid datetime format');
  }
  
  // 验证坐标
  if (latitude < -90 || latitude > 90) {
    throw new Error('Latitude must be between -90 and 90');
  }
  if (longitude < -180 || longitude > 180) {
    throw new Error('Longitude must be between -180 and 180');
  }
  
  // 使用 ephemeris 计算行星位置
  const ephemerisResult = ephemeris.getAllPlanets(date, longitude, latitude, 0);
  
  // 提取行星位置
  const planets = extractPlanetPositions(ephemerisResult);
  
  // 为每个行星添加星座信息
  const planetsWithZodiac = planets.map(planet => {
    const zodiacInfo = longitudeToZodiac(planet.longitude);
    return {
      ...planet,
      longitude: Math.round(planet.longitude * 100) / 100,
      sign: zodiacInfo.sign,
      signSymbol: zodiacInfo.symbol,
      signEnglish: zodiacInfo.english,
      degree: zodiacInfo.formatted,
      fullPosition: zodiacInfo.fullFormatted
    };
  });
  
  // 计算宫位
  const houses = calculatePlacidusHouses(date, latitude, longitude);
  
  // 计算四角
  const angles = getAngles(date, latitude, longitude);
  
  // 计算相位
  const aspects = calculateAspects(planetsWithZodiac);
  
  // 确定每个行星所在的宫位
  const planetsInHouses = planetsWithZodiac.map(planet => {
    const houseNum = findHouse(planet.longitude, houses);
    return {
      ...planet,
      house: houseNum
    };
  });
  
  return {
    datetime: {
      input: datetime,
      utc: date.toISOString(),
      local: timezone ? moment(date).tz(timezone).format('YYYY-MM-DD HH:mm:ss') : null
    },
    location: {
      latitude,
      longitude,
      timezone: timezone || 'UTC'
    },
    planets: planetsInHouses,
    houses,
    angles,
    aspects
  };
}

/**
 * 确定行星所在的宫位
 * @param {number} planetLongitude - 行星经度
 * @param {Array} houses - 宫位数组
 * @returns {number} 宫位编号 (1-12)
 */
function findHouse(planetLongitude, houses) {
  for (let i = 0; i < 12; i++) {
    const currentHouse = houses[i].longitude;
    const nextHouse = houses[(i + 1) % 12].longitude;
    
    let inHouse = false;
    if (nextHouse > currentHouse) {
      // 正常情况
      inHouse = planetLongitude >= currentHouse && planetLongitude < nextHouse;
    } else {
      // 跨越 0 度
      inHouse = planetLongitude >= currentHouse || planetLongitude < nextHouse;
    }
    
    if (inHouse) {
      return i + 1;
    }
  }
  return 1; // 默认返回第一宫
}

/**
 * 格式化输出星盘数据为文本
 * @param {Object} chart - 星盘数据
 * @returns {string} 格式化的文本输出
 */
function formatChartAsText(chart) {
  let output = [];
  
  output.push('═══════════════════════════════════════════════════');
  output.push('                    星 盘 报 告');
  output.push('═══════════════════════════════════════════════════');
  output.push('');
  output.push(`📅 时间: ${chart.datetime.utc}`);
  output.push(`📍 地点: 纬度 ${chart.location.latitude}, 经度 ${chart.location.longitude}`);
  output.push('');
  
  // 四角
  output.push('┌─────────────────────────────────────────────────┐');
  output.push('│                    四 角                        │');
  output.push('├─────────────────────────────────────────────────┤');
  output.push(`│  上升点 (ASC): ${chart.angles.ascendant.sign} ${chart.angles.ascendant.degree}`.padEnd(50) + '│');
  output.push(`│  天 顶  (MC): ${chart.angles.midheaven.sign} ${chart.angles.midheaven.degree}`.padEnd(50) + '│');
  output.push(`│  下降点 (DSC): ${chart.angles.descendant.sign} ${chart.angles.descendant.degree}`.padEnd(50) + '│');
  output.push(`│  天 底  (IC): ${chart.angles.imumCoeli.sign} ${chart.angles.imumCoeli.degree}`.padEnd(50) + '│');
  output.push('└─────────────────────────────────────────────────┘');
  output.push('');
  
  // 行星位置
  output.push('┌─────────────────────────────────────────────────┐');
  output.push('│                  行 星 位 置                    │');
  output.push('├─────────┬───────────────────┬──────┬────────────┤');
  output.push('│  行星   │      位置         │ 宫位 │   状态     │');
  output.push('├─────────┼───────────────────┼──────┼────────────┤');
  
  for (const planet of chart.planets) {
    const status = planet.retrograde ? '℞ 逆行' : '';
    const row = `│ ${(planet.symbol + ' ' + planet.name).padEnd(7)}│ ${planet.fullPosition.padEnd(17)}│  ${String(planet.house).padEnd(4)}│ ${status.padEnd(10)}│`;
    output.push(row);
  }
  output.push('└─────────┴───────────────────┴──────┴────────────┘');
  output.push('');
  
  // 宫位
  output.push('┌─────────────────────────────────────────────────┐');
  output.push('│                  宫 位 宫 头                    │');
  output.push('├──────┬──────────────────────────────────────────┤');
  
  for (const house of chart.houses) {
    const row = `│ 第${String(house.number).padStart(2)}宫│ ${house.symbol} ${house.sign} ${house.degree}`.padEnd(49) + '│';
    output.push(row);
  }
  output.push('└──────┴──────────────────────────────────────────┘');
  output.push('');
  
  // 相位
  if (chart.aspects.length > 0) {
    output.push('┌─────────────────────────────────────────────────┐');
    output.push('│                  主 要 相 位                    │');
    output.push('├─────────────────────────────────────────────────┤');
    
    for (const aspect of chart.aspects) {
      const row = `│ ${aspect.planet1.symbol} ${aspect.planet1.name} ${aspect.aspectSymbol} ${aspect.planet2.symbol} ${aspect.planet2.name} (${aspect.aspect}, 容许度: ${aspect.orb}°)`.padEnd(49) + '│';
      output.push(row);
    }
    output.push('└─────────────────────────────────────────────────┘');
  }
  
  return output.join('\n');
}

module.exports = {
  calculateChart,
  formatChartAsText,
  findHouse
};
