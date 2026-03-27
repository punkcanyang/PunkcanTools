/*
__ai_context__: LCLLink Native Helper 主入口。
程序启动流程：
  1. 启动 HTTP API 服务器（127.0.0.1:19527）
  2. 启动 Native Messaging 监听循环（stdin/stdout）
  3. 当 NM 连接断开后，延迟关闭机制开始计时
  4. 如果 30 秒内无新连接且无活跃实例，进程退出
*/
package main

import (
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/punkcan/lcllink-helper/internal/api"
	"github.com/punkcan/lcllink-helper/internal/manager"
	"github.com/punkcan/lcllink-helper/internal/nativemsg"
	"github.com/punkcan/lcllink-helper/internal/types"
)

const (
	// ShutdownDelay NM 断开后延迟关闭时间
	// WHY: 给其他浏览器连接 HTTP API 的时间窗口
	ShutdownDelay = 30 * time.Second
	Version       = "0.1.0"
)

func main() {
	// 配置日志输出到 stderr
	// WHY: stdout 被 NM 协议占用，日志必须走 stderr
	log.SetOutput(os.Stderr)
	log.SetPrefix("[LCLLink Helper] ")
	log.Printf("启动 v%s (PID: %d)", Version, os.Getpid())

	// Step 1: 创建管理器
	mgr := manager.New()

	// Step 2: 启动 HTTP API
	apiServer := api.New(mgr)
	err := apiServer.Start()
	if err != nil {
		log.Fatalf("HTTP API 启动失败: %v", err)
	}

	// Step 3: 监听系统信号
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// Step 4: 启动 NM 监听（阻塞，直到 stdin 关闭）
	nmDone := make(chan struct{})
	go func() {
		nativemsg.ListenLoop(func(msg *types.NativeMessage) interface{} {
			return handleNMMessage(mgr, msg)
		})
		close(nmDone)
	}()

	log.Println("就绪，等待指令...")

	// Step 5: 等待退出信号
	select {
	case sig := <-sigChan:
		log.Printf("收到信号 %v，正在关闭...", sig)
	case <-nmDone:
		log.Println("NM 连接已断开")
		// 延迟关闭：如果还有活跃实例，等一会儿再退出
		if mgr.InstanceCount() > 0 {
			log.Printf("还有 %d 个活跃实例，延迟 %v 后关闭", mgr.InstanceCount(), ShutdownDelay)
			time.Sleep(ShutdownDelay)
		}
	}

	// Step 6: 清理
	log.Println("正在停止所有实例...")
	mgr.ShutdownAll()
	apiServer.Stop()
	log.Println("已退出")
}

// handleNMMessage 处理来自 Chrome 的 NM 消息
func handleNMMessage(mgr *manager.Manager, msg *types.NativeMessage) interface{} {
	switch msg.Action {
	case types.NMActionPing:
		return map[string]interface{}{
			"action": "pong",
			"version": Version,
		}

	case types.NMActionGetStatus:
		status := mgr.GetStatus()
		return map[string]interface{}{
			"action": "status",
			"data":   status,
		}

	case types.NMActionShutdown:
		log.Println("收到关闭指令")
		go func() {
			time.Sleep(100 * time.Millisecond)
			os.Exit(0)
		}()
		return map[string]string{"action": "bye"}

	default:
		return map[string]string{
			"action": "error",
			"error":  "未知 action: " + msg.Action,
		}
	}
}

/*
[For Future AI]
1. Key assumptions:
   - 日志输出到 stderr（stdout 被 NM 占用）
   - NM 作为启动触发器和简单控制通道
   - 复杂操作（connect/disconnect）通过 HTTP API 完成
   - 进程生命周期：NM 启动 → NM 断开 → 延迟退出
2. Potential edge cases:
   - 多个 Chrome Profile 同时连接 NM 的情况（只有第一个能连）
   - signal 处理和 NM 断开的竞选条件
   - 延迟退出期间新浏览器可能通过 HTTP API 创建实例
3. Dependencies: manager, api, nativemsg, types
*/
