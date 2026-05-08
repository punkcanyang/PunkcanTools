#!/bin/bash

# Preserve SSH access before installer scripts open or enable firewall rules.
# Supports: ufw, firewalld, iptables (legacy/nft wrapper), pure nftables, ip6tables.

if ! declare -f log_info >/dev/null; then
    log_info() { echo "[INFO] $1"; }
fi

if ! declare -f log_warn >/dev/null; then
    log_warn() { echo "[WARN] $1"; }
fi

_resolve_sshd_binary() {
    if command -v sshd >/dev/null 2>&1; then
        command -v sshd
        return 0
    fi
    local candidate
    for candidate in /usr/sbin/sshd /sbin/sshd /usr/local/sbin/sshd; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

_parse_sshd_config_ports() {
    local files=(/etc/ssh/sshd_config)
    if compgen -G "/etc/ssh/sshd_config.d/*.conf" >/dev/null 2>&1; then
        local f
        for f in /etc/ssh/sshd_config.d/*.conf; do
            files+=("$f")
        done
    fi
    awk 'tolower($1) == "port" && $2 ~ /^[0-9]+$/ {print $2}' "${files[@]}" 2>/dev/null
}

detect_ssh_ports() {
    {
        if [[ -n "${SSH_CONNECTION:-}" ]]; then
            awk '{print $4}' <<< "$SSH_CONNECTION"
        fi

        local sshd_bin
        if sshd_bin=$(_resolve_sshd_binary); then
            "$sshd_bin" -T 2>/dev/null | awk '$1 == "port" {print $2}'
        fi

        _parse_sshd_config_ports

        echo 22
    } | awk '/^[0-9]+$/ && $1 >= 1 && $1 <= 65535 && !seen[$1]++'
}

ensure_ssh_ufw_rules() {
    local ssh_port
    while IFS= read -r ssh_port; do
        if [[ -n "$ssh_port" ]]; then
            ufw allow "${ssh_port}/tcp" >/dev/null 2>&1 || true
            log_info "已确保 UFW 允许 SSH 端口 ${ssh_port}/tcp"
        fi
    done < <(detect_ssh_ports)
}

ensure_ssh_firewalld_rules() {
    local ssh_port
    while IFS= read -r ssh_port; do
        if [[ -n "$ssh_port" ]]; then
            firewall-cmd --permanent --add-port="${ssh_port}/tcp" >/dev/null 2>&1 || true
            log_info "已确保 firewalld 允许 SSH 端口 ${ssh_port}/tcp"
        fi
    done < <(detect_ssh_ports)
}

ensure_ssh_iptables_rules() {
    local ssh_port
    while IFS= read -r ssh_port; do
        if [[ -n "$ssh_port" ]]; then
            iptables -C INPUT -p tcp --dport "$ssh_port" -j ACCEPT 2>/dev/null || \
                iptables -I INPUT -p tcp --dport "$ssh_port" -j ACCEPT
            log_info "已确保 iptables 允许 SSH 端口 ${ssh_port}/tcp"
            if command -v ip6tables >/dev/null 2>&1; then
                ip6tables -C INPUT -p tcp --dport "$ssh_port" -j ACCEPT 2>/dev/null || \
                    ip6tables -I INPUT -p tcp --dport "$ssh_port" -j ACCEPT 2>/dev/null || true
                log_info "已确保 ip6tables 允许 SSH 端口 ${ssh_port}/tcp"
            fi
        fi
    done < <(detect_ssh_ports)
}

# Ensure SSH ports are allowed in pure nftables (no firewalld, no iptables-nft wrapper).
# Creates an inet table named vrs_ssh_guard with an input chain that accepts SSH ports.
ensure_ssh_nftables_rules() {
    if ! command -v nft >/dev/null 2>&1; then
        return
    fi

    nft list table inet vrs_ssh_guard >/dev/null 2>&1 || \
        nft add table inet vrs_ssh_guard 2>/dev/null || return
    nft list chain inet vrs_ssh_guard input >/dev/null 2>&1 || \
        nft 'add chain inet vrs_ssh_guard input { type filter hook input priority -10 ; policy accept ; }' 2>/dev/null || return

    local ssh_port
    while IFS= read -r ssh_port; do
        if [[ -n "$ssh_port" ]]; then
            if ! nft list chain inet vrs_ssh_guard input 2>/dev/null | grep -q "tcp dport ${ssh_port} accept"; then
                nft add rule inet vrs_ssh_guard input tcp dport "$ssh_port" accept 2>/dev/null || true
            fi
            log_info "已确保 nftables 允许 SSH 端口 ${ssh_port}/tcp"
        fi
    done < <(detect_ssh_ports)
}

# True when nftables is the active firewall backend with no iptables compatibility wrapper
# routing rules to nft (i.e. iptables -L would be empty / nonfunctional).
is_pure_nftables_backend() {
    command -v nft >/dev/null 2>&1 || return 1
    if systemctl is-active --quiet nftables 2>/dev/null; then
        if ! command -v iptables >/dev/null 2>&1; then
            return 0
        fi
        if iptables --version 2>/dev/null | grep -qi 'nf_tables'; then
            return 1
        fi
        return 0
    fi
    return 1
}
