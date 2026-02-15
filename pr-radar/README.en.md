# PR Radar

AI-powered PR/Issue analysis tool. Automatically scan PRs and Issues in GitHub repositories for deduplication, dependency detection, and deviation assessment.

## Features

- **GitHub Data Sync**: Automatically sync repository PRs and Issues
- **AI Deduplication**: Intelligently identify similar/duplicate PRs and Issues
- **PR Dependency Detection**: Analyze PR dependencies and build dependency graphs
- **Vision Deviation Assessment**: Compare PRs with project Vision document to assess deviation
- **Web Interface**: Visual management and browsing of analysis results
- **GitHub Action**: Support running quick analysis in CI

## Quick Start

### Prerequisites

- Node.js 18+
- PostgreSQL 14+
- GitHub Personal Access Token

### Installation

```bash
# Clone repository
git clone <this-repo>
cd pr-radar

# Install dependencies
npm install
```

### Configuration

```bash
# Copy environment template
cp server/.env.example server/.env
```

Edit `server/.env`:

```env
# Database connection
DATABASE_URL="postgresql://user:password@localhost:5432/pr_radar"

# GitHub Token (needs repo scope)
GITHUB_TOKEN="ghp_xxxxxxxxxxxx"

# OpenAI API Key
OPENAI_API_KEY="sk-xxxxxxxxxxxx"

# Server port
PORT=3000
```

### Initialize Database

```bash
cd server
npx prisma generate
npx prisma db push
```

### Start

```bash
# Development mode (both frontend and backend)
npm run dev

# Start separately
npm run dev:server  # Backend: http://localhost:3000
npm run dev:web    # Frontend: http://localhost:5173
```

## Usage Guide

### Add Repository

1. Open http://localhost:5173
2. Click "添加仓库" (Add Repository)
3. Enter Owner and Repository name
4. Click "添加" (Add)

### Sync Data

Click "同步" (Sync) button next to repository to fetch latest PR and Issue data.

### Run Analysis

1. Click "分析" (Analyze) button
2. AI will automatically analyze:
   - Similar/duplicate PRs and Issues
   - PR dependencies
   - Deviation from Vision document

### Configure Vision Document

1. Click repository name to enter details
2. Click "编辑 Vision" (Edit Vision)
3. Paste your project Vision document (Markdown format)

Example Vision document:

```markdown
# Project Vision

## Core Features
- User authentication system
- Data analysis dashboard
- API export functionality

## Technical Requirements
- Language: TypeScript
- Framework: React + Node.js
- Database: PostgreSQL

## Non-Goals
- No mobile support
- No third-party integrations

## Design Principles
- Keep it simple
- Prefer mature solutions
- Focus on code maintainability
```

## GitHub Action Integration

Add to `.github/workflows/pr-radar.yml`:

```yaml
name: PR Radar Analysis
on: [pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: your-repo/pr-radar/action@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          openai-key: ${{ secrets.OPENAI_API_KEY }}
```

## API Documentation

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/repos | Get all repositories |
| POST | /api/repos | Add repository |
| DELETE | /api/repos/:id | Delete repository |
| PUT | /api/repos/:id/vision | Update Vision |
| POST | /api/repos/:id/sync | Trigger sync |
| GET | /api/repos/:id/prs | Get PR list |
| GET | /api/repos/:id/issues | Get Issue list |
| POST | /api/repos/:id/analyze/duplicates | Run deduplication analysis |
| GET | /api/repos/:id/analysis/dependencies | Get dependency graph |

## Tech Stack

| Layer | Technology |
|-------|------------|
| Frontend | React + TypeScript + Vite |
| Backend | Node.js + Express |
| Database | PostgreSQL + Prisma |
| AI | OpenAI GPT-4 |
| GitHub API | Octokit |

## License

MIT
