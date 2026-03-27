#!/bin/bash
#===============================================================================
# Shadowsocks (AEAD) 配置查看脚本
#===============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

CLIENT_CONFIG_FILE="/usr/local/etc/xray/client-config.txt"
SHARE_LINK_FILE="/usr/local/etc/xray/ss-link.txt"

show_help() {
    echo -e "${CYAN}Shadowsocks 配置查看工具${NC}"
    echo ""; echo "用法: $0 [选项]"; echo ""
    echo "  -l, --link      仅显示分享链接"
    echo "  -q, --qr        显示二维码"
    echo "  -c, --config    显示完整配置"
    echo "  -h, --help      帮助"; echo ""
}

check_config() {
    [[ ! -f "$CLIENT_CONFIG_FILE" ]] && { echo -e "${RED}[ERROR]${NC} 未找到: $CLIENT_CONFIG_FILE"; echo -e "${YELLOW}请先运行 install.sh${NC}"; exit 1; }
}

show_link() {
    [[ -f "$SHARE_LINK_FILE" ]] && cat "$SHARE_LINK_FILE" || grep "^ss://" "$CLIENT_CONFIG_FILE" 2>/dev/null || echo -e "${RED}未找到链接${NC}"
}

show_qr() {
    if ! command -v qrencode &> /dev/null; then echo -e "${YELLOW}qrencode 未安装${NC}"; show_link; return; fi
    local link; [[ -f "$SHARE_LINK_FILE" ]] && link=$(cat "$SHARE_LINK_FILE") || link=$(grep "^ss://" "$CLIENT_CONFIG_FILE" 2>/dev/null)
    [[ -n "$link" ]] && { echo -e "${CYAN}扫码导入:${NC}"; echo ""; qrencode -t ANSIUTF8 "$link"; echo ""; echo "$link"; } || echo -e "${RED}未找到链接${NC}"
}

main() {
    check_config
    case "${1:-}" in
        -l|--link)   show_link ;;
        -q|--qr)     show_qr ;;
        -c|--config) cat "$CLIENT_CONFIG_FILE" ;;
        -h|--help)   show_help ;;
        "")          cat "$CLIENT_CONFIG_FILE"; echo ""; show_qr ;;
        *)           echo -e "${RED}未知选项: $1${NC}"; show_help; exit 1 ;;
    esac
}
main "$@"
