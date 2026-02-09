/**
 * 相位计算工具
 */

// 相位定义
const ASPECTS = [
  { name: '合相', english: 'Conjunction', symbol: '☌', angle: 0, orb: 8 },
  { name: '六合', english: 'Sextile', symbol: '⚹', angle: 60, orb: 6 },
  { name: '四分', english: 'Square', symbol: '□', angle: 90, orb: 8 },
  { name: '三合', english: 'Trine', symbol: '△', angle: 120, orb: 8 },
  { name: '对冲', english: 'Opposition', symbol: '☍', angle: 180, orb: 8 },
  // 次要相位
  { name: '半六合', english: 'Semi-sextile', symbol: '⚺', angle: 30, orb: 2 },
  { name: '梅花', english: 'Quincunx', symbol: '⚻', angle: 150, orb: 3 },
  { name: '半四分', english: 'Semi-square', symbol: '∠', angle: 45, orb: 2 },
  { name: '倍半四分', english: 'Sesquiquadrate', symbol: '⚼', angle: 135, orb: 2 }
];

// 仅主要相位
const MAJOR_ASPECTS = ASPECTS.slice(0, 5);

/**
 * 计算两个经度之间的角度差
 * @param {number} lon1 - 第一个经度
 * @param {number} lon2 - 第二个经度
 * @returns {number} 角度差 (0-180)
 */
function angleDifference(lon1, lon2) {
  let diff = Math.abs(lon1 - lon2);
  if (diff > 180) {
    diff = 360 - diff;
  }
  return diff;
}

/**
 * 检测两个天体之间的相位
 * @param {number} lon1 - 第一个天体经度
 * @param {number} lon2 - 第二个天体经度
 * @param {boolean} majorOnly - 是否只检测主要相位
 * @returns {Object|null} 相位信息或 null
 */
function detectAspect(lon1, lon2, majorOnly = true) {
  const diff = angleDifference(lon1, lon2);
  const aspectList = majorOnly ? MAJOR_ASPECTS : ASPECTS;
  
  for (const aspect of aspectList) {
    const orb = Math.abs(diff - aspect.angle);
    if (orb <= aspect.orb) {
      return {
        ...aspect,
        exactAngle: diff,
        orb: Math.round(orb * 100) / 100,
        applying: null // 可进一步扩展判断相位是入相还是出相
      };
    }
  }
  
  return null;
}

/**
 * 计算所有行星之间的相位
 * @param {Array} planets - 行星位置数组
 * @param {boolean} majorOnly - 是否只计算主要相位
 * @returns {Array} 相位数组
 */
function calculateAspects(planets, majorOnly = true) {
  const aspects = [];
  
  for (let i = 0; i < planets.length; i++) {
    for (let j = i + 1; j < planets.length; j++) {
      const planet1 = planets[i];
      const planet2 = planets[j];
      
      const aspect = detectAspect(planet1.longitude, planet2.longitude, majorOnly);
      
      if (aspect) {
        aspects.push({
          planet1: {
            id: planet1.id,
            name: planet1.name,
            symbol: planet1.symbol
          },
          planet2: {
            id: planet2.id,
            name: planet2.name,
            symbol: planet2.symbol
          },
          aspect: aspect.name,
          aspectEnglish: aspect.english,
          aspectSymbol: aspect.symbol,
          angle: aspect.exactAngle,
          orb: aspect.orb,
          exactAngle: aspect.angle
        });
      }
    }
  }
  
  return aspects;
}

module.exports = {
  ASPECTS,
  MAJOR_ASPECTS,
  angleDifference,
  detectAspect,
  calculateAspects
};
