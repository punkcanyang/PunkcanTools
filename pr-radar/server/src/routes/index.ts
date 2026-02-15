import { Router } from 'express';
import { z } from 'zod';
import { PrismaClient } from '@prisma/client';
import { syncRepository } from '../services/githubSync.js';
import { analyzePRs, analyzeIssues } from '../services/aiAnalyzer.js';

const router = Router();
const prisma = new PrismaClient();

const repoSchema = z.object({
  owner: z.string(),
  name: z.string(),
});

const visionSchema = z.object({
  visionDoc: z.string(),
});

router.get('/repos', async (req, res) => {
  const repos = await prisma.repository.findMany({
    orderBy: { createdAt: 'desc' },
  });
  res.json(repos);
});

router.post('/repos', async (req, res) => {
  const { owner, name } = repoSchema.parse(req.body);
  const fullName = `${owner}/${name}`;

  try {
    const repo = await prisma.repository.create({
      data: { owner, name, fullName },
    });
    res.status(201).json(repo);
  } catch (error) {
    res.status(400).json({ error: 'Repository already exists' });
  }
});

router.delete('/repos/:id', async (req, res) => {
  const { id } = req.params;
  await prisma.repository.delete({ where: { id } });
  res.status(204).send();
});

router.put('/repos/:id/vision', async (req, res) => {
  const { id } = req.params;
  const { visionDoc } = visionSchema.parse(req.body);

  const repo = await prisma.repository.update({
    where: { id },
    data: { visionDoc },
  });
  res.json(repo);
});

router.post('/repos/:id/sync', async (req, res) => {
  const { id } = req.params;
  const repo = await prisma.repository.findUnique({ where: { id } });
  
  if (!repo) {
    return res.status(404).json({ error: 'Repository not found' });
  }

  try {
    await syncRepository(repo.id, repo.owner, repo.name);
    await prisma.repository.update({
      where: { id },
      data: { lastSyncAt: new Date() },
    });
    res.json({ status: 'synced' });
  } catch (error) {
    res.status(500).json({ error: String(error) });
  }
});

router.get('/repos/:id/prs', async (req, res) => {
  const { id } = req.params;
  const prs = await prisma.pullRequest.findMany({
    where: { repositoryId: id },
    include: { analysis: true },
    orderBy: { createdAt: 'desc' },
  });
  res.json(prs);
});

router.get('/repos/:id/issues', async (req, res) => {
  const { id } = req.params;
  const issues = await prisma.issue.findMany({
    where: { repositoryId: id },
    include: { analysis: true },
    orderBy: { createdAt: 'desc' },
  });
  res.json(issues);
});

router.post('/repos/:id/analyze/duplicates', async (req, res) => {
  const { id } = req.params;
  const repo = await prisma.repository.findUnique({ where: { id } });
  
  if (!repo) {
    return res.status(404).json({ error: 'Repository not found' });
  }

  const prs = await prisma.pullRequest.findMany({
    where: { repositoryId: id },
  });
  
  const issues = await prisma.issue.findMany({
    where: { repositoryId: id },
  });

  await analyzePRs(prs, repo.id);
  await analyzeIssues(issues, repo.id);

  res.json({ status: 'analyzed' });
});

router.get('/repos/:id/analysis/dependencies', async (req, res) => {
  const { id } = req.params;
  
  const prs = await prisma.pullRequest.findMany({
    where: { repositoryId: id },
    include: {
      dependencies: true,
      dependentOn: true,
    },
  });
  
  const nodes = prs.map(pr => ({
    id: pr.id,
    number: pr.number,
    title: pr.title,
    state: pr.state,
  }));
  
  const edges = prs.flatMap(pr => 
    pr.dependencies.map(dep => ({
      from: pr.id,
      to: dep.id,
    }))
  );
  
  res.json({ nodes, edges });
});

export { router };
