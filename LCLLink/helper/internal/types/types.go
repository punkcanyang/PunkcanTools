/*
__ai_context__: 共享类型定义，与 Chrome 扩展的 config.ts 对应。
定义了 ServerConfig、代理实例、API 请求/响应等核心数据结构。
*/
package types

// ============================================================
// 协议类型
// WHY: 与 TypeScript ProtocolType 枚举保持一致
// ============================================================

const (
	ProtocolVLESS          = "vless"
	ProtocolTrojan         = "trojan"
	ProtocolShadowsocks    = "shadowsocks"
	ProtocolShadowsocks2022 = "shadowsocks-2022"
	ProtocolHysteria2      = "hysteria2"
	ProtocolTUIC           = "tuic"
	ProtocolWireGuard      = "wireguard"
)

// ============================================================
// 服务器配置（从扩展传入）
// WHY: 镜像 TypeScript ServerConfig 结构
// ============================================================

// ServerConfig 服务器节点配置
type ServerConfig struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Protocol string `json:"protocol"`
	Address  string `json:"address"`
	Port     int    `json:"port"`

	TLS       TLSConfig       `json:"tls"`
	WebSocket WebSocketConfig `json:"websocket"`

	// WHY: 使用 map 而非具体 struct，因为不同协议字段不同
	ProtocolConfig map[string]interface{} `json:"protocolConfig"`
}

// TLSConfig TLS 安全配置
type TLSConfig struct {
	Enabled       bool     `json:"enabled"`
	ServerName    string   `json:"serverName"`
	AllowInsecure bool     `json:"allowInsecure"`
	ALPN          []string `json:"alpn"`
	Fingerprint   string   `json:"fingerprint"`
}

// WebSocketConfig WebSocket 传输配置
type WebSocketConfig struct {
	Path              string            `json:"path"`
	Headers           map[string]string `json:"headers"`
	MaxEarlyData      int               `json:"maxEarlyData"`
	EarlyDataHeaderName string          `json:"earlyDataHeaderName"`
}

// ============================================================
// 代理实例
// ============================================================

// ProxyInstance 一个运行中的代理实例
type ProxyInstance struct {
	// 分配的本地 SOCKS5 端口
	Port int `json:"port"`
	// 关联的服务器配置
	Server ServerConfig `json:"server"`
	// 运行状态
	Status string `json:"status"` // "running", "stopped", "error"
	// 启动时间 (Unix timestamp)
	StartedAt int64 `json:"startedAt"`
	// 错误信息
	Error string `json:"error,omitempty"`
}

// ============================================================
// HTTP API 请求/响应
// ============================================================

// ConnectRequest 创建代理实例的请求
type ConnectRequest struct {
	Server ServerConfig `json:"server"`
	// 可选：指定端口（0 表示自动分配）
	PreferredPort int `json:"preferredPort,omitempty"`
}

// ConnectResponse 创建代理实例的响应
type ConnectResponse struct {
	Port int `json:"port"`
}

// StatusResponse 查询所有运行实例的响应
type StatusResponse struct {
	Instances []ProxyInstance `json:"instances"`
	Version   string         `json:"version"`
	Uptime    int64          `json:"uptime"` // 秒
}

// HealthResponse 健康检查响应
type HealthResponse struct {
	OK      bool   `json:"ok"`
	Version string `json:"version"`
}

// APIError 统一错误响应
type APIError struct {
	Error string `json:"error"`
}

// ============================================================
// Native Messaging 消息
// ============================================================

// NativeMessage Chrome Native Messaging 协议的消息格式
type NativeMessage struct {
	Action  string      `json:"action"`
	Payload interface{} `json:"payload,omitempty"`
}

// NM Actions
const (
	NMActionPing       = "ping"
	NMActionShutdown   = "shutdown"
	NMActionGetStatus  = "get_status"
)

/*
[For Future AI]
1. Key assumptions:
   - ServerConfig.ProtocolConfig 使用 map[string]interface{} 来兼容所有协议的配置字段
   - ProxyInstance.Port 是本地 SOCKS5 监听端口
   - HTTP API 和 Native Messaging 共享同一套类型
2. Potential edge cases:
   - ProtocolConfig 中的数值可能被 JSON 解析为 float64
   - 端口号需要校验范围 (10001-10099)
3. Dependencies: 无外部依赖
*/
