/*
__ai_context__: Chrome Native Messaging 协议编解码。
Chrome NM 协议使用 stdin/stdout 通信，消息格式为：
  [4字节小端序长度][JSON消息体]
*/
package nativemsg

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"os"

	"github.com/punkcan/lcllink-helper/internal/types"
)

// MaxMessageSize Chrome NM 协议最大消息大小（1MB）
const MaxMessageSize = 1024 * 1024

// ============================================================
// 读取消息
// WHY: Chrome 发给 Helper 的消息需要从 stdin 读取
// ============================================================

// ReadMessage 从 stdin 读取一条 NM 消息
func ReadMessage(reader io.Reader) (*types.NativeMessage, error) {
	// Step 1: 读取 4 字节消息长度（小端序）
	lengthBuf := make([]byte, 4)
	_, err := io.ReadFull(reader, lengthBuf)
	if err != nil {
		return nil, fmt.Errorf("读取消息长度失败: %w", err)
	}

	// Step 2: 解析长度
	messageLength := binary.LittleEndian.Uint32(lengthBuf)

	// Step 3: 校验长度
	if messageLength == 0 {
		return nil, fmt.Errorf("消息长度为 0")
	}
	if messageLength > MaxMessageSize {
		return nil, fmt.Errorf("消息长度超限: %d > %d", messageLength, MaxMessageSize)
	}

	// Step 4: 读取消息体
	messageBuf := make([]byte, messageLength)
	_, err = io.ReadFull(reader, messageBuf)
	if err != nil {
		return nil, fmt.Errorf("读取消息体失败: %w", err)
	}

	// Step 5: 解析 JSON
	var msg types.NativeMessage
	err = json.Unmarshal(messageBuf, &msg)
	if err != nil {
		return nil, fmt.Errorf("JSON 解析失败: %w", err)
	}

	return &msg, nil
}

// ============================================================
// 发送消息
// WHY: Helper 回复给 Chrome 的消息需要写到 stdout
// ============================================================

// WriteMessage 将消息写到 stdout
func WriteMessage(writer io.Writer, msg interface{}) error {
	// Step 1: 序列化为 JSON
	data, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("JSON 序列化失败: %w", err)
	}

	// Step 2: 写入 4 字节长度头（小端序）
	length := uint32(len(data))
	if length > MaxMessageSize {
		return fmt.Errorf("消息过大: %d bytes", length)
	}

	lengthBuf := make([]byte, 4)
	binary.LittleEndian.PutUint32(lengthBuf, length)

	_, err = writer.Write(lengthBuf)
	if err != nil {
		return fmt.Errorf("写入长度头失败: %w", err)
	}

	// Step 3: 写入消息体
	_, err = writer.Write(data)
	if err != nil {
		return fmt.Errorf("写入消息体失败: %w", err)
	}

	return nil
}

// ============================================================
// NM 消息处理循环
// ============================================================

// HandleFunc NM 消息处理回调
type HandleFunc func(msg *types.NativeMessage) interface{}

// ListenLoop 持续监听 stdin 并处理消息
// WHY: Chrome 通过 stdin 发消息，Helper 通过 stdout 回复
func ListenLoop(handler HandleFunc) {
	for {
		msg, err := ReadMessage(os.Stdin)
		if err != nil {
			// WHY: stdin 关闭 = Chrome 关闭了 NM 连接
			// 此时不立即退出，等待延迟关闭逻辑处理
			return
		}

		response := handler(msg)
		if response != nil {
			_ = WriteMessage(os.Stdout, response)
		}
	}
}

/*
[For Future AI]
1. Key assumptions:
   - Chrome NM 使用 小端序 4 字节长度 + JSON 的二进制协议
   - 消息最大 1MB（Chrome 硬限制）
   - stdin 关闭意味着 Chrome 断开连接
2. Potential edge cases:
   - stdin EOF 不一定是错误，可能是正常关闭
   - 并发写 stdout 需要外部加锁（Chrome NM 是单线程的）
3. Dependencies: types 包
*/
