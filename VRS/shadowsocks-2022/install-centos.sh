#!/bin/bash
#===============================================================================
# Shadowsocks 2022 一键安装脚本 (CentOS/RHEL 版本)
#===============================================================================
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
CLIENT_CONFIG_FILE="${XRAY_CONFIG_DIR}/client-config.txt"
SHARE_LINK_FILE="${XRAY_CONFIG_DIR}/ss2022-link.txt"
VRS_PROTOCOL_ID="shadowsocks-2022"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../lib/xray-protocol-guard.sh"
source "${SCRIPT_DIR}/../lib/firewall-ssh-guard.sh"
PORT=8388; METHOD="2022-blake3-aes-128-gcm"; PASSWORD=""; PKG_MANAGER=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }; log_error() { echo -e "${RED}[ERROR]${NC} $1"; }; log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║     Shadowsocks 2022 安装脚本 for CentOS/RHEL                ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() { [[ $EUID -ne 0 ]] && { log_error "需要 root 权限"; exit 1; }; log_success "Root OK"; }
check_system() {
    source /etc/os-release 2>/dev/null; command -v dnf &> /dev/null && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
    log_success "系统: $PRETTY_NAME ($PKG_MANAGER)"
}
check_port() { ss -tlnp 2>/dev/null | grep -q ":${PORT} " && PORT=18388; log_success "端口: ${PORT}"; }

install_dependencies() {
    $PKG_MANAGER install -y epel-release > /dev/null 2>&1 || true
    $PKG_MANAGER install -y curl wget unzip jq openssl cronie qrencode > /dev/null 2>&1
    log_success "依赖安装完成"
}

install_xray() {
    log_info "安装 Xray-core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    [[ ! -f /usr/local/bin/xray ]] && { log_error "安装失败"; exit 1; }
    log_success "Xray 安装完成"
}

generate_config() {
    mkdir -p "$XRAY_CONFIG_DIR"; PASSWORD=$(openssl rand -base64 16)
    cat > "$XRAY_CONFIG_FILE" << EOF
{
    "log": {"loglevel": "warning"},
    "inbounds": [{
        "listen": "0.0.0.0", "port": ${PORT}, "protocol": "shadowsocks",
        "settings": {"method": "${METHOD}", "password": "${PASSWORD}", "network": "tcp,udp"},
        "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    }],
    "outbounds": [{"protocol": "freedom", "tag": "direct"}, {"protocol": "blackhole", "tag": "block"}]
}
EOF
    chmod 600 "$XRAY_CONFIG_FILE"
    log_success "配置完成"
}

configure_service() {
    systemctl daemon-reload; systemctl enable xray; systemctl restart xray; sleep 2
    systemctl is-active --quiet xray && log_success "Xray (SS-2022) 启动成功" || { log_error "启动失败"; exit 1; }
}

configure_firewall() {
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        ensure_ssh_firewalld_rules
        firewall-cmd --permanent --add-port=${PORT}/tcp --add-port=${PORT}/udp > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        log_success "firewalld 已开放 ${PORT}，SSH 端口已保留"
    elif command -v iptables &> /dev/null; then
        ensure_ssh_iptables_rules
        iptables -C INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null || \
            iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
        iptables -C INPUT -p udp --dport ${PORT} -j ACCEPT 2>/dev/null || \
            iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT
        log_success "iptables 已开放 ${PORT}，SSH 端口已保留"
    fi
}

enable_bbr() {
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then return; fi
    local major=$(uname -r | cut -d. -f1)
    if [[ "$major" -ge 4 ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf; echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p > /dev/null 2>&1
    fi
}

generate_client_config() {
    local server_ip; server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")
    local user_info; user_info=$(echo -n "${METHOD}:${PASSWORD}" | base64 -w 0 2>/dev/null || echo -n "${METHOD}:${PASSWORD}" | base64)
    local share_link="ss://${user_info}@${server_ip}:${PORT}#SS-2022"
    echo -n "$share_link" > "$SHARE_LINK_FILE"
    chmod 600 "$SHARE_LINK_FILE"

    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                  Shadowsocks 2022 客户端配置 (CentOS)
═══════════════════════════════════════════════════════════════════════════════
服务器: ${server_ip}:${PORT} | 加密: ${METHOD} | Key: ${PASSWORD}

Clash Meta:
- name: "SS-2022"
  type: ss
  server: ${server_ip}
  port: ${PORT}
  cipher: ${METHOD}
  password: "${PASSWORD}"
  udp: true

分享链接: ${share_link}
卸载: bash $(dirname "$0")/uninstall-centos.sh
═══════════════════════════════════════════════════════════════════════════════
EOF
    chmod 600 "$CLIENT_CONFIG_FILE"
    log_success "配置已保存"
    command -v qrencode &> /dev/null && { echo ""; qrencode -t ANSIUTF8 "$share_link"; }
}

main() {
    print_banner; echo ""; parse_xray_guard_args "$@"
    check_root; check_system; check_xray_config_ownership; check_port; echo ""
    install_dependencies; install_xray; echo ""; generate_config; write_xray_protocol_marker; echo ""
    configure_service; configure_firewall; enable_bbr; echo ""
    generate_client_config
    echo -e "\n${GREEN}════════ 安装完成！════════${NC}\n"
    cat "$CLIENT_CONFIG_FILE"
}
main "$@"
