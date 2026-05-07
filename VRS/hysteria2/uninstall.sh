#!/bin/bash

#===============================================================================
# Hysteria 2 卸载脚本
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║              Hysteria 2 卸载脚本                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

main() {
    print_banner

    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} 需要 root 权限"
        exit 1
    fi

    echo -e "${YELLOW}警告: 此操作将完全卸载 Hysteria 2${NC}"
    read -p "确认卸载？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { log_info "已取消"; exit 0; }
    echo ""

    # 停止服务
    systemctl stop hysteria-server 2>/dev/null || true
    systemctl disable hysteria-server 2>/dev/null || true
    log_success "服务已停止"

    # 删除文件
    rm -f /usr/local/bin/hysteria
    rm -f /etc/systemd/system/hysteria-server.service
    rm -rf /etc/hysteria
    systemctl daemon-reload
    log_success "Hysteria 2 已卸载"

    echo ""
    log_info "防火墙规则需手动清理:"
    echo "  ufw delete allow 443/udp"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    卸载完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
}

main "$@"

# [For Future AI]
# 1. 清理 hysteria 二进制、配置和 systemd 服务
# 2. 不清理防火墙规则
