#!/bin/bash

#===============================================================================
# VLESS + Reality 卸载脚本 (CentOS/RHEL 版本)
# 清理 Xray 及相关配置
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# 颜色定义
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

#-------------------------------------------------------------------------------
# 工具函数
#-------------------------------------------------------------------------------
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
VRS_PROTOCOL_ID="vless-reality"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/lib/xray-protocol-guard.sh"

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║        VLESS + Reality 卸载脚本 (CentOS/RHEL)                 ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

#-------------------------------------------------------------------------------
# 检查 root 权限
#-------------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# 停止并禁用服务
#-------------------------------------------------------------------------------
stop_service() {
    log_info "停止 Xray 服务..."
    
    if systemctl is-active --quiet xray; then
        systemctl stop xray
        log_success "Xray 服务已停止"
    else
        log_info "Xray 服务未运行"
    fi
    
    if systemctl is-enabled --quiet xray 2>/dev/null; then
        systemctl disable xray
        log_success "Xray 服务已禁用"
    fi
}

#-------------------------------------------------------------------------------
# 卸载 Xray
#-------------------------------------------------------------------------------
uninstall_xray() {
    log_info "卸载 Xray-core..."
    
    if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge 2>/dev/null; then
        log_success "Xray-core 已卸载"
    else
        log_warn "官方卸载脚本失败，尝试手动清理..."
        
        rm -f /usr/local/bin/xray
        rm -rf /usr/local/etc/xray
        rm -rf /usr/local/share/xray
        rm -f /etc/systemd/system/xray.service
        rm -f /etc/systemd/system/xray@.service
        
        systemctl daemon-reload
        
        log_success "手动清理完成"
    fi
}

#-------------------------------------------------------------------------------
# 清理日志
#-------------------------------------------------------------------------------
cleanup_logs() {
    log_info "清理日志文件..."
    
    rm -rf /var/log/xray
    
    log_success "日志文件已清理"
}

#-------------------------------------------------------------------------------
# 移除定时任务
#-------------------------------------------------------------------------------
remove_cron() {
    log_info "移除定时任务..."
    
    crontab -l 2>/dev/null | grep -v "xray-health-check" | crontab - 2>/dev/null || true
    rm -f /usr/local/bin/xray-health-check.sh
    rm -f /usr/local/bin/xray-show-config
    rm -f /usr/local/bin/xray-uninstall.sh
    
    log_success "定时任务和管理脚本已移除"
}

#-------------------------------------------------------------------------------
# 清理防火墙规则 (可选)
#-------------------------------------------------------------------------------
cleanup_firewall() {
    log_info "提示: 防火墙规则需要手动清理"
    
    echo ""
    echo -e "${YELLOW}如果使用 firewalld:${NC}"
    echo "  firewall-cmd --permanent --remove-port=443/tcp"
    echo "  firewall-cmd --reload"
    echo ""
    echo -e "${YELLOW}如果使用 iptables:${NC}"
    echo "  iptables -D INPUT -p tcp --dport 443 -j ACCEPT"
    echo "  service iptables save"
    echo ""
}

#-------------------------------------------------------------------------------
# 清理 BBR 配置 (可选)
#-------------------------------------------------------------------------------
cleanup_bbr() {
    log_info "提示: BBR 配置保留使用"
    echo "  如需移除，请手动编辑 /etc/sysctl.conf"
    echo ""
}

#-------------------------------------------------------------------------------
# 主函数
#-------------------------------------------------------------------------------
main() {
    print_banner
    parse_xray_uninstall_args "$@"
    
    check_root
    
    echo ""
    echo -e "${YELLOW}警告: 此操作将完全卸载 Xray 及其配置${NC}"
    read -p "确认卸载？(y/N): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "卸载已取消"
        exit 0
    fi
    
    echo ""
    check_xray_uninstall_ownership
    
    stop_service
    remove_cron
    uninstall_xray
    cleanup_logs
    
    echo ""
    
    cleanup_firewall
    cleanup_bbr
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    卸载完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# 执行主函数
main "$@"
