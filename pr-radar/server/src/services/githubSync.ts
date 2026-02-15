import { Octokit } from 'octokit';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN });

export async function syncRepository(
  repositoryId: string,
  owner: string,
  name: string
) {
  // Sync Pull Requests
  const prs = await octokit.paginate('GET /repos/{owner}/{repo}/pulls', {
    owner,
    repo: name,
    state: 'all',
    per_page: 100,
  });

  for (const pr of prs) {
    const filesResponse = await octokit.request(
      'GET /repos/{owner}/{repo}/pulls/{pull_number}/files',
      {
        owner,
        repo: name,
        pull_number: pr.number,
        per_page: 100,
      }
    );

    await prisma.pullRequest.upsert({
      where: {
        repositoryId_number: {
          repositoryId,
          number: pr.number,
        },
      },
      create: {
        repositoryId,
        number: pr.number,
        title: pr.title,
        body: pr.body,
        state: pr.state ?? 'unknown',
        author: pr.user?.login ?? 'unknown',
        baseBranch: pr.base?.ref ?? '',
        headBranch: pr.head?.ref ?? '',
        filesChanged: filesResponse.data.map(f => ({
          filename: f.filename,
          status: f.status,
          additions: f.additions,
          deletions: f.deletions,
        })),
        additions: pr.additions ?? 0,
        deletions: pr.deletions ?? 0,
        mergedAt: pr.merged_at ? new Date(pr.merged_at) : null,
        createdAt: new Date(pr.created_at),
      },
      update: {
        title: pr.title,
        body: pr.body,
        state: pr.state ?? 'unknown',
        filesChanged: filesResponse.data.map(f => ({
          filename: f.filename,
          status: f.status,
          additions: f.additions,
          deletions: f.deletions,
        })),
        additions: pr.additions ?? 0,
        deletions: pr.deletions ?? 0,
        mergedAt: pr.merged_at ? new Date(pr.merged_at) : null,
      },
    });
  }

  // Sync Issues
  const issues = await octokit.paginate('GET /repos/{owner}/{repo}/issues', {
    owner,
    repo: name,
    state: 'all',
    per_page: 100,
  });

  for (const issue of issues) {
    if (issue.pull_request) continue;

    await prisma.issue.upsert({
      where: {
        repositoryId_number: {
          repositoryId,
          number: issue.number,
        },
      },
      create: {
        repositoryId,
        number: issue.number,
        title: issue.title,
        body: issue.body,
        state: issue.state ?? 'unknown',
        author: issue.user?.login ?? 'unknown',
        labels: issue.labels.map(l =>
          typeof l === 'string' ? l : l.name ?? ''
        ),
        createdAt: new Date(issue.created_at),
      },
      update: {
        title: issue.title,
        body: issue.body,
        state: issue.state ?? 'unknown',
        labels: issue.labels.map(l =>
          typeof l === 'string' ? l : l.name ?? ''
        ),
      },
    });
  }

  // Detect dependencies
  await detectDependencies(repositoryId);
}

async function detectDependencies(repositoryId: string) {
  const prs = await prisma.pullRequest.findMany({
    where: { repositoryId },
    orderBy: { createdAt: 'asc' },
  });

  for (const pr of prs) {
    const potentialDeps = prs.filter(p => 
      p.id !== pr.id && 
      p.createdAt < pr.createdAt &&
      hasFileOverlap(pr.filesChanged, p.filesChanged)
    );

    for (const dep of potentialDeps) {
      await prisma.pullRequest.update({
        where: { id: pr.id },
        data: {
          dependencies: {
            connect: { id: dep.id },
          },
        },
      });
    }
  }
}

function hasFileOverlap(
  files1: unknown,
  files2: unknown
): boolean {
  if (!Array.isArray(files1) || !Array.isArray(files2)) return false;
  
  const set1 = new Set(files1.map((f: unknown) => (f as { filename?: string }).filename));
  const set2 = new Set(files2.map((f: unknown) => (f as { filename?: string }).filename));
  
  for (const file of set1) {
    if (set2.has(file)) return true;
  }
  return false;
}
