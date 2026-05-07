#!/bin/bash
#===============================================================================
# VLESS + WebSocket + TLS 卸载脚本 (CentOS/RHEL)
#===============================================================================
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
VRS_PROTOCOL_ID="vless-ws"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../lib/xray-protocol-guard.sh"

main() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║     VLESS + WebSocket + TLS 卸载脚本 (CentOS/RHEL)            ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    parse_xray_uninstall_args "$@"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}需要 root 权限${NC}"; exit 1; }
    echo -e "${YELLOW}警告: 将完全卸载 Xray${NC}"
    read -p "确认？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0
    check_xray_uninstall_ownership

    systemctl stop xray 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge 2>/dev/null || {
        rm -f /usr/local/bin/xray; rm -rf /usr/local/etc/xray; rm -rf /usr/local/share/xray
        rm -f /etc/systemd/system/xray.service; systemctl daemon-reload
    }
    rm -rf /var/log/xray
    log_success "已卸载"

    echo ""
    echo -e "${GREEN}[INFO]${NC} 防火墙清理: firewall-cmd --permanent --remove-port=443/tcp && firewall-cmd --reload"
    echo -e "\n${GREEN}════════ 卸载完成！════════${NC}"
}
main "$@"
