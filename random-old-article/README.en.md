# Random Old Article

An Obsidian plugin that randomly picks old articles to read, helping you review past notes.

## Features

- **Random Old Article Selection**: Randomly select an article from your vault
- **Smart Deduplication**: Avoid selecting recently read articles (configurable, default 1 year)
- **Configurable Parameters**:
  - Set cooldown days (how long after reading before an article can be selected again)
  - Set minimum file age (only select articles created long enough ago)
  - Exclude specific folders
  - Include/exclude subfolders

## Installation

1. Clone or download this repository to your Obsidian plugins folder
2. Run `npm install` to install dependencies
3. Run `npm run build` to build the plugin
4. Enable the plugin in Obsidian

## Usage

1. **Click the toolbar icon**: Click the dice icon in the left toolbar to randomly pick an article
2. **Use command palette**: Press `Cmd/Ctrl + P`, search for "挑选随机旧文章"
3. **Clear history**: Use "清除阅读历史" command to reset history

## Settings

Open the settings panel to configure:
- **Cooldown (days)**: Default 365, articles read within this period won't be selected again
- **Minimum file age (days)**: Default 30, only select articles created at least this many days ago
- **Include subfolders**: Whether to search in all subfolders
- **Excluded folders**: Specify folder paths to exclude

## Development

```bash
# Install dependencies
npm install

# Development mode (auto rebuild)
npm run dev

# Production build
npm run build
```

## License

MIT License
