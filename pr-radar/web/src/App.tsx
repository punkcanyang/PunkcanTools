import { useState, useEffect } from 'react';
import axios from 'axios';

const API = '/api';

interface Repository {
  id: string;
  owner: string;
  name: string;
  fullName: string;
  visionDoc: string | null;
  lastSyncAt: string | null;
}

interface PullRequest {
  id: string;
  number: number;
  title: string;
  body: string | null;
  state: string;
  author: string;
  baseBranch: string;
  headBranch: string;
  additions: number;
  deletions: number;
  analysis: PRAnalysis | null;
}

interface PRAnalysis {
  id: string;
  isDuplicate: boolean;
  similarityScore: number | null;
  deviationScore: number | null;
  deviationReason: string | null;
  visionMatch: number | null;
}

interface Issue {
  id: string;
  number: number;
  title: string;
  body: string | null;
  state: string;
  author: string;
  labels: string[];
  analysis: IssueAnalysis | null;
}

interface IssueAnalysis {
  id: string;
  isDuplicate: boolean;
  similarityScore: number | null;
}

function App() {
  const [repos, setRepos] = useState<Repository[]>([]);
  const [selectedRepo, setSelectedRepo] = useState<Repository | null>(null);
  const [prs, setPrs] = useState<PullRequest[]>([]);
  const [issues, setIssues] = useState<Issue[]>([]);
  const [activeTab, setActiveTab] = useState<'prs' | 'issues'>('prs');
  const [loading, setLoading] = useState(false);
  const [showAddRepo, setShowAddRepo] = useState(false);
  const [showVision, setShowVision] = useState(false);
  const [newRepo, setNewRepo] = useState({ owner: '', name: '' });
  const [visionContent, setVisionContent] = useState('');

  useEffect(() => {
    fetchRepos();
  }, []);

  useEffect(() => {
    if (selectedRepo) {
      fetchPRs(selectedRepo.id);
      fetchIssues(selectedRepo.id);
      if (selectedRepo.visionDoc) {
        setVisionContent(selectedRepo.visionDoc);
      }
    }
  }, [selectedRepo]);

  async function fetchRepos() {
    const res = await axios.get(`${API}/repos`);
    setRepos(res.data);
  }

  async function fetchPRs(repoId: string) {
    const res = await axios.get(`${API}/repos/${repoId}/prs`);
    setPrs(res.data);
  }

  async function fetchIssues(repoId: string) {
    const res = await axios.get(`${API}/repos/${repoId}/issues`);
    setIssues(res.data);
  }

  async function addRepo() {
    if (!newRepo.owner || !newRepo.name) return;
    await axios.post(`${API}/repos`, newRepo);
    setNewRepo({ owner: '', name: '' });
    setShowAddRepo(false);
    fetchRepos();
  }

  async function deleteRepo(id: string) {
    if (!confirm('确定删除这个仓库?')) return;
    await axios.delete(`${API}/repos/${id}`);
    if (selectedRepo?.id === id) {
      setSelectedRepo(null);
    }
    fetchRepos();
  }

  async function syncRepo(id: string) {
    setLoading(true);
    try {
      await axios.post(`${API}/repos/${id}/sync`);
      if (selectedRepo?.id === id) {
        fetchPRs(id);
        fetchIssues(id);
      }
      fetchRepos();
    } catch (error) {
      alert('同步失败: ' + error);
    }
    setLoading(false);
  }

  async function analyzeDuplicates(id: string) {
    setLoading(true);
    try {
      await axios.post(`${API}/repos/${id}/analyze/duplicates`);
      fetchPRs(id);
      fetchIssues(id);
    } catch (error) {
      alert('分析失败: ' + error);
    }
    setLoading(false);
  }

  async function saveVision() {
    if (!selectedRepo) return;
    await axios.put(`${API}/repos/${selectedRepo.id}/vision`, {
      visionDoc: visionContent,
    });
    fetchRepos();
    setShowVision(false);
  }

  function getStateBadge(state: string) {
    const stateMap: Record<string, { class: string; text: string }> = {
      open: { class: 'badge-open', text: 'Open' },
      closed: { class: 'badge-closed', text: 'Closed' },
      merged: { class: 'badge-merged', text: 'Merged' },
    };
    const s = stateMap[state] || { class: '', text: state };
    return <span className={`badge ${s.class}`}>{s.text}</span>;
  }

  return (
    <div className="container">
      <header>
        <h1>PR Radar</h1>
        <p>AI驱动的PR/Issue分析工具</p>
      </header>

      <div className="card">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
          <h2>仓库列表</h2>
          <button className="btn btn-primary" onClick={() => setShowAddRepo(!showAddRepo)}>
            添加仓库
          </button>
        </div>

        {showAddRepo && (
          <div className="form-group" style={{ background: '#f9f9f9', padding: '16px', borderRadius: '8px' }}>
            <div style={{ display: 'flex', gap: '12px' }}>
              <input
                placeholder="Owner (e.g., facebook)"
                value={newRepo.owner}
                onChange={(e) => setNewRepo({ ...newRepo, owner: e.target.value })}
              />
              <input
                placeholder="Repo name (e.g., react)"
                value={newRepo.name}
                onChange={(e) => setNewRepo({ ...newRepo, name: e.target.value })}
              />
              <button className="btn btn-primary" onClick={addRepo}>添加</button>
            </div>
          </div>
        )}

        <div className="repo-list">
          {repos.length === 0 ? (
            <div className="empty-state">暂无仓库，请添加一个</div>
          ) : (
            repos.map((repo) => (
              <div key={repo.id} className="repo-item">
                <div
                  className="repo-info"
                  onClick={() => setSelectedRepo(repo)}
                  style={{ cursor: 'pointer' }}
                >
                  <div className="repo-name">{repo.fullName}</div>
                  <div className="repo-meta">
                    最后同步: {repo.lastSyncAt ? new Date(repo.lastSyncAt).toLocaleString() : '从未同步'}
                  </div>
                </div>
                <div className="repo-actions">
                  <button className="btn btn-primary" onClick={() => syncRepo(repo.id)} disabled={loading}>
                    同步
                  </button>
                  <button className="btn btn-primary" onClick={() => analyzeDuplicates(repo.id)} disabled={loading}>
                    分析
                  </button>
                  <button className="btn btn-danger" onClick={() => deleteRepo(repo.id)}>
                    删除
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </div>

      {selectedRepo && (
        <>
          <div className="card">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
              <h2>{selectedRepo.fullName}</h2>
              <button className="btn btn-primary" onClick={() => setShowVision(!showVision)}>
                {showVision ? '关闭 Vision' : '编辑 Vision'}
              </button>
            </div>

            {showVision && (
              <div className="form-group">
                <label>Vision 文档 (Markdown 格式)</label>
                <textarea
                  value={visionContent}
                  onChange={(e) => setVisionContent(e.target.value)}
                  placeholder="# Project Vision&#10;&#10;## Core Features&#10;- Feature A&#10;&#10;## Technical Requirements&#10;- Language: TypeScript"
                />
                <button className="btn btn-primary" onClick={saveVision} style={{ marginTop: '8px' }}>
                  保存 Vision
                </button>
              </div>
            )}

            <div style={{ display: 'flex', gap: '8px', marginBottom: '16px' }}>
              <button
                className={`btn ${activeTab === 'prs' ? 'btn-primary' : ''}`}
                onClick={() => setActiveTab('prs')}
              >
                PRs ({prs.length})
              </button>
              <button
                className={`btn ${activeTab === 'issues' ? 'btn-primary' : ''}`}
                onClick={() => setActiveTab('issues')}
              >
                Issues ({issues.length})
              </button>
            </div>

            {activeTab === 'prs' ? (
              <div>
                {prs.length === 0 ? (
                  <div className="empty-state">暂无 PR 数据</div>
                ) : (
                  prs.map((pr) => (
                    <div key={pr.id} className="pr-item">
                      <div className="pr-title">
                        #{pr.number} {pr.title} {getStateBadge(pr.state)}
                      </div>
                      <div className="pr-meta">
                        <span>作者: {pr.author}</span>
                        <span>分支: {pr.headBranch} → {pr.baseBranch}</span>
                        <span>+{pr.additions} -{pr.deletions}</span>
                      </div>
                      {pr.analysis && (
                        <div style={{ marginTop: '8px', display: 'flex', gap: '16px' }}>
                          {pr.analysis.isDuplicate && (
                            <span className="badge badge-warning">可能重复</span>
                          )}
                          {pr.analysis.deviationScore !== null && (
                            <span>偏离度: {pr.analysis.deviationScore}%</span>
                          )}
                          {pr.analysis.visionMatch !== null && (
                            <span>Vision 匹配: {pr.analysis.visionMatch}%</span>
                          )}
                        </div>
                      )}
                    </div>
                  ))
                )}
              </div>
            ) : (
              <div>
                {issues.length === 0 ? (
                  <div className="empty-state">暂无 Issue 数据</div>
                ) : (
                  issues.map((issue) => (
                    <div key={issue.id} className="issue-item">
                      <div className="issue-title">
                        #{issue.number} {issue.title} {getStateBadge(issue.state)}
                      </div>
                      <div className="issue-meta">
                        <span>作者: {issue.author}</span>
                        {issue.labels.length > 0 && (
                          <span>标签: {issue.labels.map((l) => <span key={l} className="tag">{l}</span>)}</span>
                        )}
                      </div>
                      {issue.analysis?.isDuplicate && (
                        <div style={{ marginTop: '8px' }}>
                          <span className="badge badge-warning">可能重复</span>
                        </div>
                      )}
                    </div>
                  ))
                )}
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}

export default App;
