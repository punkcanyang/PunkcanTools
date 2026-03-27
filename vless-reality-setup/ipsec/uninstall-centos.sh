#!/bin/bash
#===============================================================================
# IPsec/L2TP 卸载脚本 (CentOS/RHEL)
#===============================================================================
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
PKG_MANAGER=""

main() {
    echo -e "${CYAN}╔══════════════════════════════════════════════╗"
    echo "║   IPsec/L2TP 卸载脚本 (CentOS/RHEL)          ║"
    echo -e "╚══════════════════════════════════════════════╝${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}需要 root 权限${NC}"; exit 1; }
    command -v dnf &> /dev/null && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
    echo -e "${YELLOW}警告: 将完全卸载 IPsec/L2TP${NC}"
    read -p "确认？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0

    ipsec stop 2>/dev/null || true
    systemctl stop strongswan 2>/dev/null || true
    systemctl stop xl2tpd 2>/dev/null || true
    systemctl disable strongswan 2>/dev/null || true
    systemctl disable xl2tpd 2>/dev/null || true

    local main_interface; main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    iptables -t nat -D POSTROUTING -s 10.55.55.0/24 -o "${main_interface}" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -s 10.55.55.0/24 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -d 10.55.55.0/24 -j ACCEPT 2>/dev/null || true

    $PKG_MANAGER remove -y strongswan xl2tpd > /dev/null 2>&1 || true
    rm -f /etc/ipsec.conf /etc/ipsec.secrets /etc/ipsec.d/client-config-l2tp.txt
    rm -f /etc/ppp/options.xl2tpd
    log_success "IPsec/L2TP 已卸载"
    echo -e "\n${GREEN}════════ 卸载完成！════════${NC}"
}
main "$@"
