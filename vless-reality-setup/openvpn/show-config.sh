#!/bin/bash
#===============================================================================
# OpenVPN 配置查看脚本
# OpenVPN 没有分享链接，显示连接信息和 .ovpn 文件路径
#===============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

CLIENT_CONFIG_FILE="/etc/openvpn/client-config.txt"
OVPN_FILE="/etc/openvpn/clients/client1.ovpn"

show_help() {
    echo -e "${CYAN}OpenVPN 配置查看工具${NC}"
    echo ""; echo "用法: $0 [选项]"; echo ""
    echo "  -c, --config    显示完整配置信息"
    echo "  -f, --file      显示 .ovpn 文件路径"
    echo "  -h, --help      帮助"; echo ""
}

check_config() {
    [[ ! -f "$CLIENT_CONFIG_FILE" ]] && { echo -e "${RED}[ERROR]${NC} 未找到: $CLIENT_CONFIG_FILE"; echo -e "${YELLOW}请先运行 install.sh${NC}"; exit 1; }
}

main() {
    check_config
    case "${1:-}" in
        -c|--config) cat "$CLIENT_CONFIG_FILE" ;;
        -f|--file)
            if [[ -f "$OVPN_FILE" ]]; then
                echo -e "${CYAN}.ovpn 文件路径:${NC} ${OVPN_FILE}"
                echo -e "${CYAN}下载命令:${NC} scp root@\$(curl -s4 ifconfig.me):${OVPN_FILE} ./client1.ovpn"
            else
                echo -e "${RED}未找到 .ovpn 文件${NC}"
            fi
            ;;
        -h|--help)   show_help ;;
        "")          cat "$CLIENT_CONFIG_FILE" ;;
        *)           echo -e "${RED}未知选项: $1${NC}"; show_help; exit 1 ;;
    esac
}
main "$@"
