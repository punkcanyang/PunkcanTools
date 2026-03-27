/*
__ai_context__: xray-core 引擎封装。
定义 Engine 接口和 xray-core 具体实现。
根据 ServerConfig 生成 xray-core JSON 配置并启动本地 SOCKS5 代理实例。
*/
package engine

import (
	"encoding/json"
	"fmt"
	"log"

	"github.com/punkcan/lcllink-helper/internal/types"

	"github.com/xtls/xray-core/core"
	_ "github.com/xtls/xray-core/main/distro/all" // WHY: 注册所有 xray-core 模块
)

// ============================================================
// Engine 接口
// WHY: 抽象代理引擎，便于测试和未来替换实现
// ============================================================

// Engine 代理引擎接口
type Engine interface {
	Start() error
	Stop() error
}

// ============================================================
// XrayEngine 实现
// ============================================================

// XrayEngine xray-core 引擎实例
type XrayEngine struct {
	instance *core.Instance
	port     int
	server   types.ServerConfig
}

// NewXrayEngine 创建 xray-core 引擎实例
func NewXrayEngine(localPort int, server types.ServerConfig) (*XrayEngine, error) {
	return &XrayEngine{
		port:   localPort,
		server: server,
	}, nil
}

// Start 启动 xray-core 实例
func (e *XrayEngine) Start() error {
	// Step 1: 生成 xray-core JSON 配置
	configJSON, err := e.buildConfig()
	if err != nil {
		return fmt.Errorf("生成配置失败: %w", err)
	}

	log.Printf("[Engine] 启动代理 (端口 %d → %s:%d)", e.port, e.server.Address, e.server.Port)

	// Step 2: 解析配置并创建实例
	config, err := core.LoadConfig("json", configJSON)
	if err != nil {
		return fmt.Errorf("加载 xray-core 配置失败: %w", err)
	}

	instance, err := core.New(config)
	if err != nil {
		return fmt.Errorf("创建 xray-core 实例失败: %w", err)
	}

	// Step 3: 启动实例
	err = instance.Start()
	if err != nil {
		return fmt.Errorf("启动 xray-core 实例失败: %w", err)
	}

	e.instance = instance
	return nil
}

// Stop 停止 xray-core 实例
func (e *XrayEngine) Stop() error {
	if e.instance == nil {
		return nil
	}
	err := e.instance.Close()
	e.instance = nil
	return err
}

// ============================================================
// 配置生成
// WHY: 根据 ServerConfig 动态生成 xray-core 的 JSON 配置
// ============================================================

func (e *XrayEngine) buildConfig() ([]byte, error) {
	// 构建 outbound settings（因协议而异）
	outboundSettings, err := e.buildOutboundSettings()
	if err != nil {
		return nil, err
	}

	// 构建 stream settings（传输层配置）
	streamSettings := e.buildStreamSettings()

	// 完整的 xray-core JSON 配置
	config := map[string]interface{}{
		// WHY: 仅输出错误日志，避免 stdout 干扰 NM 协议
		"log": map[string]interface{}{
			"loglevel": "warning",
		},
		// 入站：本地 SOCKS5 代理
		"inbounds": []map[string]interface{}{
			{
				"port":     e.port,
				"listen":   "127.0.0.1",
				"protocol": "socks",
				"settings": map[string]interface{}{
					"auth": "noauth",
					"udp":  true,
				},
			},
		},
		// 出站：连接远端服务器
		"outbounds": []map[string]interface{}{
			{
				"protocol":       e.server.Protocol,
				"settings":       outboundSettings,
				"streamSettings": streamSettings,
			},
		},
	}

	return json.Marshal(config)
}

// buildOutboundSettings 根据协议类型构建出站配置
func (e *XrayEngine) buildOutboundSettings() (map[string]interface{}, error) {
	pc := e.server.ProtocolConfig

	switch e.server.Protocol {
	case types.ProtocolVLESS:
		return e.buildVLESSSettings(pc)
	case types.ProtocolTrojan:
		return e.buildTrojanSettings(pc)
	case types.ProtocolShadowsocks, types.ProtocolShadowsocks2022:
		return e.buildShadowsocksSettings(pc)
	default:
		return nil, fmt.Errorf("不支持的协议: %s", e.server.Protocol)
	}
}

func (e *XrayEngine) buildVLESSSettings(pc map[string]interface{}) (map[string]interface{}, error) {
	uuid, _ := pc["uuid"].(string)
	encryption, _ := pc["encryption"].(string)
	flow, _ := pc["flow"].(string)

	if encryption == "" {
		encryption = "none"
	}

	user := map[string]interface{}{
		"id":         uuid,
		"encryption": encryption,
	}

	// WHY: flow 只在非 WebSocket 传输时使用
	if flow != "" {
		user["flow"] = flow
	}

	return map[string]interface{}{
		"vnext": []map[string]interface{}{
			{
				"address": e.server.Address,
				"port":    e.server.Port,
				"users":   []map[string]interface{}{user},
			},
		},
	}, nil
}

func (e *XrayEngine) buildTrojanSettings(pc map[string]interface{}) (map[string]interface{}, error) {
	password, _ := pc["password"].(string)

	return map[string]interface{}{
		"servers": []map[string]interface{}{
			{
				"address":  e.server.Address,
				"port":     e.server.Port,
				"password": password,
			},
		},
	}, nil
}

func (e *XrayEngine) buildShadowsocksSettings(pc map[string]interface{}) (map[string]interface{}, error) {
	method, _ := pc["method"].(string)
	password, _ := pc["password"].(string)

	return map[string]interface{}{
		"servers": []map[string]interface{}{
			{
				"address":  e.server.Address,
				"port":     e.server.Port,
				"method":   method,
				"password": password,
			},
		},
	}, nil
}

// buildStreamSettings 构建传输层配置（TLS/Reality/WebSocket/TCP）
func (e *XrayEngine) buildStreamSettings() map[string]interface{} {
	stream := map[string]interface{}{}

	// 传输方式
	// WHY: 有 WebSocket 配置就用 ws，否则用 tcp（Reality 通常走 tcp）
	if e.server.WebSocket.Path != "" && e.server.WebSocket.Path != "/" {
		stream["network"] = "ws"
		stream["wsSettings"] = map[string]interface{}{
			"path":    e.server.WebSocket.Path,
			"headers": e.server.WebSocket.Headers,
		}
	} else {
		stream["network"] = "tcp"
	}

	// TLS 配置
	if e.server.TLS.Enabled {
		// 检查是否为 Reality
		realityConfig, hasReality := e.extractRealityConfig()

		if hasReality && realityConfig["enabled"] == true {
			// Reality 模式
			stream["security"] = "reality"
			realitySettings := map[string]interface{}{
				"serverName": e.server.TLS.ServerName,
				"fingerprint": e.server.TLS.Fingerprint,
			}

			if pubKey, ok := realityConfig["publicKey"].(string); ok && pubKey != "" {
				realitySettings["publicKey"] = pubKey
			}
			if shortId, ok := realityConfig["shortId"].(string); ok && shortId != "" {
				realitySettings["shortId"] = shortId
			}
			if spiderX, ok := realityConfig["spiderX"].(string); ok && spiderX != "" {
				realitySettings["spiderX"] = spiderX
			}

			stream["realitySettings"] = realitySettings
		} else {
			// 标准 TLS
			stream["security"] = "tls"
			tlsSettings := map[string]interface{}{
				"serverName":    e.server.TLS.ServerName,
				"allowInsecure": e.server.TLS.AllowInsecure,
			}
			if len(e.server.TLS.ALPN) > 0 {
				tlsSettings["alpn"] = e.server.TLS.ALPN
			}
			if e.server.TLS.Fingerprint != "" {
				tlsSettings["fingerprint"] = e.server.TLS.Fingerprint
			}
			stream["tlsSettings"] = tlsSettings
		}
	}

	return stream
}

// extractRealityConfig 从 ProtocolConfig 中提取 Reality 配置
// WHY: Reality 配置嵌套在 VLESS 的 protocolConfig.reality 中
func (e *XrayEngine) extractRealityConfig() (map[string]interface{}, bool) {
	reality, ok := e.server.ProtocolConfig["reality"]
	if !ok {
		return nil, false
	}

	realityMap, ok := reality.(map[string]interface{})
	if !ok {
		return nil, false
	}

	return realityMap, true
}

/*
[For Future AI]
1. Key assumptions:
   - 使用 xray-core 的库模式（非命令行模式），直接调用 Go API
   - 每个引擎实例独立运行一个 SOCKS5 入站 + 一个协议出站
   - Reality 配置从 VLESS 的 protocolConfig.reality 字段提取
2. Potential edge cases:
   - xray-core 实例启动失败需要正确清理
   - port 冲突导致 SOCKS5 绑定失败
   - Reality 的 publicKey/shortId 如果格式错误会导致握手失败
   - JSON 配置的数值类型可能因为 interface{} 序列化问题丢失
3. Dependencies: xray-core/core, types 包
*/
