#!/bin/bash

#===============================================================================
# OpenVPN 卸载脚本
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
    echo "║              OpenVPN 卸载脚本                                  ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    [[ $EUID -ne 0 ]] && { echo -e "${RED}需要 root 权限${NC}"; exit 1; }

    echo -e "${YELLOW}警告: 将完全卸载 OpenVPN 和所有证书${NC}"
    read -p "确认？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0

    # 停止服务
    systemctl stop openvpn@server 2>/dev/null || true
    systemctl disable openvpn@server 2>/dev/null || true
    log_success "服务已停止"

    # 清理 NAT 规则
    local main_interface
    main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o "${main_interface}" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i tun0 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -o tun0 -j ACCEPT 2>/dev/null || true

    # 卸载包
    apt-get remove -y openvpn easy-rsa > /dev/null 2>&1 || true
    log_success "OpenVPN 已卸载"

    # 清理配置
    rm -rf /etc/openvpn
    rm -rf /var/log/openvpn
    log_success "配置和日志已清理"

    echo ""
    echo -e "${GREEN}════════ 卸载完成！════════${NC}"
}

main "$@"
