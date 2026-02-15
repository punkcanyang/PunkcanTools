# Astro Chart

⭐ Generate detailed astrological chart data including planetary positions, houses, and aspects based on time and location.

## Features

- 🌍 **Planetary Positions**: Ecliptic positions of the Sun, Moon, and 8 planets
- 🏠 **House System**: Placidus house system calculation
- 📐 **Aspect Analysis**: Major aspects (conjunction, sextile, square, trine, opposition)
- ↩️ **Retrograde Detection**: Automatically marks retrograde planets
- 🌐 **Web UI**: Modern web interface
- 💻 **CLI Tool**: Command-line quick lookup

## Quick Start

### Installation

```bash
cd astro-chart
npm install
```

### Web Interface

```bash
npm start
# Visit http://localhost:3000
```

### Command Line

```bash
# Text format output
node src/cli.js --date "2026-01-13 00:23" --lat 39.9 --lon 116.4 --timezone "Asia/Shanghai"

# JSON format output
node src/cli.js --date "2026-01-13 00:23" --lat 39.9 --lon 116.4 --format json
```

## API

### POST /api/chart

Calculate astrological chart, returns JSON data.

**Request Body:**
```json
{
  "datetime": "2026-01-13T00:23:00",
  "latitude": 39.9042,
  "longitude": 116.4074,
  "timezone": "Asia/Shanghai"
}
```

**Response:**
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

## Use as Module

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

## Tech Stack

- [ephemeris](https://www.npmjs.com/package/ephemeris) - Ephemeris calculation
- [Express](https://expressjs.com/) - Web framework
- [moment-timezone](https://momentjs.com/timezone/) - Timezone handling

## License

MIT
