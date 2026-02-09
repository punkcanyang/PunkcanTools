/**
 * 宫位计算工具
 * 使用 Placidus 宫位制
 */

const { longitudeToZodiac } = require('./zodiac');

/**
 * 计算恒星时 (Sidereal Time)
 * @param {Date} date - UTC 日期时间
 * @returns {number} 恒星时（小时）
 */
function calculateSiderealTime(date) {
  // 计算儒略日
  const jd = dateToJulianDay(date);
  
  // 计算 T (儒略世纪数，从 J2000.0 起算)
  const T = (jd - 2451545.0) / 36525.0;
  
  // 格林威治平恒星时 (GMST) - 使用 IAU 公式
  let gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0)
           + 0.000387933 * T * T - T * T * T / 38710000;
  
  // 规范化到 0-360 度
  gmst = ((gmst % 360) + 360) % 360;
  
  // 转换为小时
  return gmst / 15;
}

/**
 * 将日期转换为儒略日
 * @param {Date} date - 日期对象
 * @returns {number} 儒略日
 */
function dateToJulianDay(date) {
  const year = date.getUTCFullYear();
  const month = date.getUTCMonth() + 1;
  const day = date.getUTCDate();
  const hour = date.getUTCHours();
  const minute = date.getUTCMinutes();
  const second = date.getUTCSeconds();
  
  const dayFraction = (hour + minute / 60 + second / 3600) / 24;
  
  let y = year;
  let m = month;
  
  if (month <= 2) {
    y = year - 1;
    m = month + 12;
  }
  
  const A = Math.floor(y / 100);
  const B = 2 - A + Math.floor(A / 4);
  
  const jd = Math.floor(365.25 * (y + 4716)) 
           + Math.floor(30.6001 * (m + 1)) 
           + day + dayFraction + B - 1524.5;
  
  return jd;
}

/**
 * 计算上升点 (ASC) 和中天 (MC)
 * @param {Date} date - UTC 日期时间
 * @param {number} latitude - 纬度
 * @param {number} longitude - 经度
 * @returns {Object} ASC 和 MC 信息
 */
function calculateAscMc(date, latitude, longitude) {
  // 计算本地恒星时
  const gmst = calculateSiderealTime(date);
  const lst = ((gmst + longitude / 15) % 24 + 24) % 24;
  const lstDegrees = lst * 15; // 转换为度
  
  // 中天 (MC) = 本地恒星时
  const mc = lstDegrees;
  
  // 黄道倾角 (大约 23.44 度)
  const obliquity = 23.4393 * Math.PI / 180;
  const latRad = latitude * Math.PI / 180;
  const lstRad = lstDegrees * Math.PI / 180;
  
  // 计算上升点
  // ASC = atan2(cos(RAMC), -(sin(RAMC) * cos(ε) + tan(φ) * sin(ε)))
  const sinLst = Math.sin(lstRad);
  const cosLst = Math.cos(lstRad);
  const sinObl = Math.sin(obliquity);
  const cosObl = Math.cos(obliquity);
  const tanLat = Math.tan(latRad);
  
  let asc = Math.atan2(cosLst, -(sinLst * cosObl + tanLat * sinObl));
  asc = asc * 180 / Math.PI;
  
  // 规范化到 0-360
  asc = ((asc % 360) + 360) % 360;
  
  return {
    ascendant: asc,
    midheaven: mc
  };
}

/**
 * 计算 Placidus 宫位
 * @param {Date} date - UTC 日期时间
 * @param {number} latitude - 纬度
 * @param {number} longitude - 经度
 * @returns {Array} 12 个宫位的宫头经度
 */
function calculatePlacidusHouses(date, latitude, longitude) {
  const { ascendant, midheaven } = calculateAscMc(date, latitude, longitude);
  
  // 计算各宫头
  // 简化的 Placidus 计算 - 使用三分法近似
  const houses = [];
  
  // 第 1 宫 = ASC
  houses[0] = ascendant;
  
  // 第 10 宫 = MC
  houses[9] = midheaven;
  
  // 第 4 宫 = IC (MC 对面)
  houses[3] = (midheaven + 180) % 360;
  
  // 第 7 宫 = DSC (ASC 对面)
  houses[6] = (ascendant + 180) % 360;
  
  // 计算其他宫位 (使用简化的三分法)
  // 第 2、3 宫 (ASC 到 IC 三分)
  const arc1 = angleBetween(ascendant, houses[3]);
  houses[1] = (ascendant + arc1 / 3) % 360;
  houses[2] = (ascendant + 2 * arc1 / 3) % 360;
  
  // 第 11、12 宫 (MC 到 ASC 三分)
  const arc2 = angleBetween(midheaven, ascendant);
  houses[10] = (midheaven + arc2 / 3) % 360;
  houses[11] = (midheaven + 2 * arc2 / 3) % 360;
  
  // 对称计算下半球宫位
  houses[4] = (houses[10] + 180) % 360;
  houses[5] = (houses[11] + 180) % 360;
  houses[7] = (houses[1] + 180) % 360;
  houses[8] = (houses[2] + 180) % 360;
  
  // 转换为宫位信息对象
  return houses.map((longitude, index) => {
    const zodiacInfo = longitudeToZodiac(longitude);
    return {
      number: index + 1,
      longitude: Math.round(longitude * 100) / 100,
      sign: zodiacInfo.sign,
      symbol: zodiacInfo.symbol,
      degree: zodiacInfo.formatted
    };
  });
}

/**
 * 计算两个角度之间的顺时针弧度
 */
function angleBetween(from, to) {
  let diff = to - from;
  if (diff < 0) diff += 360;
  return diff;
}

/**
 * 获取上升点和中天信息
 */
function getAngles(date, latitude, longitude) {
  const { ascendant, midheaven } = calculateAscMc(date, latitude, longitude);
  
  const ascInfo = longitudeToZodiac(ascendant);
  const mcInfo = longitudeToZodiac(midheaven);
  const descInfo = longitudeToZodiac((ascendant + 180) % 360);
  const icInfo = longitudeToZodiac((midheaven + 180) % 360);
  
  return {
    ascendant: {
      longitude: Math.round(ascendant * 100) / 100,
      sign: ascInfo.sign,
      symbol: ascInfo.symbol,
      degree: ascInfo.formatted
    },
    midheaven: {
      longitude: Math.round(midheaven * 100) / 100,
      sign: mcInfo.sign,
      symbol: mcInfo.symbol,
      degree: mcInfo.formatted
    },
    descendant: {
      longitude: Math.round((ascendant + 180) % 360 * 100) / 100,
      sign: descInfo.sign,
      symbol: descInfo.symbol,
      degree: descInfo.formatted
    },
    imumCoeli: {
      longitude: Math.round((midheaven + 180) % 360 * 100) / 100,
      sign: icInfo.sign,
      symbol: icInfo.symbol,
      degree: icInfo.formatted
    }
  };
}

module.exports = {
  calculateSiderealTime,
  dateToJulianDay,
  calculateAscMc,
  calculatePlacidusHouses,
  getAngles
};
