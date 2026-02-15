# PR Radar - AI驱动的PR/Issue分析工具

## 1. 项目概述

**项目名称**: PR Radar
**项目类型**: 本地运行的 Web 应用 + GitHub Action 插件
**核心功能**: 利用 AI 自动分析 GitHub 项目中的 PR 和 Issue，进行去重、依赖检测、偏离度评估
**目标用户**: 维护自己 GitHub 项目的开发者

## 2. 功能列表

### 2.1 核心功能

#### 2.1.1 GitHub 数据同步
- 扫描指定 GitHub 仓库的 PR 和 Issue
- 支持多个仓库配置
- 增量同步 + 定时全量同步
- 记录每个 PR/Issue 的状态、标签、评论等

#### 2.1.2 AI 去重分析
- 自动检测相似/重复的 PR 和 Issue
- 基于以下信号判断相似度：
  - 标题文本相似度
  - 描述内容相似度
  - 文件改动重叠度
  - 涉及的代码路径
- 生成去重报告，标记可能的重复项

#### 2.1.3 PR 依赖检测
- 检测 PR 是否基于另一个 PR (base/head 关系)
- 分析代码改动的时间线
- 识别依赖链
- 标记需要先合并的 PR

#### 2.1.4 偏离度评估 (Vision Check)
- 用户维护一个 Vision 文档（Markdown 格式）
- AI 分析每个 PR 与 Vision 的偏离程度
- 标记/拒绝偏离太远的 PR
- 提供偏离原因说明

#### 2.1.5 GitHub Action 集成
- 可在 CI 中运行，快速获取 PR 分析结果
- 输出 JSON 格式的分析报告

### 2.2 管理功能

- 仓库管理：添加/删除/编辑仓库
- Vision 文档管理：上传/编辑 Vision
- 同步控制：手动触发同步、查看同步状态
- 分析结果查看：查看去重报告、依赖图、偏离度

## 3. 技术架构

### 3.1 技术栈

| 层级 | 技术 |
|------|------|
| 前端 | React + TypeScript + Vite |
| 后端 | Node.js + Express + TypeScript |
| 数据库 | PostgreSQL + Prisma ORM |
| AI | OpenAI API (支持扩展 Ollama) |
| GitHub API | Octokit |

### 3.2 项目结构

```
pr-radar/
├── web/                    # 前端 Web 应用
│   ├── src/
│   │   ├── components/     # React 组件
│   │   ├── pages/         # 页面
│   │   ├── hooks/         # 自定义 hooks
│   │   ├── services/      # API 调用
│   │   └── types/         # TypeScript 类型
│   └── index.html
├── server/                 # 后端 API
│   ├── src/
│   │   ├── routes/        # API 路由
│   │   ├── services/      # 业务逻辑
│   │   ├── ai/            # AI 相关逻辑
│   │   ├── github/        # GitHub API 封装
│   │   └── types/         # 类型定义
│   └── index.ts
├── action/                 # GitHub Action
│   └── action.yml
├── prisma/                 # 数据库模型
│   └── schema.prisma
└── package.json
```

### 3.3 数据库模型

```prisma
model Repository {
  id          String   @id @default(cuid())
  owner       String
  name        String
  fullName    String   @unique
  visionDoc   String?  @db.Text
  lastSyncAt DateTime?
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt
  
  pullRequests PullRequest[]
  issues      Issue[]
}

model PullRequest {
  id            String   @id @default(cuid())
  number        Int
  title         String
  body          String?  @db.Text
  state         String
  author        String
  baseBranch    String
  headBranch    String
  filesChanged Json?
  additions     Int      @default(0)
  deletions     Int      @default(0)
  mergedAt      DateTime?
  createdAt     DateTime
  updatedAt     DateTime @updatedAt
  
  repositoryId  String
  repository    Repository @relation(fields: [repositoryId], references: [id])
  
  duplicates    PullRequest[] @relation("PRDuplicates")
  duplicateOf   PullRequest?   @relation("PRDuplicates")
  dependencies  PullRequest[] @relation("PRDependencies")
  dependentOn   PullRequest?   @relation("PRDependencies")
  
  analysis      PRAnalysis?
  
  @@unique([repositoryId, number])
}

model Issue {
  id          String   @id @default(cuid())
  number      Int
  title       String
  body        String?  @db.Text
  state       String
  author      String
  labels      String[]
  createdAt   DateTime
  updatedAt   DateTime @updatedAt
  
  repositoryId String
  repository   Repository @relation(fields: [repositoryId], references: [id])
  
  duplicates   Issue[] @relation("IssueDuplicates")
  duplicateOf Issue?  @relation("IssueDuplicates")
  
  analysis    IssueAnalysis?
  
  @@unique([repositoryId, number])
}

model PRAnalysis {
  id              String  @id @default(cuid())
  prId            String  @unique
  pr              PullRequest @relation(fields: [prId], references: [id])
  
  similarityScore Float?
  isDuplicate     Boolean @default(false)
  duplicateOfId   String?
  deviationScore  Float?
  deviationReason String? @db.Text
  visionMatch     Float?
  summary         String? @db.Text
  
  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt
}

model IssueAnalysis {
  id              String  @id @default(cuid())
  issueId         String  @unique
  issue           Issue   @relation(fields: [issueId], references: [id])
  
  similarityScore Float?
  isDuplicate     Boolean @default(false)
  duplicateOfId   String?
  
  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt
}
```

## 4. API 设计

### 4.1 仓库管理

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /api/repos | 获取所有仓库 |
| POST | /api/repos | 添加仓库 |
| DELETE | /api/repos/:id | 删除仓库 |
| PUT | /api/repos/:id | 更新仓库配置 |
| PUT | /api/repos/:id/vision | 更新 Vision 文档 |

### 4.2 同步

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | /api/repos/:id/sync | 触发同步 |
| GET | /api/repos/:id/sync/status | 获取同步状态 |

### 4.3 分析结果

| 方法 | 路径 |说明 |
|------|------|------|
| GET | /api/repos/:id/prs | 获取 PR 列表 |
| GET | /api/repos/:id/prs/:number | 获取单个 PR 分析结果 |
| GET | /api/repos/:id/issues | 获取 Issue 列表 |
| GET | /api/repos/:id/analysis/duplicates | 获取去重报告 |
| GET | /api/repos/:id/analysis/dependencies | 获取依赖图 |

## 5. AI 分析流程

### 5.1 去重分析

```
1. 获取所有 PR/Issue
2. 对每个 PR/Issue:
   a. 提取关键信息（标题、描述、改动文件）
   b. 与其他 PR/Issue 比较
   c. 计算相似度分数
   d. 超过阈值则标记为可能重复
3. 生成去重报告
```

### 5.2 依赖检测

```
1. 获取 PR 的 base/head 分支信息
2. 分析代码改动时间线
3. 查找是否有共享的提交
4. 构建依赖图
```

### 5.3 偏离度评估

```
1. 读取 Vision 文档
2. 分析 PR 的改动内容
3. 使用 AI 比较改动与 Vision 的契合度
4. 计算偏离分数 (0-100)
5. 生成偏离原因说明
```

## 6. Vision 文档格式

```markdown
# Project Vision

## Core Features
- Feature A: description
- Feature B: description

## Technical Requirements
- Language: TypeScript
- Framework: React
- Database: PostgreSQL

## Non-Goals
- Feature that we explicitly don't want
- Something out of scope

## Design Principles
- Keep it simple
- Prefer TypeScript over JavaScript
- Use established libraries
```

## 7. GitHub Action

```yaml
name: PR Radar Analysis
on: [pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: pr-radar/action@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          openai-key: ${{ secrets.OPENAI_API_KEY }}
          vision-path: ./VISION.md
          output: json
```

## 8. 配置项

| 环境变量 | 说明 | 默认值 |
|----------|------|--------|
| DATABASE_URL | PostgreSQL 连接串 | - |
| GITHUB_TOKEN | GitHub 访问令牌 | - |
| OPENAI_API_KEY | OpenAI API 密钥 | - |
| OLLAMA_BASE_URL | Ollama 服务地址 | http://localhost:11434 |
| AI_PROVIDER | AI 提供商 (openai/ollama) | openai |
| PORT | 服务端口 | 3000 |

## 9. 验收标准

- [ ] 可以添加 GitHub 仓库并同步数据
- [ ] 可以查看 PR 和 Issue 列表
- [ ] AI 去重分析能正确识别相似 PR/Issue
- [ ] PR 依赖检测能正确显示依赖关系
- [ ] Vision 偏离度评估能给出偏离分数和原因
- [ ] GitHub Action 可以正常运行并输出分析结果
- [ ] Web 界面可以正常浏览和管理
