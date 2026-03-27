#!/bin/bash
# __ai_context__: macOS 安装脚本。
# 编译 Go Helper，复制到固定位置，注册 Chrome NM Host。

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="$HOME/Library/Application Support/LCLLink"
NM_HOST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
NM_HOST_NAME="com.punkcan.lcllink.helper"
BINARY_NAME="lcllink-helper"

echo "╔══════════════════════════════════════════╗"
echo "║   LCLLink Helper 安装脚本 (macOS)       ║"
echo "╚══════════════════════════════════════════╝"
echo

# Step 1: 编译 Go 二进制
echo "➤ 编译 Helper..."
cd "$HELPER_DIR"
go build -o "$BINARY_NAME" .
echo "  ✓ 编译成功"

# Step 2: 创建安装目录
echo "➤ 安装到 $INSTALL_DIR/"
mkdir -p "$INSTALL_DIR"
cp "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
chmod +x "$INSTALL_DIR/$BINARY_NAME"
echo "  ✓ 二进制已复制"

# Step 3: 检查 Chrome 扩展 ID
EXTENSION_ID="${1:-}"
if [ -z "$EXTENSION_ID" ]; then
    echo
    echo "⚠️  请提供 Chrome 扩展 ID（在 chrome://extensions/ 查看）"
    echo "   用法: ./install.sh <EXTENSION_ID>"
    echo
    echo "   暂时使用通配符模式安装..."
    EXTENSION_ID="*"
fi

# Step 4: 生成 NM Host 清单
echo "➤ 注册 Chrome Native Messaging Host..."
mkdir -p "$NM_HOST_DIR"

cat > "$NM_HOST_DIR/$NM_HOST_NAME.json" << EOF
{
  "name": "$NM_HOST_NAME",
  "description": "LCLLink Native Messaging Helper",
  "path": "$INSTALL_DIR/$BINARY_NAME",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXTENSION_ID/"
  ]
}
EOF

echo "  ✓ NM Host 已注册"

# Step 5: 清理编译产物
rm -f "$HELPER_DIR/$BINARY_NAME"

echo
echo "✅ 安装完成！"
echo "   二进制: $INSTALL_DIR/$BINARY_NAME"
echo "   NM Host: $NM_HOST_DIR/$NM_HOST_NAME.json"
echo
echo "📝 下一步："
echo "   1. 在 chrome://extensions/ 找到 LCLLink 的扩展 ID"
echo "   2. 重新运行: ./install.sh <EXTENSION_ID>"
echo "   3. 重启 Chrome"
