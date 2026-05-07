#!/bin/bash
#===============================================================================
# WireGuard 卸载脚本 (CentOS/RHEL)
#===============================================================================
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
PKG_MANAGER=""

main() {
    echo -e "${CYAN}╔══════════════════════════════════════════════╗"
    echo "║      WireGuard 卸载脚本 (CentOS/RHEL)         ║"
    echo -e "╚══════════════════════════════════════════════╝${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}需要 root 权限${NC}"; exit 1; }
    command -v dnf &> /dev/null && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
    echo -e "${YELLOW}警告: 将完全卸载 WireGuard${NC}"
    read -p "确认？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0

    systemctl stop wg-quick@wg0 2>/dev/null || true
    systemctl disable wg-quick@wg0 2>/dev/null || true
    log_success "服务已停止"

    $PKG_MANAGER remove -y wireguard-tools > /dev/null 2>&1 || true
    rm -rf /etc/wireguard
    log_success "WireGuard 已卸载"
    echo -e "\n${GREEN}════════ 卸载完成！════════${NC}"
}
main "$@"
