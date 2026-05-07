#!/bin/bash

#===============================================================================
# TUIC v5 一键安装脚本 (CentOS/RHEL 版本)
#===============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

TUIC_DIR="/etc/tuic"
TUIC_CONFIG="${TUIC_DIR}/config.json"
CERT_DIR="${TUIC_DIR}/certs"
CLIENT_CONFIG_FILE="${TUIC_DIR}/client-config.txt"
SHARE_LINK_FILE="${TUIC_DIR}/tuic-link.txt"
PORT=443
UUID=""
PASSWORD=""
PKG_MANAGER=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║        TUIC v5 一键安装脚本 for CentOS/RHEL                    ║"
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
    if ss -ulnp 2>/dev/null | grep -q ":${PORT} "; then PORT=8443; fi
    log_success "端口: ${PORT}/udp"
}

install_dependencies() {
    log_info "安装依赖..."
    $PKG_MANAGER install -y epel-release > /dev/null 2>&1 || true
    $PKG_MANAGER install -y curl wget openssl qrencode > /dev/null 2>&1
    log_success "完成"
}

install_tuic() {
    log_info "下载 TUIC v5..."
    mkdir -p "$TUIC_DIR"
    local arch
    case "$(uname -m)" in
        x86_64)  arch="x86_64-unknown-linux-gnu" ;;
        aarch64) arch="aarch64-unknown-linux-gnu" ;;
        *)       log_error "不支持的架构"; exit 1 ;;
    esac
    local latest_url
    latest_url=$(curl -sL "https://api.github.com/repos/EAimTY/tuic/releases/latest" \
        | grep "browser_download_url" | grep "tuic-server-.*-${arch}" | head -1 | cut -d '"' -f 4)
    [[ -z "$latest_url" ]] && { log_error "无法获取下载链接"; exit 1; }
    wget -q -O /usr/local/bin/tuic-server "$latest_url"
    chmod +x /usr/local/bin/tuic-server
    log_success "TUIC v5 安装完成"
}

generate_cert() {
    log_info "生成自签证书..."
    mkdir -p "$CERT_DIR"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "${CERT_DIR}/server.key" -out "${CERT_DIR}/server.crt" \
        -subj "/CN=bing.com" -days 3650 2>/dev/null
    chmod 644 "${CERT_DIR}/server.crt"; chmod 600 "${CERT_DIR}/server.key"
    log_success "证书完成"
}

generate_config() {
    log_info "生成配置..."
    UUID=$(cat /proc/sys/kernel/random/uuid)
    PASSWORD=$(openssl rand -base64 16)
    cat > "$TUIC_CONFIG" << EOF
{
    "server": "[::]:${PORT}",
    "users": {"${UUID}": "${PASSWORD}"},
    "certificate": "${CERT_DIR}/server.crt",
    "private_key": "${CERT_DIR}/server.key",
    "congestion_control": "bbr",
    "alpn": ["h3", "spdy/3.1"],
    "udp_relay_ipv6": true,
    "zero_rtt_handshake": false,
    "auth_timeout": "3s",
    "max_idle_time": "10s",
    "max_external_packet_size": 1500,
    "log_level": "warn"
}
EOF
    log_success "配置完成"
}

configure_service() {
    cat > /etc/systemd/system/tuic-server.service << 'EOF'
[Unit]
Description=TUIC v5 Server
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/tuic-server -c /etc/tuic/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable tuic-server; systemctl restart tuic-server
    sleep 2
    systemctl is-active --quiet tuic-server && log_success "TUIC 服务启动成功" || { log_error "启动失败"; exit 1; }
}

configure_firewall() {
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=${PORT}/udp > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        log_success "firewalld 已开放 ${PORT}/udp"
    elif command -v iptables &> /dev/null; then
        iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT
    fi
}

generate_client_config() {
    log_info "生成客户端配置..."
    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")
    local share_link="tuic://${UUID}:${PASSWORD}@${server_ip}:${PORT}?congestion_control=bbr&alpn=h3,spdy/3.1&udp_relay_mode=native&allow_insecure=1#TUIC-v5"
    echo -n "$share_link" > "$SHARE_LINK_FILE"

    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                          TUIC v5 客户端配置
═══════════════════════════════════════════════════════════════════════════════
服务器: ${server_ip}:${PORT} (UDP) | UUID: ${UUID} | 密码: ${PASSWORD}
拥塞控制: bbr | ALPN: h3, spdy/3.1

分享链接: ${share_link}

提示: 确保防火墙开放 ${PORT}/UDP
卸载: bash $(dirname "$0")/uninstall-centos.sh
═══════════════════════════════════════════════════════════════════════════════
EOF
    log_success "配置已保存"
    command -v qrencode &> /dev/null && { echo ""; qrencode -t ANSIUTF8 "$share_link"; }
}

main() {
    print_banner; echo ""
    check_root; check_system; check_port; echo ""
    install_dependencies; install_tuic; echo ""
    generate_cert; generate_config; echo ""
    configure_service; configure_firewall; echo ""
    generate_client_config
    echo -e "\n${GREEN}════════ 安装完成！════════${NC}\n"
    cat "$CLIENT_CONFIG_FILE"
}
main "$@"
