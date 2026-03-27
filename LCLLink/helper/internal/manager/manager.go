/*
__ai_context__: 代理实例管理器。
核心模块，负责管理多个 SOCKS5 代理实例的生命周期。
每个实例占用一个本地端口，连接到一个远端服务器。
支持动态创建/销毁/查询实例——实现多浏览器独立 IP 的关键。
*/
package manager

import (
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/punkcan/lcllink-helper/internal/engine"
	"github.com/punkcan/lcllink-helper/internal/types"
)

// ============================================================
// 常量
// ============================================================

const (
	// 端口池范围
	PortRangeStart = 10001
	PortRangeEnd   = 10099
)

// ============================================================
// Manager 结构体
// ============================================================

// Manager 代理实例管理器（线程安全）
type Manager struct {
	mu        sync.RWMutex
	instances map[int]*instanceEntry // key = 本地端口号
	startedAt time.Time
}

// instanceEntry 内部实例记录
type instanceEntry struct {
	info   types.ProxyInstance
	engine engine.Engine // xray-core 引擎实例
}

// New 创建管理器
func New() *Manager {
	return &Manager{
		instances: make(map[int]*instanceEntry),
		startedAt: time.Now(),
	}
}

// ============================================================
// 创建代理实例
// WHY: 每个浏览器 Profile 调用一次，获得独立的本地端口
// ============================================================

// Connect 创建并启动一个代理实例
func (m *Manager) Connect(req types.ConnectRequest) (*types.ConnectResponse, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Step 1: 分配端口
	port := req.PreferredPort
	if port == 0 || m.isPortInUse(port) {
		var err error
		port, err = m.allocatePort()
		if err != nil {
			return nil, err
		}
	}

	// Step 2: 创建 xray-core 引擎实例
	eng, err := engine.NewXrayEngine(port, req.Server)
	if err != nil {
		return nil, fmt.Errorf("创建代理引擎失败: %w", err)
	}

	// Step 3: 启动引擎
	err = eng.Start()
	if err != nil {
		return nil, fmt.Errorf("启动代理引擎失败: %w", err)
	}

	// Step 4: 注册实例
	entry := &instanceEntry{
		info: types.ProxyInstance{
			Port:      port,
			Server:    req.Server,
			Status:    "running",
			StartedAt: time.Now().Unix(),
		},
		engine: eng,
	}

	m.instances[port] = entry

	log.Printf("[Manager] 实例启动成功: 端口=%d, 服务器=%s:%d (%s)",
		port, req.Server.Address, req.Server.Port, req.Server.Protocol)

	return &types.ConnectResponse{Port: port}, nil
}

// ============================================================
// 断开代理实例
// ============================================================

// Disconnect 停止并销毁指定端口的代理实例
func (m *Manager) Disconnect(port int) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	entry, exists := m.instances[port]
	if !exists {
		return fmt.Errorf("端口 %d 上没有运行的实例", port)
	}

	// 停止引擎
	err := entry.engine.Stop()
	if err != nil {
		log.Printf("[Manager] 停止引擎出错（端口 %d）: %v", port, err)
	}

	delete(m.instances, port)
	log.Printf("[Manager] 实例已停止: 端口=%d", port)

	return nil
}

// ============================================================
// 查询状态
// ============================================================

// GetStatus 获取所有运行中实例的状态
func (m *Manager) GetStatus() types.StatusResponse {
	m.mu.RLock()
	defer m.mu.RUnlock()

	instances := make([]types.ProxyInstance, 0, len(m.instances))
	for _, entry := range m.instances {
		instances = append(instances, entry.info)
	}

	return types.StatusResponse{
		Instances: instances,
		Version:   "0.1.0",
		Uptime:    int64(time.Since(m.startedAt).Seconds()),
	}
}

// InstanceCount 返回当前运行实例数
func (m *Manager) InstanceCount() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return len(m.instances)
}

// ============================================================
// 全部停止
// ============================================================

// ShutdownAll 停止所有实例
func (m *Manager) ShutdownAll() {
	m.mu.Lock()
	defer m.mu.Unlock()

	for port, entry := range m.instances {
		err := entry.engine.Stop()
		if err != nil {
			log.Printf("[Manager] 停止端口 %d 出错: %v", port, err)
		}
	}

	m.instances = make(map[int]*instanceEntry)
	log.Println("[Manager] 所有实例已停止")
}

// ============================================================
// 内部方法
// ============================================================

// allocatePort 从端口池中分配一个空闲端口
func (m *Manager) allocatePort() (int, error) {
	for port := PortRangeStart; port <= PortRangeEnd; port++ {
		if !m.isPortInUse(port) {
			return port, nil
		}
	}
	return 0, fmt.Errorf("端口池已满 (%d-%d)，共 %d 个实例",
		PortRangeStart, PortRangeEnd, len(m.instances))
}

// isPortInUse 检查端口是否已被占用
func (m *Manager) isPortInUse(port int) bool {
	_, exists := m.instances[port]
	return exists
}

/*
[For Future AI]
1. Key assumptions:
   - 端口池范围固定为 10001-10099（99 个代理实例上限）
   - 所有操作通过 sync.RWMutex 保证线程安全
   - Engine 接口抽象了 xray-core 具体实现
2. Potential edge cases:
   - 端口被系统其他进程占用（需要 engine.Start 检测）
   - 并发创建大量实例时的竞争
   - 引擎启动失败后需要清理已分配的端口
3. Dependencies: engine 包, types 包
*/
