/*
__ai_context__: HTTP API 服务器。
监听 127.0.0.1:19527，提供 RESTful API 供多个浏览器实例控制代理。
所有 API 只接受来自本地的请求（安全约束）。
*/
package api

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/punkcan/lcllink-helper/internal/manager"
	"github.com/punkcan/lcllink-helper/internal/types"
	"github.com/punkcan/lcllink-helper/web"
)

// ============================================================
// 常量
// ============================================================

const (
	// APIPort HTTP API 监听端口
	APIPort = 19527
	// APIAddr 只监听本地回环地址（安全）
	APIAddr = "127.0.0.1:19527"
)

// ============================================================
// Server 结构体
// ============================================================

// Server HTTP API 服务器
type Server struct {
	mgr    *manager.Manager
	server *http.Server
}

// New 创建 API 服务器
func New(mgr *manager.Manager) *Server {
	s := &Server{mgr: mgr}

	mux := http.NewServeMux()

	// 注册路由
	mux.HandleFunc("/api/health", s.handleHealth)
	mux.HandleFunc("/api/status", s.handleStatus)
	mux.HandleFunc("/api/connect", s.handleConnect)
	// WHY: Go 标准库不支持路径参数，使用前缀匹配 + 手动提取
	mux.HandleFunc("/api/disconnect/", s.handleDisconnect)

	// Web UI（嵌入的静态文件）
	// WHY: 访问 http://127.0.0.1:19527/ 即可打开管理面板
	webFS, _ := fs.Sub(web.Content, ".")
	mux.Handle("/", http.FileServer(http.FS(webFS)))

	s.server = &http.Server{
		Addr:    APIAddr,
		Handler: withCORS(mux),
	}

	return s
}

// Start 启动 HTTP 服务器（非阻塞）
func (s *Server) Start() error {
	log.Printf("[API] 启动 HTTP API: http://%s", APIAddr)

	go func() {
		err := s.server.ListenAndServe()
		if err != nil && err != http.ErrServerClosed {
			log.Printf("[API] HTTP 服务器错误: %v", err)
		}
	}()

	return nil
}

// Stop 关闭 HTTP 服务器
func (s *Server) Stop() {
	if s.server != nil {
		_ = s.server.Close()
	}
}

// ============================================================
// 路由处理
// ============================================================

// GET /api/health — 健康检查
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "只接受 GET 请求")
		return
	}

	writeJSON(w, http.StatusOK, types.HealthResponse{
		OK:      true,
		Version: "0.1.0",
	})
}

// GET /api/status — 查询所有实例
func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "只接受 GET 请求")
		return
	}

	status := s.mgr.GetStatus()
	writeJSON(w, http.StatusOK, status)
}

// POST /api/connect — 创建代理实例
func (s *Server) handleConnect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "只接受 POST 请求")
		return
	}

	var req types.ConnectRequest
	err := json.NewDecoder(r.Body).Decode(&req)
	if err != nil {
		writeError(w, http.StatusBadRequest, fmt.Sprintf("请求体解析失败: %v", err))
		return
	}

	// 校验必填字段
	if req.Server.Address == "" || req.Server.Port == 0 {
		writeError(w, http.StatusBadRequest, "缺少服务器地址或端口")
		return
	}

	resp, err := s.mgr.Connect(req)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

// DELETE /api/disconnect/:port — 断开指定端口
func (s *Server) handleDisconnect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		writeError(w, http.StatusMethodNotAllowed, "只接受 DELETE 请求")
		return
	}

	// 从路径中提取端口号: /api/disconnect/10001
	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 4 {
		writeError(w, http.StatusBadRequest, "缺少端口参数")
		return
	}

	portStr := parts[len(parts)-1]
	port, err := strconv.Atoi(portStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, fmt.Sprintf("无效端口号: %s", portStr))
		return
	}

	err = s.mgr.Disconnect(port)
	if err != nil {
		writeError(w, http.StatusNotFound, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "disconnected"})
}

// ============================================================
// 辅助函数
// ============================================================

// writeJSON 写入 JSON 响应
func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}

// writeError 写入错误响应
func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, types.APIError{Error: message})
}

// withCORS 添加 CORS 中间件
// WHY: Chrome 扩展的 fetch 请求需要 CORS 允许
func withCORS(handler http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		handler.ServeHTTP(w, r)
	})
}

/*
[For Future AI]
1. Key assumptions:
   - API 只监听 127.0.0.1（不暴露到外网）
   - CORS 设置为 * 因为 Chrome 扩展的 origin 是 chrome-extension://
   - 使用 Go 标准库，不依赖第三方 HTTP 框架
2. Potential edge cases:
   - 端口 19527 可能被占用
   - 并发请求需要 Manager 的 mutex 保护（已在 Manager 中实现）
   - JSON 请求体过大可能导致 OOM（应添加 body size limit）
3. Dependencies: manager 包, types 包
*/
