#!/bin/bash

# Guard shared Xray config ownership for protocol-specific installers.
# Callers must define XRAY_CONFIG_DIR, XRAY_CONFIG_FILE, and VRS_PROTOCOL_ID.

VRS_PROTOCOL_MARKER_FILE="${XRAY_CONFIG_DIR}/vrs-protocol"
ALLOW_REPLACE=false
ALLOW_FORCE_REMOVE=false

if ! declare -f log_warn >/dev/null; then
    log_warn() { echo "[WARN] $1"; }
fi

if ! declare -f log_error >/dev/null; then
    log_error() { echo "[ERROR] $1"; }
fi

print_xray_guard_install_usage() {
    cat <<EOF
Usage: sudo bash $0 [--replace]

Options:
  --replace   Explicitly allow replacing an existing Xray config.
  -h, --help  Show this help.
EOF
}

print_xray_guard_uninstall_usage() {
    cat <<EOF
Usage: sudo bash $0 [--force]

Options:
  --force     Explicitly allow removing Xray even if ownership marker is missing or different.
  -h, --help  Show this help.
EOF
}

parse_xray_guard_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --replace)
                ALLOW_REPLACE=true
                shift
                ;;
            -h|--help)
                print_xray_guard_install_usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                print_xray_guard_install_usage
                exit 1
                ;;
        esac
    done
}

parse_xray_uninstall_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --force)
                ALLOW_FORCE_REMOVE=true
                shift
                ;;
            -h|--help)
                print_xray_guard_uninstall_usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                print_xray_guard_uninstall_usage
                exit 1
                ;;
        esac
    done
}

current_xray_protocol_marker() {
    if [ -f "$VRS_PROTOCOL_MARKER_FILE" ]; then
        head -n1 "$VRS_PROTOCOL_MARKER_FILE" 2>/dev/null || true
    fi
}

check_xray_config_ownership() {
    local existing_protocol

    if [ ! -f "$XRAY_CONFIG_FILE" ]; then
        return
    fi

    existing_protocol=$(current_xray_protocol_marker)

    if [ "$existing_protocol" = "$VRS_PROTOCOL_ID" ]; then
        return
    fi

    if [ "$ALLOW_REPLACE" = true ]; then
        if [ -n "$existing_protocol" ]; then
            log_warn "将替换既有 Xray 配置，原协议: $existing_protocol"
        else
            log_warn "将替换未标记归属的既有 Xray 配置"
        fi
        return
    fi

    if [ -n "$existing_protocol" ]; then
        log_error "检测到既有 Xray 配置属于协议: $existing_protocol"
    else
        log_error "检测到既有 Xray 配置，但没有 VRS 协议归属标记"
    fi
    log_error "为避免覆盖其他协议，已停止安装。确认要替换时请加 --replace。"
    exit 1
}

write_xray_protocol_marker() {
    mkdir -p "$XRAY_CONFIG_DIR"
    printf '%s\n' "$VRS_PROTOCOL_ID" > "$VRS_PROTOCOL_MARKER_FILE"
    chmod 600 "$VRS_PROTOCOL_MARKER_FILE" 2>/dev/null || true
}

check_xray_uninstall_ownership() {
    local existing_protocol

    existing_protocol=$(current_xray_protocol_marker)

    if [ "$existing_protocol" = "$VRS_PROTOCOL_ID" ]; then
        return
    fi

    if [ "$ALLOW_FORCE_REMOVE" = true ]; then
        if [ -n "$existing_protocol" ]; then
            log_warn "强制卸载 Xray，当前标记协议: $existing_protocol"
        else
            log_warn "强制卸载未标记归属的 Xray 配置"
        fi
        return
    fi

    if [ -n "$existing_protocol" ]; then
        log_error "当前 Xray 配置属于协议: $existing_protocol"
    else
        log_error "当前 Xray 配置没有 VRS 协议归属标记"
    fi
    log_error "为避免卸载其他协议，已停止。确认要强制移除时请加 --force。"
    exit 1
}
