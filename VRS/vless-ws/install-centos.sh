#!/bin/bash

#===============================================================================
# VLESS + WebSocket + TLS 一键安装脚本 (CentOS/RHEL 版本)
# 适用于 CentOS 8/9, RHEL, Rocky Linux, AlmaLinux
#
# __ai_context__:
#   CentOS 版本的 VLESS+WebSocket+TLS 安装脚本。
#   与 Debian 版差异：使用 dnf/yum、firewalld、EPEL 仓库。
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
SHARE_LINK_FILE="${XRAY_CONFIG_DIR}/vless-ws-link.txt"
VRS_PROTOCOL_ID="vless-ws"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../lib/xray-protocol-guard.sh"

PORT=443
WS_PATH="/ws"
PKG_MANAGER=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║  VLESS + WebSocket + TLS 安装脚本 for CentOS/RHEL             ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    [[ $EUID -ne 0 ]] && { log_error "需要 root 权限"; exit 1; }
    log_success "Root 权限检查通过"
}

check_system() {
    source /etc/os-release 2>/dev/null || { log_error "无法检测系统"; exit 1; }
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    else
        log_error "未找到 yum 或 dnf"; exit 1
    fi
    log_success "系统: $PRETTY_NAME (使用 $PKG_MANAGER)"
}

check_port() {
    if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
        PORT=8443
        log_warn "443 被占用，使用 ${PORT}"
    fi
    log_success "端口: ${PORT}"
}

install_epel() {
    if rpm -q epel-release > /dev/null 2>&1; then
        log_success "EPEL 已安装"
        return
    fi
    $PKG_MANAGER install -y epel-release > /dev/null 2>&1 || true
    log_success "EPEL 仓库已安装"
}

install_dependencies() {
    log_info "安装依赖..."
    $PKG_MANAGER install -y curl wget unzip jq openssl cronie qrencode > /dev/null 2>&1
    systemctl enable crond > /dev/null 2>&1 || true
    systemctl start crond > /dev/null 2>&1 || true
    log_success "依赖安装完成"
}

install_xray() {
    log_info "安装 Xray-core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    [[ ! -f /usr/local/bin/xray ]] && { log_error "Xray 安装失败"; exit 1; }
    log_success "Xray 安装完成"
}

generate_self_signed_cert() {
    log_info "生成自签证书..."
    mkdir -p "$CERT_DIR"
    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "localhost")
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "${CERT_DIR}/server.key" \
        -out "${CERT_DIR}/server.crt" \
        -subj "/CN=${server_ip}" \
        -days 3650 2>/dev/null
    chmod 644 "${CERT_DIR}/server.crt"
    chmod 600 "${CERT_DIR}/server.key"
    log_success "证书生成完成"
}

generate_config() {
    log_info "生成 Xray 配置..."
    mkdir -p "$XRAY_CONFIG_DIR"
    UUID=$(cat /proc/sys/kernel/random/uuid)

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
            "protocol": "vless",
            "settings": {
                "clients": [{"id": "${UUID}", "level": 0}],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "security": "tls",
                "tlsSettings": {
                    "certificates": [
                        {
                            "certificateFile": "${CERT_DIR}/server.crt",
                            "keyFile": "${CERT_DIR}/server.key"
                        }
                    ]
                },
                "wsSettings": {"path": "${WS_PATH}"}
            },
            "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
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
        log_error "启动失败"; exit 1
    fi
}

configure_firewall() {
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=${PORT}/tcp > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        log_success "firewalld 已开放 ${PORT}/tcp"
    elif command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
        log_success "iptables 已开放 ${PORT}/tcp"
    fi
}

enable_bbr() {
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then return; fi
    local major=$(uname -r | cut -d. -f1)
    local minor=$(uname -r | cut -d. -f2)
    if [[ "$major" -ge 5 ]] || [[ "$major" -eq 4 && "$minor" -ge 9 ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p > /dev/null 2>&1
        log_success "BBR 启用成功"
    fi
}

generate_client_config() {
    log_info "生成客户端配置..."
    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")
    local share_link="vless://${UUID}@${server_ip}:${PORT}?encryption=none&security=tls&type=ws&host=${server_ip}&path=${WS_PATH}&allowInsecure=1#VLESS-WS-TLS"
    echo -n "$share_link" > "$SHARE_LINK_FILE"

    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                     VLESS + WebSocket + TLS 客户端配置
═══════════════════════════════════════════════════════════════════════════════

服务器地址: ${server_ip}
端口: ${PORT}
UUID: ${UUID}
传输协议: WebSocket
WebSocket 路径: ${WS_PATH}
安全类型: TLS (自签证书，客户端需允许不安全连接)

分享链接: ${share_link}

提示:
1. 自签证书，客户端需开启 allowInsecure
2. 服务状态: systemctl status xray
3. 卸载: bash $(dirname "$0")/uninstall-centos.sh
═══════════════════════════════════════════════════════════════════════════════
EOF
    log_success "配置已保存"
    if command -v qrencode &> /dev/null; then
        echo ""; qrencode -t ANSIUTF8 "$share_link"
    fi
}

main() {
    print_banner; echo ""
    parse_xray_guard_args "$@"
    check_root; check_system; check_xray_config_ownership; check_port; echo ""
    install_epel; install_dependencies; install_xray; echo ""
    generate_self_signed_cert; generate_config; write_xray_protocol_marker; echo ""
    configure_service; configure_firewall; enable_bbr; echo ""
    generate_client_config
    echo -e "\n${GREEN}════════ 安装完成！════════${NC}\n"
    cat "$CLIENT_CONFIG_FILE"
}

main "$@"

# [For Future AI]
# 1. CentOS 版本使用 dnf/yum 和 firewalld
# 2. 需要 EPEL 仓库用于 qrencode 等包
# 3. cron 服务名为 crond (非 cron)
