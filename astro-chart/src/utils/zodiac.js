/**
 * 星座定义和转换工具
 */

const ZODIAC_SIGNS = [
  { name: '白羊座', symbol: '♈', english: 'Aries', startDegree: 0 },
  { name: '金牛座', symbol: '♉', english: 'Taurus', startDegree: 30 },
  { name: '双子座', symbol: '♊', english: 'Gemini', startDegree: 60 },
  { name: '巨蟹座', symbol: '♋', english: 'Cancer', startDegree: 90 },
  { name: '狮子座', symbol: '♌', english: 'Leo', startDegree: 120 },
  { name: '处女座', symbol: '♍', english: 'Virgo', startDegree: 150 },
  { name: '天秤座', symbol: '♎', english: 'Libra', startDegree: 180 },
  { name: '天蝎座', symbol: '♏', english: 'Scorpio', startDegree: 210 },
  { name: '射手座', symbol: '♐', english: 'Sagittarius', startDegree: 240 },
  { name: '摩羯座', symbol: '♑', english: 'Capricorn', startDegree: 270 },
  { name: '水瓶座', symbol: '♒', english: 'Aquarius', startDegree: 300 },
  { name: '双鱼座', symbol: '♓', english: 'Pisces', startDegree: 330 }
];

/**
 * 将黄道经度转换为星座信息
 * @param {number} longitude - 黄道经度 (0-360)
 * @returns {Object} 星座信息
 */
function longitudeToZodiac(longitude) {
  // 规范化经度到 0-360 范围
  const normalizedLon = ((longitude % 360) + 360) % 360;
  
  // 计算星座索引
  const signIndex = Math.floor(normalizedLon / 30);
  const sign = ZODIAC_SIGNS[signIndex];
  
  // 计算在星座内的度数
  const degreeInSign = normalizedLon - sign.startDegree;
  const degrees = Math.floor(degreeInSign);
  const minutes = Math.floor((degreeInSign - degrees) * 60);
  
  return {
    sign: sign.name,
    symbol: sign.symbol,
    english: sign.english,
    degree: degrees,
    minute: minutes,
    formatted: `${degrees}°${minutes}'`,
    fullFormatted: `${sign.name} ${degrees}°${minutes}'`
  };
}

/**
 * 获取星座列表
 */
function getZodiacSigns() {
  return ZODIAC_SIGNS;
}

module.exports = {
  ZODIAC_SIGNS,
  longitudeToZodiac,
  getZodiacSigns
};
