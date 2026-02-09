/**
 * 行星定义
 */

const PLANETS = [
  { id: 'sun', name: '太阳', symbol: '☉', english: 'Sun' },
  { id: 'moon', name: '月亮', symbol: '☽', english: 'Moon' },
  { id: 'mercury', name: '水星', symbol: '☿', english: 'Mercury' },
  { id: 'venus', name: '金星', symbol: '♀', english: 'Venus' },
  { id: 'mars', name: '火星', symbol: '♂', english: 'Mars' },
  { id: 'jupiter', name: '木星', symbol: '♃', english: 'Jupiter' },
  { id: 'saturn', name: '土星', symbol: '♄', english: 'Saturn' },
  { id: 'uranus', name: '天王星', symbol: '⛢', english: 'Uranus' },
  { id: 'neptune', name: '海王星', symbol: '♆', english: 'Neptune' },
  { id: 'pluto', name: '冥王星', symbol: '♇', english: 'Pluto' }
];

// 虚点 - 月球交点
const LUNAR_NODES = [
  { id: 'northnode', name: '北交点', symbol: '☊', english: 'North Node' },
  { id: 'southnode', name: '南交点', symbol: '☋', english: 'South Node' }
];

/**
 * 获取行星列表
 */
function getPlanets() {
  return PLANETS;
}

/**
 * 根据 ID 获取行星信息
 */
function getPlanetById(id) {
  return PLANETS.find(p => p.id === id) || LUNAR_NODES.find(p => p.id === id);
}

/**
 * 从 ephemeris 结果中提取行星经度
 * @param {Object} ephemerisResult - ephemeris 计算结果
 * @returns {Array} 行星位置数组
 */
function extractPlanetPositions(ephemerisResult) {
  const positions = [];
  const data = ephemerisResult.observed;
  
  // 映射 ephemeris 的键名到我们的行星 ID
  const mapping = {
    'sun': 'sun',
    'moon': 'moon',
    'mercury': 'mercury',
    'venus': 'venus',
    'mars': 'mars',
    'jupiter': 'jupiter',
    'saturn': 'saturn',
    'uranus': 'uranus',
    'neptune': 'neptune',
    'pluto': 'pluto'
  };
  
  for (const [ephKey, planetId] of Object.entries(mapping)) {
    if (data[ephKey]) {
      const planetData = data[ephKey];
      const planetInfo = getPlanetById(planetId);
      
      positions.push({
        id: planetId,
        name: planetInfo.name,
        symbol: planetInfo.symbol,
        english: planetInfo.english,
        longitude: planetData.apparentLongitudeDd,
        latitude: planetData.apparentLatitudeDd || 0,
        distance: planetData.distanceAu || 0,
        retrograde: planetData.isRetrograde || false
      });
    }
  }
  
  return positions;
}

module.exports = {
  PLANETS,
  LUNAR_NODES,
  getPlanets,
  getPlanetById,
  extractPlanetPositions
};
