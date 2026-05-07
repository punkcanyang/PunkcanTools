#!/bin/bash

#===============================================================================
# Hysteria 2 一键安装脚本 (CentOS/RHEL 版本)
#===============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

HYSTERIA_DIR="/etc/hysteria"
HYSTERIA_CONFIG="${HYSTERIA_DIR}/config.yaml"
CERT_DIR="${HYSTERIA_DIR}/certs"
CLIENT_CONFIG_FILE="${HYSTERIA_DIR}/client-config.txt"
SHARE_LINK_FILE="${HYSTERIA_DIR}/hysteria2-link.txt"
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
    echo "║       Hysteria 2 一键安装脚本 for CentOS/RHEL                  ║"
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

install_hysteria() {
    log_info "安装 Hysteria 2..."
    bash <(curl -fsSL https://get.hy2.sh/)
    [[ ! -f /usr/local/bin/hysteria ]] && { log_error "安装失败"; exit 1; }
    log_success "Hysteria 2 安装完成"
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
    mkdir -p "$HYSTERIA_DIR"
    PASSWORD=$(openssl rand -base64 32)
    cat > "$HYSTERIA_CONFIG" << EOF
listen: :${PORT}
tls:
  cert: ${CERT_DIR}/server.crt
  key: ${CERT_DIR}/server.key
auth:
  type: password
  password: "${PASSWORD}"
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOF
    log_success "配置完成"
}

configure_service() {
    cat > /etc/systemd/system/hysteria-server.service << 'EOF'
[Unit]
Description=Hysteria 2 Server
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable hysteria-server; systemctl restart hysteria-server
    sleep 2
    systemctl is-active --quiet hysteria-server && log_success "服务启动成功" || { log_error "启动失败"; exit 1; }
}

configure_firewall() {
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=${PORT}/udp > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        log_success "firewalld 已开放 ${PORT}/udp"
    elif command -v iptables &> /dev/null; then
        iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT
        log_success "iptables 已开放"
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
    local share_link="hysteria2://${encoded_password}@${server_ip}:${PORT}?insecure=1&sni=bing.com#Hysteria2"
    echo -n "$share_link" > "$SHARE_LINK_FILE"

    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                        Hysteria 2 客户端配置
═══════════════════════════════════════════════════════════════════════════════
服务器: ${server_ip}:${PORT} (UDP)
密码: ${PASSWORD}
SNI: bing.com | 跳过证书验证: 是

分享链接: ${share_link}

Clash Meta:
- name: "Hysteria2"
  type: hysteria2
  server: ${server_ip}
  port: ${PORT}
  password: "${PASSWORD}"
  sni: bing.com
  skip-cert-verify: true

提示: 确保防火墙开放 ${PORT}/UDP
服务状态: systemctl status hysteria-server
卸载: bash $(dirname "$0")/uninstall-centos.sh
═══════════════════════════════════════════════════════════════════════════════
EOF
    log_success "配置已保存"
    command -v qrencode &> /dev/null && { echo ""; qrencode -t ANSIUTF8 "$share_link"; }
}

main() {
    print_banner; echo ""
    check_root; check_system; check_port; echo ""
    install_dependencies; install_hysteria; echo ""
    generate_cert; generate_config; echo ""
    configure_service; configure_firewall; enable_bbr; echo ""
    generate_client_config
    echo -e "\n${GREEN}════════ 安装完成！════════${NC}\n"
    cat "$CLIENT_CONFIG_FILE"
}
main "$@"

# [For Future AI]
# 1. CentOS 版使用 dnf/yum 和 firewalld
# 2. Hysteria 2 官方安装脚本跨平台通用
