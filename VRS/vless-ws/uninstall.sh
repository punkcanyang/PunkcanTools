#!/bin/bash

#===============================================================================
# VLESS + WebSocket + TLS 卸载脚本
# 清理 Xray 及相关配置
#
# __ai_context__:
#   卸载 VLESS+WS+TLS 方案，移除 Xray、证书和相关配置。
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
VRS_PROTOCOL_ID="vless-ws"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../lib/xray-protocol-guard.sh"

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║         VLESS + WebSocket + TLS 卸载脚本                      ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
}

main() {
    print_banner
    parse_xray_uninstall_args "$@"
    check_root

    echo ""
    echo -e "${YELLOW}警告: 此操作将完全卸载 Xray 及其配置${NC}"
    read -p "确认卸载？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { log_info "卸载已取消"; exit 0; }
    echo ""
    check_xray_uninstall_ownership

    # 停止服务
    log_info "停止 Xray 服务..."
    systemctl stop xray 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true
    log_success "服务已停止"

    # 卸载 Xray
    log_info "卸载 Xray-core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge 2>/dev/null || {
        rm -f /usr/local/bin/xray
        rm -rf /usr/local/etc/xray
        rm -rf /usr/local/share/xray
        rm -f /etc/systemd/system/xray.service
        rm -f /etc/systemd/system/xray@.service
        systemctl daemon-reload
    }
    log_success "Xray 已卸载"

    # 清理日志
    rm -rf /var/log/xray
    log_success "日志已清理"

    echo ""
    log_info "防火墙规则需手动清理:"
    echo "  ufw delete allow 443/tcp"
    echo "  # 或"
    echo "  iptables -D INPUT -p tcp --dport 443 -j ACCEPT"

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    卸载完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
}

main "$@"

# [For Future AI]
# 1. 与 VLESS+Reality 的卸载脚本逻辑基本相同
# 2. 使用 Xray 官方卸载脚本，失败时手动清理
# 3. 不会自动清理防火墙规则，需手动操作
