#!/bin/bash

#===============================================================================
# Shadowsocks (传统 AEAD) 一键安装脚本
# 适用于 Debian/Ubuntu 系统
#
# __ai_context__:
#   使用 Xray-core 实现传统 Shadowsocks AEAD 加密。
#   不需要 TLS 证书，配置简单，兼容性好。
#   使用 chacha20-ietf-poly1305 加密方法。
#
# 功能：
#   - 安装 Xray-core + Shadowsocks
#   - 无需证书，配置简洁
#   - 生成 ss:// 分享链接
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
CLIENT_CONFIG_FILE="${XRAY_CONFIG_DIR}/client-config.txt"
SHARE_LINK_FILE="${XRAY_CONFIG_DIR}/ss-link.txt"

PORT=8388
METHOD="chacha20-ietf-poly1305"
PASSWORD=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║     Shadowsocks (AEAD) 一键安装脚本 for Debian/Ubuntu        ║"
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
        PORT=18388
        log_warn "8388 被占用，使用 ${PORT}"
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
    [[ ! -f /usr/local/bin/xray ]] && { log_error "安装失败"; exit 1; }
    log_success "Xray 安装完成"
}

generate_config() {
    log_info "生成配置..."
    mkdir -p "$XRAY_CONFIG_DIR"

    PASSWORD=$(openssl rand -base64 16)

    cat > "$XRAY_CONFIG_FILE" << EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": ${PORT},
            "protocol": "shadowsocks",
            "settings": {
                "method": "${METHOD}",
                "password": "${PASSWORD}",
                "network": "tcp,udp"
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

    log_success "配置完成"
}

configure_service() {
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray
    sleep 2
    if systemctl is-active --quiet xray; then
        log_success "Xray (SS) 服务启动成功"
    else
        log_error "启动失败"
        exit 1
    fi
}

configure_firewall() {
    if command -v ufw &> /dev/null; then
        ufw allow ${PORT}/tcp > /dev/null 2>&1 || true
        ufw allow ${PORT}/udp > /dev/null 2>&1 || true
    elif command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
        iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT
    fi
    log_success "防火墙已配置"
}

enable_bbr() {
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then return; fi
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

    # SS 分享链接格式: ss://BASE64(method:password)@server:port#name
    local user_info
    user_info=$(echo -n "${METHOD}:${PASSWORD}" | base64 -w 0 2>/dev/null || echo -n "${METHOD}:${PASSWORD}" | base64)
    local share_link="ss://${user_info}@${server_ip}:${PORT}#Shadowsocks"

    echo -n "$share_link" > "$SHARE_LINK_FILE"

    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                     Shadowsocks (AEAD) 客户端配置
═══════════════════════════════════════════════════════════════════════════════

服务器地址: ${server_ip}
端口: ${PORT}
加密方式: ${METHOD}
密码: ${PASSWORD}

───────────────────────────────────────────────────────────────────────────────
                              分享链接
───────────────────────────────────────────────────────────────────────────────

${share_link}

───────────────────────────────────────────────────────────────────────────────
                              重要提示
───────────────────────────────────────────────────────────────────────────────

1. 支持 TCP+UDP
2. 推荐客户端: Shadowrocket, Clash, V2rayN, ss-local
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
# 1. 传统 SS AEAD，使用 chacha20-ietf-poly1305
# 2. 基于 Xray-core 实现，与 VLESS/Trojan 共享安装
# 3. 不需要 TLS 证书
# 4. 默认端口 8388，支持 TCP+UDP
# 5. SS 链接格式使用 base64 编码
