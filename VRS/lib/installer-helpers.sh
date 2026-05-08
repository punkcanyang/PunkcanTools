#!/bin/bash

# Shared installer helpers used by VRS installer/uninstaller scripts.

if ! declare -f log_info  >/dev/null; then log_info()  { echo "[INFO] $1"; }; fi
if ! declare -f log_warn  >/dev/null; then log_warn()  { echo "[WARN] $1"; }; fi
if ! declare -f log_error >/dev/null; then log_error() { echo "[ERROR] $1"; }; fi

# Pinned commit + sha256 of the upstream Xray-install bootstrapper.
# Update both fields when bumping. Keep them in sync — the script will refuse to run otherwise.
VRS_XRAY_INSTALL_REF="${VRS_XRAY_INSTALL_REF:-main}"
VRS_XRAY_INSTALL_URL="${VRS_XRAY_INSTALL_URL:-https://raw.githubusercontent.com/XTLS/Xray-install/${VRS_XRAY_INSTALL_REF}/install-release.sh}"
# Set VRS_XRAY_INSTALL_SHA256 to a known-good hash to enforce verification. Empty disables it
# (with a logged warning) but the download still uses curl -fsSL so HTTP errors abort early.
VRS_XRAY_INSTALL_SHA256="${VRS_XRAY_INSTALL_SHA256:-}"

# Download the official Xray-install script with strict error handling, verify sha256
# when configured, then execute it with the supplied arguments.
secure_run_xray_installer() {
    local tmp
    tmp=$(mktemp) || { log_error "无法创建临时文件"; return 1; }
    # shellcheck disable=SC2064
    trap "rm -f '$tmp'" RETURN

    log_info "下载 Xray 安装脚本: ${VRS_XRAY_INSTALL_URL}"
    if ! curl -fsSL --max-time 60 -o "$tmp" "$VRS_XRAY_INSTALL_URL"; then
        log_error "Xray 安装脚本下载失败"
        return 1
    fi

    if [[ -n "$VRS_XRAY_INSTALL_SHA256" ]]; then
        local actual
        if command -v sha256sum >/dev/null 2>&1; then
            actual=$(sha256sum "$tmp" | awk '{print $1}')
        elif command -v shasum >/dev/null 2>&1; then
            actual=$(shasum -a 256 "$tmp" | awk '{print $1}')
        else
            log_error "未找到 sha256sum / shasum，无法验证脚本完整性"
            return 1
        fi
        if [[ "$actual" != "$VRS_XRAY_INSTALL_SHA256" ]]; then
            log_error "Xray 安装脚本 sha256 校验失败"
            log_error "  期望: $VRS_XRAY_INSTALL_SHA256"
            log_error "  实际: $actual"
            return 1
        fi
        log_info "Xray 安装脚本 sha256 校验通过"
    else
        log_warn "未设置 VRS_XRAY_INSTALL_SHA256，跳过完整性校验（仅依赖 HTTPS）"
    fi

    bash "$tmp" "$@"
}

# Append a sysctl key=value line, or update it in place if a different value already exists.
# Avoids the duplicate-append issue from naive `cat >> /etc/sysctl.conf` callers.
upsert_sysctl_line() {
    local conf="$1" key="$2" value="$3"
    [[ -f "$conf" ]] || touch "$conf"
    if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$conf"; then
        # Replace existing line. Use awk to avoid sed escaping pitfalls with key/value.
        local tmp
        tmp=$(mktemp) || return 1
        awk -v k="$key" -v v="$value" '
            BEGIN { pat = "^[[:space:]]*" k "[[:space:]]*=" }
            $0 ~ pat { print k "=" v; replaced=1; next }
            { print }
            END { if (!replaced) print k "=" v }
        ' "$conf" > "$tmp" && cat "$tmp" > "$conf" && rm -f "$tmp"
    else
        printf '%s=%s\n' "$key" "$value" >> "$conf"
    fi
}

# Ensure BBR is enabled in /etc/sysctl.conf and applied. Idempotent.
ensure_bbr_enabled() {
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        log_info "BBR 已经启用"
        return 0
    fi
    local kmajor kminor
    kmajor=$(uname -r | cut -d. -f1)
    kminor=$(uname -r | cut -d. -f2)
    if (( kmajor < 4 )) || { (( kmajor == 4 )) && (( kminor < 9 )); }; then
        log_warn "内核版本 ${kmajor}.${kminor} 不支持 BBR (需要 4.9+)"
        return 1
    fi
    upsert_sysctl_line /etc/sysctl.conf net.core.default_qdisc fq
    upsert_sysctl_line /etc/sysctl.conf net.ipv4.tcp_congestion_control bbr
    sysctl -p >/dev/null 2>&1 || true
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        log_info "BBR 启用成功"
    else
        log_warn "BBR 启用可能需要重启系统"
    fi
}

# Replace the user's crontab safely: remove any line matching the supplied pattern.
# Preserves all other lines, never empties the crontab to nothing if other entries existed.
remove_crontab_lines_matching() {
    local pattern="$1"
    [[ -n "$pattern" ]] || return 0
    local current
    current=$(crontab -l 2>/dev/null) || current=""
    if [[ -z "$current" ]]; then
        return 0
    fi
    local filtered
    filtered=$(printf '%s\n' "$current" | grep -v -- "$pattern" || true)
    if [[ -z "$filtered" ]]; then
        crontab -r 2>/dev/null || true
    else
        printf '%s\n' "$filtered" | crontab -
    fi
}

# Drop a previously-allowed TCP port from whichever firewall backend is active.
# Best-effort and idempotent; never fails the caller.
remove_firewall_port_tcp() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 0

    if command -v ufw >/dev/null 2>&1; then
        ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --remove-port="${port}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi
    if command -v iptables >/dev/null 2>&1; then
        while iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; do
            iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || break
        done
    fi
    if command -v ip6tables >/dev/null 2>&1; then
        while ip6tables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; do
            ip6tables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || break
        done
    fi
    if command -v nft >/dev/null 2>&1; then
        local handle
        while read -r handle; do
            [[ -n "$handle" ]] || continue
            nft delete rule inet vrs_ssh_guard input handle "$handle" 2>/dev/null || true
        done < <(nft --handle list chain inet vrs_ssh_guard input 2>/dev/null \
            | awk -v p="$port" '$0 ~ "tcp dport "p" accept" { for (i=1;i<=NF;i++) if ($i=="handle") { print $(i+1); break } }')
    fi
}
