#!/bin/bash

# Preserve SSH access before installer scripts open or enable firewall rules.

if ! declare -f log_info >/dev/null; then
    log_info() { echo "[INFO] $1"; }
fi

detect_ssh_ports() {
    {
        if [[ -n "${SSH_CONNECTION:-}" ]]; then
            echo "$SSH_CONNECTION" | awk '{print $4}'
        fi

        if command -v sshd > /dev/null 2>&1; then
            sshd -T 2>/dev/null | awk '$1 == "port" {print $2}'
        fi

        if [[ -f /etc/ssh/sshd_config ]]; then
            awk 'tolower($1) == "port" && $2 ~ /^[0-9]+$/ {print $2}' /etc/ssh/sshd_config
        fi

        echo 22
    } | awk '/^[0-9]+$/ && $1 > 0 && $1 <= 65535 {print $1}' | sort -n -u
}

ensure_ssh_ufw_rules() {
    local ssh_ports
    local ssh_port

    ssh_ports=$(detect_ssh_ports)
    while IFS= read -r ssh_port; do
        if [[ -n "$ssh_port" ]]; then
            ufw allow "${ssh_port}/tcp" > /dev/null 2>&1 || true
            log_info "已确保 UFW 允许 SSH 端口 ${ssh_port}/tcp"
        fi
    done <<< "$ssh_ports"
}

ensure_ssh_firewalld_rules() {
    local ssh_ports
    local ssh_port

    ssh_ports=$(detect_ssh_ports)
    while IFS= read -r ssh_port; do
        if [[ -n "$ssh_port" ]]; then
            firewall-cmd --permanent --add-port="${ssh_port}/tcp" > /dev/null 2>&1 || true
            log_info "已确保 firewalld 允许 SSH 端口 ${ssh_port}/tcp"
        fi
    done <<< "$ssh_ports"
}

ensure_ssh_iptables_rules() {
    local ssh_ports
    local ssh_port

    ssh_ports=$(detect_ssh_ports)
    while IFS= read -r ssh_port; do
        if [[ -n "$ssh_port" ]]; then
            iptables -C INPUT -p tcp --dport "$ssh_port" -j ACCEPT 2>/dev/null || \
                iptables -I INPUT -p tcp --dport "$ssh_port" -j ACCEPT
            log_info "已确保 iptables 允许 SSH 端口 ${ssh_port}/tcp"
        fi
    done <<< "$ssh_ports"
}
