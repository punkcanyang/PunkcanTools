#!/bin/bash
#===============================================================================
# WireGuard 配置查看脚本
# WireGuard 没有分享链接格式，直接显示 .conf 配置文件和二维码
#===============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

CLIENT_CONFIG_FILE="/etc/wireguard/client-config.txt"
CLIENT_CONF_FILE="/etc/wireguard/clients/client1.conf"

show_help() {
    echo -e "${CYAN}WireGuard 配置查看工具${NC}"
    echo ""; echo "用法: $0 [选项]"; echo ""
    echo "  -q, --qr        显示二维码 (手机导入)"
    echo "  -c, --config    显示完整配置信息"
    echo "  -f, --file      显示客户端 .conf 文件内容"
    echo "  -h, --help      帮助"; echo ""
}

check_config() {
    [[ ! -f "$CLIENT_CONFIG_FILE" ]] && { echo -e "${RED}[ERROR]${NC} 未找到: $CLIENT_CONFIG_FILE"; echo -e "${YELLOW}请先运行 install.sh${NC}"; exit 1; }
}

show_qr() {
    if ! command -v qrencode &> /dev/null; then echo -e "${YELLOW}qrencode 未安装${NC}"; return; fi
    if [[ -f "$CLIENT_CONF_FILE" ]]; then
        echo -e "${CYAN}扫码导入 WireGuard 配置:${NC}"; echo ""
        qrencode -t ANSIUTF8 < "$CLIENT_CONF_FILE"
    else
        echo -e "${RED}未找到客户端配置文件${NC}"
    fi
}

main() {
    check_config
    case "${1:-}" in
        -q|--qr)     show_qr ;;
        -c|--config) cat "$CLIENT_CONFIG_FILE" ;;
        -f|--file)   [[ -f "$CLIENT_CONF_FILE" ]] && cat "$CLIENT_CONF_FILE" || echo -e "${RED}未找到 .conf${NC}" ;;
        -h|--help)   show_help ;;
        "")          cat "$CLIENT_CONFIG_FILE"; echo ""; show_qr ;;
        *)           echo -e "${RED}未知选项: $1${NC}"; show_help; exit 1 ;;
    esac
}
main "$@"
