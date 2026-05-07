#!/bin/bash

#===============================================================================
# Trojan-Go 卸载脚本
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

main() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║              Trojan-Go 卸载脚本                                ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    [[ $EUID -ne 0 ]] && { echo -e "${RED}需要 root 权限${NC}"; exit 1; }

    echo -e "${YELLOW}警告: 将完全卸载 Trojan-Go${NC}"
    read -p "确认？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0

    systemctl stop trojan-go 2>/dev/null || true
    systemctl disable trojan-go 2>/dev/null || true
    rm -f /usr/local/bin/trojan-go
    rm -f /etc/systemd/system/trojan-go.service
    rm -rf /etc/trojan-go
    systemctl daemon-reload
    log_success "Trojan-Go 已卸载"

    echo ""
    echo -e "${GREEN}════════ 卸载完成！════════${NC}"
}

main "$@"
