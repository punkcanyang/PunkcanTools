#!/bin/bash

#===============================================================================
# VLESS + Reality 配置查看脚本
# 用于随时查看客户端配置信息
#===============================================================================

#-------------------------------------------------------------------------------
# 颜色定义
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# 配置路径
#-------------------------------------------------------------------------------
XRAY_CONFIG_DIR="/usr/local/etc/xray"
CLIENT_CONFIG_FILE="${XRAY_CONFIG_DIR}/client-config.txt"
VLESS_LINK_FILE="${XRAY_CONFIG_DIR}/vless-link.txt"
QR_CODE_FILE="${XRAY_CONFIG_DIR}/vless-qrcode.png"

#-------------------------------------------------------------------------------
# 显示帮助
#-------------------------------------------------------------------------------
show_help() {
    echo -e "${CYAN}VLESS + Reality 配置查看工具${NC}"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -l, --link      仅显示 VLESS 分享链接"
    echo "  -q, --qr        在终端显示二维码"
    echo "  -c, --config    显示完整配置信息"
    echo "  -p, --path      显示配置文件路径"
    echo "  -h, --help      显示此帮助信息"
    echo ""
    echo "无参数时显示完整配置信息和二维码"
}

#-------------------------------------------------------------------------------
# 检查配置是否存在
#-------------------------------------------------------------------------------
check_config() {
    if [[ ! -f "$CLIENT_CONFIG_FILE" ]]; then
        echo -e "${RED}[ERROR]${NC} 未找到配置文件: $CLIENT_CONFIG_FILE"
        echo -e "${YELLOW}[提示]${NC} 请先运行 install.sh 安装 VLESS + Reality"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# 显示分享链接
#-------------------------------------------------------------------------------
show_link() {
    if [[ -f "$VLESS_LINK_FILE" ]]; then
        cat "$VLESS_LINK_FILE"
    else
        # 从配置文件中提取链接
        grep "^vless://" "$CLIENT_CONFIG_FILE" 2>/dev/null || echo -e "${RED}未找到分享链接${NC}"
    fi
}

#-------------------------------------------------------------------------------
# 显示终端二维码
#-------------------------------------------------------------------------------
show_qr() {
    if ! command -v qrencode &> /dev/null; then
        echo -e "${YELLOW}[提示]${NC} qrencode 未安装，无法显示终端二维码"
        echo -e "${YELLOW}[提示]${NC} 安装命令: apt-get install qrencode"
        echo ""
        echo -e "${CYAN}使用分享链接手动导入:${NC}"
        show_link
        return
    fi
    
    local link
    if [[ -f "$VLESS_LINK_FILE" ]]; then
        link=$(cat "$VLESS_LINK_FILE")
    else
        link=$(grep "^vless://" "$CLIENT_CONFIG_FILE" 2>/dev/null)
    fi
    
    if [[ -n "$link" ]]; then
        echo -e "${CYAN}扫描下方二维码导入配置:${NC}"
        echo ""
        qrencode -t ANSIUTF8 "$link"
        echo ""
        echo -e "${GREEN}─────────────────────────────────────────${NC}"
        echo -e "${CYAN}分享链接:${NC}"
        echo "$link"
    else
        echo -e "${RED}[ERROR]${NC} 未找到 VLESS 分享链接"
    fi
}

#-------------------------------------------------------------------------------
# 显示完整配置
#-------------------------------------------------------------------------------
show_config() {
    cat "$CLIENT_CONFIG_FILE"
}

#-------------------------------------------------------------------------------
# 显示配置文件路径
#-------------------------------------------------------------------------------
show_paths() {
    echo -e "${CYAN}配置文件路径:${NC}"
    echo ""
    echo -e "  完整配置: ${GREEN}${CLIENT_CONFIG_FILE}${NC}"
    echo -e "  分享链接: ${GREEN}${VLESS_LINK_FILE}${NC}"
    echo -e "  二维码图片: ${GREEN}${QR_CODE_FILE}${NC}"
    echo ""
    echo -e "${CYAN}快速命令:${NC}"
    echo ""
    echo -e "  查看链接: ${YELLOW}cat ${VLESS_LINK_FILE}${NC}"
    echo -e "  复制链接到剪贴板 (需要 xclip):"
    echo -e "            ${YELLOW}cat ${VLESS_LINK_FILE} | xclip -selection clipboard${NC}"
    echo -e "  下载配置文件:"
    echo -e "            ${YELLOW}scp root@<server>:${CLIENT_CONFIG_FILE} ./client-config.txt${NC}"
}

#-------------------------------------------------------------------------------
# 主函数
#-------------------------------------------------------------------------------
main() {
    check_config
    
    case "${1:-}" in
        -l|--link)
            show_link
            ;;
        -q|--qr)
            show_qr
            ;;
        -c|--config)
            show_config
            ;;
        -p|--path)
            show_paths
            ;;
        -h|--help)
            show_help
            ;;
        "")
            # 默认：显示配置和二维码
            show_config
            echo ""
            echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
            echo ""
            show_qr
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} 未知选项: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
