#!/bin/bash

#===============================================================================
# IKEv2 (StrongSwan) 卸载脚本
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

main() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║           IKEv2 (StrongSwan) 卸载脚本                          ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    [[ $EUID -ne 0 ]] && { echo -e "${RED}需要 root 权限${NC}"; exit 1; }

    echo -e "${YELLOW}警告: 将完全卸载 StrongSwan (IKEv2) 和所有证书${NC}"
    read -p "确认？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0

    # 停止服务
    ipsec stop 2>/dev/null || true
    systemctl stop strongswan-starter 2>/dev/null || systemctl stop strongswan 2>/dev/null || true
    systemctl disable strongswan-starter 2>/dev/null || systemctl disable strongswan 2>/dev/null || true
    log_success "服务已停止"

    # 清理 NAT 规则
    local main_interface
    main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    iptables -t nat -D POSTROUTING -s 10.10.10.0/24 -o "${main_interface}" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -s 10.10.10.0/24 -j ACCEPT 2>/dev/null || true

    # 卸载
    apt-get remove -y strongswan strongswan-pki libcharon-extra-plugins > /dev/null 2>&1 || true
    log_success "StrongSwan 已卸载"

    # 清理证书和配置
    rm -rf /etc/ipsec.d/private /etc/ipsec.d/cacerts /etc/ipsec.d/certs /etc/ipsec.d/clients
    rm -f /etc/ipsec.conf /etc/ipsec.secrets
    log_success "证书和配置已清理"

    echo ""
    echo -e "${GREEN}════════ 卸载完成！════════${NC}"
}

main "$@"
