# PR Radar

AI驱动的 PR/Issue 分析工具。自动扫描 GitHub 仓库中的 PR 和 Issue，进行去重、依赖检测和偏离度评估。

## 功能特性

- **GitHub 数据同步**：自动同步仓库的 PR 和 Issue
- **AI 去重分析**：智能识别相似/重复的 PR 和 Issue
- **PR 依赖检测**：分析 PR 之间的依赖关系，构建依赖图
- **Vision 偏离评估**：对比 PR 与项目愿景文档，评估偏离程度
- **Web 界面**：可视化管理和浏览分析结果
- **GitHub Action**：支持在 CI 中运行快速分析

## 快速开始

### 前置要求

- Node.js 18+
- PostgreSQL 14+
- GitHub Personal Access Token

### 安装

```bash
# 克隆仓库
git clone <this-repo>
cd pr-radar

# 安装依赖
npm install
```

### 配置

```bash
# 复制环境变量模板
cp server/.env.example server/.env
```

编辑 `server/.env`：

```env
# 数据库连接
DATABASE_URL="postgresql://user:password@localhost:5432/pr_radar"

# GitHub Token (需要 repo 权限)
GITHUB_TOKEN="ghp_xxxxxxxxxxxx"

# OpenAI API Key
OPENAI_API_KEY="sk-xxxxxxxxxxxx"

# 服务器端口
PORT=3000
```

### 初始化数据库

```bash
cd server
npx prisma generate
npx prisma db push
```

### 启动

```bash
# 开发模式 (同时启动前端和后端)
npm run dev

# 分别启动
npm run dev:server  # 后端: http://localhost:3000
npm run dev:web    # 前端: http://localhost:5173
```

## 使用指南

### 添加仓库

1. 打开 http://localhost:5173
2. 点击「添加仓库」
3. 输入 Owner 和 Repository 名称
4. 点击「添加」

### 同步数据

点击仓库旁边的「同步」按钮，获取最新的 PR 和 Issue 数据。

### 运行分析

1. 点击「分析」按钮
2. AI 会自动分析：
   - 相似/重复的 PR 和 Issue
   - PR 之间的依赖关系
   - 与 Vision 文档的偏离度

### 配置 Vision 文档

1. 点击仓库名称进入详情页
2. 点击「编辑 Vision」
3. 粘贴你的项目愿景文档（Markdown 格式）

示例 Vision 文档：

```markdown
# Project Vision

## Core Features
- 用户认证系统
- 数据分析仪表盘
- API 导出功能

## Technical Requirements
- Language: TypeScript
- Framework: React + Node.js
- Database: PostgreSQL

## Non-Goals
- 不支持移动端
- 不做第三方集成

## Design Principles
- 保持简单
- 优先使用成熟方案
- 注重代码可维护性
```

## GitHub Action 集成

在 `.github/workflows/pr-radar.yml` 中添加：

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

## API 文档

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /api/repos | 获取所有仓库 |
| POST | /api/repos | 添加仓库 |
| DELETE | /api/repos/:id | 删除仓库 |
| PUT | /api/repos/:id/vision | 更新 Vision |
| POST | /api/repos/:id/sync | 触发同步 |
| GET | /api/repos/:id/prs | 获取 PR 列表 |
| GET | /api/repos/:id/issues | 获取 Issue 列表 |
| POST | /api/repos/:id/analyze/duplicates | 运行去重分析 |
| GET | /api/repos/:id/analysis/dependencies | 获取依赖图 |

## 技术栈

| 层级 | 技术 |
|------|------|
| 前端 | React + TypeScript + Vite |
| 后端 | Node.js + Express |
| 数据库 | PostgreSQL + Prisma |
| AI | OpenAI GPT-4 |
| GitHub API | Octokit |

## 许可证

MIT
