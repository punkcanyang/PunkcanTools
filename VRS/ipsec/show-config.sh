#!/bin/bash
#===============================================================================
# IPsec/L2TP 配置查看脚本
#===============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

CLIENT_CONFIG_FILE="/etc/ipsec.d/client-config-l2tp.txt"

show_help() {
    echo -e "${CYAN}IPsec/L2TP 配置查看工具${NC}"
    echo ""; echo "用法: $0 [选项]"; echo ""
    echo "  -c, --config    显示完整配置信息"
    echo "  -h, --help      帮助"; echo ""
}

check_config() {
    [[ ! -f "$CLIENT_CONFIG_FILE" ]] && { echo -e "${RED}[ERROR]${NC} 未找到: $CLIENT_CONFIG_FILE"; echo -e "${YELLOW}请先运行 install.sh${NC}"; exit 1; }
}

main() {
    check_config
    case "${1:-}" in
        -c|--config) cat "$CLIENT_CONFIG_FILE" ;;
        -h|--help)   show_help ;;
        "")          cat "$CLIENT_CONFIG_FILE" ;;
        *)           echo -e "${RED}未知选项: $1${NC}"; show_help; exit 1 ;;
    esac
}
main "$@"
