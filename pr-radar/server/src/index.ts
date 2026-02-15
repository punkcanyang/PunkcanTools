import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { Octokit } from 'octokit';
import { PrismaClient } from '@prisma/client';
import { analyzePRs, analyzeIssues } from './services/aiAnalyzer.js';
import { syncRepository } from './services/githubSync.js';
import { router } from './routes/index.js';

const app = express();
const prisma = new PrismaClient();
const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN });

app.use(cors());
app.use(express.json());

app.use('/api', router);

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`PR Radar server running on port ${PORT}`);
});

process.on('SIGINT', async () => {
  await prisma.$disconnect();
  process.exit(0);
});
