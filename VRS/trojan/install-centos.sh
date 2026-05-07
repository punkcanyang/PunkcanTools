#!/bin/bash

#===============================================================================
# Trojan 一键安装脚本 (CentOS/RHEL 版本，基于 Xray-core)
#===============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
CERT_DIR="${XRAY_CONFIG_DIR}/certs"
CLIENT_CONFIG_FILE="${XRAY_CONFIG_DIR}/client-config.txt"
SHARE_LINK_FILE="${XRAY_CONFIG_DIR}/trojan-link.txt"
PORT=443
PASSWORD=""
PKG_MANAGER=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║     Trojan 一键安装脚本 (Xray) for CentOS/RHEL                ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() { [[ $EUID -ne 0 ]] && { log_error "需要 root 权限"; exit 1; }; log_success "Root OK"; }

check_system() {
    source /etc/os-release 2>/dev/null || { log_error "无法检测系统"; exit 1; }
    command -v dnf &> /dev/null && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
    log_success "系统: $PRETTY_NAME ($PKG_MANAGER)"
}

check_port() {
    if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then PORT=8443; fi
    log_success "端口: ${PORT}"
}

install_dependencies() {
    log_info "安装依赖..."
    $PKG_MANAGER install -y epel-release > /dev/null 2>&1 || true
    $PKG_MANAGER install -y curl wget unzip jq openssl cronie qrencode > /dev/null 2>&1
    log_success "完成"
}

install_xray() {
    log_info "安装 Xray-core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    [[ ! -f /usr/local/bin/xray ]] && { log_error "安装失败"; exit 1; }
    log_success "Xray 安装完成"
}

generate_cert() {
    log_info "生成自签证书..."
    mkdir -p "$CERT_DIR"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "${CERT_DIR}/server.key" -out "${CERT_DIR}/server.crt" \
        -subj "/CN=www.microsoft.com" -days 3650 2>/dev/null
    chmod 644 "${CERT_DIR}/server.crt"; chmod 600 "${CERT_DIR}/server.key"
    log_success "证书完成"
}

generate_config() {
    log_info "生成配置..."
    mkdir -p "$XRAY_CONFIG_DIR"
    PASSWORD=$(openssl rand -base64 24)
    cat > "$XRAY_CONFIG_FILE" << EOF
{
    "log": {"loglevel": "warning", "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log"},
    "inbounds": [{
        "listen": "0.0.0.0", "port": ${PORT}, "protocol": "trojan",
        "settings": {
            "clients": [{"password": "${PASSWORD}", "level": 0}],
            "fallbacks": [{"dest": "www.microsoft.com:443"}]
        },
        "streamSettings": {
            "network": "tcp", "security": "tls",
            "tlsSettings": {"certificates": [{"certificateFile": "${CERT_DIR}/server.crt", "keyFile": "${CERT_DIR}/server.key"}]}
        },
        "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    }],
    "outbounds": [{"protocol": "freedom", "tag": "direct"}, {"protocol": "blackhole", "tag": "block"}]
}
EOF
    mkdir -p /var/log/xray
    log_success "配置完成"
}

configure_service() {
    systemctl daemon-reload; systemctl enable xray; systemctl restart xray; sleep 2
    systemctl is-active --quiet xray && log_success "Xray 启动成功" || { log_error "启动失败"; exit 1; }
}

configure_firewall() {
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=${PORT}/tcp > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        log_success "firewalld 已开放 ${PORT}/tcp"
    elif command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
    fi
}

enable_bbr() {
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then return; fi
    local major=$(uname -r | cut -d. -f1)
    if [[ "$major" -ge 4 ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p > /dev/null 2>&1
    fi
}

generate_client_config() {
    log_info "生成客户端配置..."
    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")
    local encoded_password
    encoded_password=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${PASSWORD}'))" 2>/dev/null || echo "${PASSWORD}")
    local share_link="trojan://${encoded_password}@${server_ip}:${PORT}?security=tls&type=tcp&sni=www.microsoft.com&allowInsecure=1#Trojan"
    echo -n "$share_link" > "$SHARE_LINK_FILE"

    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                     Trojan 客户端配置 (Xray, CentOS)
═══════════════════════════════════════════════════════════════════════════════
服务器: ${server_ip}:${PORT} | 密码: ${PASSWORD}
传输: tcp | 安全: TLS (自签证书)

分享链接: ${share_link}

提示: 客户端需开启 allowInsecure
卸载: bash $(dirname "$0")/uninstall-centos.sh
═══════════════════════════════════════════════════════════════════════════════
EOF
    log_success "配置已保存"
    command -v qrencode &> /dev/null && { echo ""; qrencode -t ANSIUTF8 "$share_link"; }
}

main() {
    print_banner; echo ""
    check_root; check_system; check_port; echo ""
    install_dependencies; install_xray; echo ""
    generate_cert; generate_config; echo ""
    configure_service; configure_firewall; enable_bbr; echo ""
    generate_client_config
    echo -e "\n${GREEN}════════ 安装完成！════════${NC}\n"
    cat "$CLIENT_CONFIG_FILE"
}
main "$@"
