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
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
VRS_PROTOCOL_ID="vless-reality"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

_resolve_vrs_lib_dir() {
    local candidates=(
        "${VRS_LIB_DIR:-}"
        "${SCRIPT_DIR}/lib"
        "/usr/local/share/vrs/lib"
        "/usr/local/lib/vrs"
    )
    local d
    for d in "${candidates[@]}"; do
        if [[ -n "$d" && -f "$d/xray-protocol-guard.sh" ]]; then
            printf '%s' "$d"
            return 0
        fi
    done
    return 1
}

VRS_LIB_DIR=$(_resolve_vrs_lib_dir) || {
    log_error "未找到 VRS 共享 lib 目录"
    exit 1
}

# shellcheck source=lib/xray-protocol-guard.sh
source "${VRS_LIB_DIR}/xray-protocol-guard.sh"
# shellcheck source=lib/installer-helpers.sh
source "${VRS_LIB_DIR}/installer-helpers.sh"

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║        VLESS + Reality 卸载脚本 (CentOS/RHEL)                 ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
}

read_xray_listen_port() {
    if [[ -f "$XRAY_CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
        jq -r '.inbounds[0].port // empty' "$XRAY_CONFIG_FILE" 2>/dev/null
    elif [[ -f "$XRAY_CONFIG_FILE" ]]; then
        awk -F: '/"port"[[:space:]]*:/ { gsub(/[^0-9]/,"",$2); if ($2!="") {print $2; exit} }' "$XRAY_CONFIG_FILE"
    fi
}

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

uninstall_xray() {
    log_info "卸载 Xray-core..."

    if secure_run_xray_installer @ remove --purge 2>/dev/null; then
        log_success "Xray-core 已卸载"
        return
    fi

    log_warn "官方卸载脚本失败，尝试手动清理..."
    rm -f /usr/local/bin/xray
    rm -rf /usr/local/etc/xray
    rm -rf /usr/local/share/xray
    rm -f /etc/systemd/system/xray.service
    rm -f /etc/systemd/system/xray@.service
    systemctl daemon-reload
    log_success "手动清理完成"
}

cleanup_logs() {
    log_info "清理日志文件..."
    rm -rf /var/log/xray
    log_success "日志文件已清理"
}

remove_cron() {
    log_info "移除定时任务..."
    remove_crontab_lines_matching 'xray-health-check'
    rm -f /usr/local/bin/xray-health-check.sh
    rm -f /usr/local/bin/xray-show-config
    rm -f /usr/local/bin/xray-uninstall.sh
    log_success "定时任务和管理脚本已移除"
}

cleanup_firewall() {
    if [[ -z "$LISTEN_PORT" ]]; then
        log_info "未识别到 Xray 端口，跳过自动防火墙清理"
        return
    fi
    log_info "清理防火墙规则（端口 ${LISTEN_PORT}）..."
    remove_firewall_port_tcp "$LISTEN_PORT"
    log_success "已尝试移除端口 ${LISTEN_PORT} 的防火墙规则"
}

cleanup_bbr() {
    log_info "BBR 内核参数保留使用（如需移除请手动编辑 /etc/sysctl.conf）"
}

main() {
    print_banner
    parse_xray_uninstall_args "$@"

    check_root

    echo ""
    echo -e "${YELLOW}警告: 此操作将完全卸载 Xray 及其配置${NC}"
    read -r -p "确认卸载？(y/N): " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "卸载已取消"
        exit 0
    fi

    echo ""
    check_xray_uninstall_ownership

    LISTEN_PORT=$(read_xray_listen_port || true)

    stop_service
    remove_cron
    cleanup_firewall
    uninstall_xray
    cleanup_logs

    echo ""
    cleanup_bbr

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    卸载完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

main "$@"
