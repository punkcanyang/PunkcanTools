import OpenAI from 'openai';
import { PrismaClient, PullRequest, Issue } from '@prisma/client';

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const prisma = new PrismaClient();

type PRWithRepo = PullRequest & {
  repository?: {
    visionDoc: string | null;
  };
};

export async function analyzePRs(
  prs: PRWithRepo[],
  repositoryId: string
) {
  const repo = await prisma.repository.findUnique({
    where: { id: repositoryId },
  });

  for (let i = 0; i < prs.length; i++) {
    const pr = prs[i];
    
    // Find duplicates
    const duplicates = await findDuplicatePRs(pr, prs.slice(i + 1));
    
    // Calculate deviation from vision
    let deviationScore = null;
    let deviationReason = null;
    let visionMatch = null;
    
    if (repo?.visionDoc) {
      const visionResult = await analyzeDeviation(pr, repo.visionDoc);
      deviationScore = visionResult.score;
      deviationReason = visionResult.reason;
      visionMatch = visionResult.match;
    }

    await prisma.pRAnalysis.upsert({
      where: { prId: pr.id },
      create: {
        prId: pr.id,
        similarityScore: duplicates.similarity,
        isDuplicate: duplicates.isDuplicate,
        duplicateOfId: duplicates.duplicateOfId,
        deviationScore,
        deviationReason,
        visionMatch,
      },
      update: {
        similarityScore: duplicates.similarity,
        isDuplicate: duplicates.isDuplicate,
        duplicateOfId: duplicates.duplicateOfId,
        deviationScore,
        deviationReason,
        visionMatch,
      },
    });
  }
}

export async function analyzeIssues(
  issues: Issue[],
  repositoryId: string
) {
  for (let i = 0; i < issues.length; i++) {
    const issue = issues[i];
    const duplicates = await findDuplicateIssues(issue, issues.slice(i + 1));

    await prisma.issueAnalysis.upsert({
      where: { issueId: issue.id },
      create: {
        issueId: issue.id,
        similarityScore: duplicates.similarity,
        isDuplicate: duplicates.isDuplicate,
        duplicateOfId: duplicates.duplicateOfId,
      },
      update: {
        similarityScore: duplicates.similarity,
        isDuplicate: duplicates.isDuplicate,
        duplicateOfId: duplicates.duplicateOfId,
      },
    });
  }
}

async function findDuplicatePRs(
  pr: PullRequest,
  otherPRs: PullRequest[]
): Promise<{
  similarity: number | null;
  isDuplicate: boolean;
  duplicateOfId: string | null;
}> {
  if (otherPRs.length === 0) {
    return { similarity: null, isDuplicate: false, duplicateOfId: null };
  }

  const prompt = `You are analyzing potential duplicate pull requests.
  
Current PR:
- Title: ${pr.title}
- Description: ${pr.body || 'No description'}

Other PRs to compare:
${otherPRs.map((p, i) => `${i + 1}. #${p.number}: ${p.title}\n   Description: ${p.body || 'No description'}`).join('\n')}

For each other PR, provide a similarity score from 0 to 1 (where 1 is identical).
Respond in JSON format:
{
  "mostSimilar": { "index": number, "score": number },
  "isDuplicate": boolean,
  "reason": "brief explanation"
}`;

  try {
    const response = await openai.chat.completions.create({
      model: 'gpt-4',
      messages: [{ role: 'user', content: prompt }],
      response_format: { type: 'json_object' },
    });

    const result = JSON.parse(response.choices[0]?.message?.content || '{}');
    
    if (result.mostSimilar && result.mostSimilar.score > 0.7) {
      return {
        similarity: result.mostSimilar.score,
        isDuplicate: result.isDuplicate,
        duplicateOfId: otherPRs[result.mostSimilar.index]?.id || null,
      };
    }
  } catch (error) {
    console.error('AI analysis failed:', error);
  }

  return { similarity: null, isDuplicate: false, duplicateOfId: null };
}

async function findDuplicateIssues(
  issue: Issue,
  otherIssues: Issue[]
): Promise<{
  similarity: number | null;
  isDuplicate: boolean;
  duplicateOfId: string | null;
}> {
  if (otherIssues.length === 0) {
    return { similarity: null, isDuplicate: false, duplicateOfId: null };
  }

  const prompt = `You are analyzing potential duplicate issues.
  
Current Issue:
- Title: ${issue.title}
- Description: ${issue.body || 'No description'}

Other Issues to compare:
${otherIssues.map((i, idx) => `${idx + 1}. #${i.number}: ${i.title}\n   Description: ${i.body || 'No description'}`).join('\n')}

For each other issue, provide a similarity score from 0 to 1.
Respond in JSON format:
{
  "mostSimilar": { "index": number, "score": number },
  "isDuplicate": boolean,
  "reason": "brief explanation"
}`;

  try {
    const response = await openai.chat.completions.create({
      model: 'gpt-4',
      messages: [{ role: 'user', content: prompt }],
      response_format: { type: 'json_object' },
    });

    const result = JSON.parse(response.choices[0]?.message?.content || '{}');
    
    if (result.mostSimilar && result.mostSimilar.score > 0.7) {
      return {
        similarity: result.mostSimilar.score,
        isDuplicate: result.isDuplicate,
        duplicateOfId: otherIssues[result.mostSimilar.index]?.id || null,
      };
    }
  } catch (error) {
    console.error('AI analysis failed:', error);
  }

  return { similarity: null, isDuplicate: false, duplicateOfId: null };
}

async function analyzeDeviation(
  pr: PullRequest,
  visionDoc: string
): Promise<{
  score: number;
  reason: string;
  match: number;
}> {
  const prompt = `You are analyzing how well a pull request aligns with the project vision.

Project Vision:
${visionDoc}

Pull Request:
- Title: ${pr.title}
- Description: ${pr.body || 'No description'}
- Base Branch: ${pr.baseBranch}
- Files Changed: ${JSON.stringify(pr.filesChanged || [])}

Analyze how well this PR aligns with the vision. Consider:
1. Does it add features mentioned in the vision?
2. Does it violate any non-goals?
3. Does it follow the technical requirements?

Respond in JSON format:
{
  "score": number (0-100, higher = more deviated),
  "match": number (0-100, higher = better match),
  "reason": "detailed explanation of the deviation"
}`;

  try {
    const response = await openai.chat.completions.create({
      model: 'gpt-4',
      messages: [{ role: 'user', content: prompt }],
      response_format: { type: 'json_object' },
    });

    const result = JSON.parse(response.choices[0]?.message?.content || '{}');
    return {
      score: result.score ?? 50,
      match: result.match ?? 50,
      reason: result.reason ?? 'Unable to analyze',
    };
  } catch (error) {
    console.error('Vision analysis failed:', error);
    return { score: 50, match: 50, reason: 'Analysis failed' };
  }
}
