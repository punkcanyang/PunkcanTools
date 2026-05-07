#!/bin/bash

#===============================================================================
# WireGuard 卸载脚本
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
    echo "║              WireGuard 卸载脚本                                ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    [[ $EUID -ne 0 ]] && { echo -e "${RED}需要 root 权限${NC}"; exit 1; }

    echo -e "${YELLOW}警告: 将完全卸载 WireGuard${NC}"
    read -p "确认？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0

    # 停止 WireGuard
    systemctl stop wg-quick@wg0 2>/dev/null || true
    systemctl disable wg-quick@wg0 2>/dev/null || true
    log_success "WireGuard 服务已停止"

    # 卸载包
    apt-get remove -y wireguard wireguard-tools > /dev/null 2>&1 || true
    log_success "WireGuard 包已卸载"

    # 清理配置
    rm -rf /etc/wireguard
    log_success "配置已清理"

    # 提示 IP 转发
    echo ""
    log_info "IP 转发设置保留。如需关闭:"
    echo "  编辑 /etc/sysctl.conf 移除 net.ipv4.ip_forward=1"
    echo "  执行 sysctl -p"

    echo ""
    echo -e "${GREEN}════════ 卸载完成！════════${NC}"
}

main "$@"
