#!/bin/bash
#===============================================================================
# OpenVPN 卸载脚本 (CentOS/RHEL)
#===============================================================================
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
PKG_MANAGER=""

main() {
    echo -e "${CYAN}╔══════════════════════════════════════════════╗"
    echo "║     OpenVPN 卸载脚本 (CentOS/RHEL)            ║"
    echo -e "╚══════════════════════════════════════════════╝${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}需要 root 权限${NC}"; exit 1; }
    command -v dnf &> /dev/null && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
    echo -e "${YELLOW}警告: 将完全卸载 OpenVPN${NC}"
    read -p "确认？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0

    systemctl stop openvpn@server 2>/dev/null || true
    systemctl disable openvpn@server 2>/dev/null || true

    local main_interface; main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o "${main_interface}" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i tun0 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -o tun0 -j ACCEPT 2>/dev/null || true

    $PKG_MANAGER remove -y openvpn easy-rsa > /dev/null 2>&1 || true
    rm -rf /etc/openvpn /var/log/openvpn
    log_success "OpenVPN 已卸载"
    echo -e "\n${GREEN}════════ 卸载完成！════════${NC}"
}
main "$@"
