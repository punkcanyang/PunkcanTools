#!/bin/bash

#===============================================================================
# Trojan 一键安装脚本 (基于 Xray-core)
# 适用于 Debian/Ubuntu 系统
#
# __ai_context__:
#   使用 Xray-core 实现 Trojan 协议。Trojan 伪装为正常 HTTPS 流量，
#   使用自签证书提供 TLS 加密。
#
# 功能：
#   - 安装 Xray-core
#   - 配置 Trojan + TLS
#   - 生成 trojan:// 分享链接
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
CERT_DIR="${XRAY_CONFIG_DIR}/certs"
CLIENT_CONFIG_FILE="${XRAY_CONFIG_DIR}/client-config.txt"
SHARE_LINK_FILE="${XRAY_CONFIG_DIR}/trojan-link.txt"

PORT=443
PASSWORD=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║       Trojan 一键安装脚本 (Xray) for Debian/Ubuntu            ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    [[ $EUID -ne 0 ]] && { log_error "需要 root 权限"; exit 1; }
    log_success "Root 权限检查通过"
}

check_system() {
    source /etc/os-release 2>/dev/null || { log_error "无法检测系统"; exit 1; }
    if [[ "$ID" != "debian" && "$ID" != "ubuntu" ]]; then
        log_warn "当前系统: $ID"
        read -p "继续？(y/N): " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 1
    fi
    log_success "系统: $PRETTY_NAME"
}

check_port() {
    if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
        PORT=8443
        log_warn "443 被占用，使用 ${PORT}"
    fi
    log_success "端口: ${PORT}"
}

install_dependencies() {
    log_info "安装依赖..."
    apt-get update > /dev/null 2>&1
    apt-get install -y curl wget unzip jq openssl cron qrencode > /dev/null 2>&1
    log_success "完成"
}

install_xray() {
    log_info "安装 Xray-core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    [[ ! -f /usr/local/bin/xray ]] && { log_error "Xray 安装失败"; exit 1; }
    log_success "Xray 安装完成"
}

generate_cert() {
    log_info "生成自签证书..."
    mkdir -p "$CERT_DIR"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "${CERT_DIR}/server.key" \
        -out "${CERT_DIR}/server.crt" \
        -subj "/CN=www.microsoft.com" \
        -days 3650 2>/dev/null
    chmod 644 "${CERT_DIR}/server.crt"
    chmod 600 "${CERT_DIR}/server.key"
    log_success "证书生成完成"
}

generate_config() {
    log_info "生成配置..."
    mkdir -p "$XRAY_CONFIG_DIR"

    # Trojan 使用密码认证
    PASSWORD=$(openssl rand -base64 24)

    cat > "$XRAY_CONFIG_FILE" << EOF
{
    "log": {
        "loglevel": "warning",
        "access": "/var/log/xray/access.log",
        "error": "/var/log/xray/error.log"
    },
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": ${PORT},
            "protocol": "trojan",
            "settings": {
                "clients": [
                    {
                        "password": "${PASSWORD}",
                        "level": 0
                    }
                ],
                "fallbacks": [
                    {
                        "dest": "www.microsoft.com:443"
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "certificates": [
                        {
                            "certificateFile": "${CERT_DIR}/server.crt",
                            "keyFile": "${CERT_DIR}/server.key"
                        }
                    ]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        }
    ],
    "outbounds": [
        {"protocol": "freedom", "tag": "direct"},
        {"protocol": "blackhole", "tag": "block"}
    ]
}
EOF

    mkdir -p /var/log/xray
    log_success "配置完成"
}

configure_service() {
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray
    sleep 2
    if systemctl is-active --quiet xray; then
        log_success "Xray 服务启动成功"
    else
        log_error "启动失败"
        exit 1
    fi
}

configure_firewall() {
    if command -v ufw &> /dev/null; then
        ufw allow ${PORT}/tcp > /dev/null 2>&1 || true
    elif command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
    fi
    log_success "防火墙已配置"
}

enable_bbr() {
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        return
    fi
    local major=$(uname -r | cut -d. -f1)
    local minor=$(uname -r | cut -d. -f2)
    if [[ "$major" -ge 5 ]] || [[ "$major" -eq 4 && "$minor" -ge 9 ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p > /dev/null 2>&1
    fi
}

generate_client_config() {
    log_info "生成客户端配置..."

    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")

    # Trojan 分享链接
    local encoded_password
    encoded_password=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${PASSWORD}'))" 2>/dev/null || echo "${PASSWORD}")
    local share_link="trojan://${encoded_password}@${server_ip}:${PORT}?security=tls&type=tcp&sni=www.microsoft.com&allowInsecure=1#Trojan"

    echo -n "$share_link" > "$SHARE_LINK_FILE"

    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                        Trojan 客户端配置 (Xray)
═══════════════════════════════════════════════════════════════════════════════

服务器地址: ${server_ip}
端口: ${PORT}
密码: ${PASSWORD}
传输协议: tcp
安全类型: TLS (自签证书)

───────────────────────────────────────────────────────────────────────────────
                              分享链接
───────────────────────────────────────────────────────────────────────────────

${share_link}

───────────────────────────────────────────────────────────────────────────────
                              重要提示
───────────────────────────────────────────────────────────────────────────────

1. 自签证书，客户端需开启 "允许不安全连接"
2. 推荐客户端: V2rayN, Clash, Shadowrocket
3. 服务状态: systemctl status xray
4. 卸载: bash $(dirname "$0")/uninstall.sh

═══════════════════════════════════════════════════════════════════════════════
EOF

    log_success "配置已保存"

    if command -v qrencode &> /dev/null; then
        echo ""
        qrencode -t ANSIUTF8 "$share_link"
    fi
}

main() {
    print_banner
    echo ""
    check_root
    check_system
    check_port
    echo ""
    install_dependencies
    install_xray
    echo ""
    generate_cert
    generate_config
    echo ""
    configure_service
    configure_firewall
    enable_bbr
    echo ""
    generate_client_config
    echo ""
    echo -e "${GREEN}════════ 安装完成！════════${NC}"
    echo ""
    cat "$CLIENT_CONFIG_FILE"
}

main "$@"

# [For Future AI]
# 1. Trojan 使用密码认证（非 UUID）
# 2. 基于 Xray-core 实现，共享安装逻辑
# 3. fallback 到 www.microsoft.com 作为伪装
# 4. 自签证书需客户端设置 allowInsecure
