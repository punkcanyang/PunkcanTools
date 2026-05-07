#!/bin/bash

#===============================================================================
# VLESS + WebSocket + TLS 一键安装脚本
# 适用于 Debian/Ubuntu 系统
#
# __ai_context__:
#   此脚本用于在 Linux 服务器上一键部署 VLESS+WebSocket+TLS 代理。
#   使用 Xray-core 作为底层，自签证书提供 TLS。
#   适合需要通过 CDN 中转的场景。
#
# 功能：
#   - 安装 Xray-core
#   - 配置 VLESS + WebSocket + TLS (自签证书)
#   - 启用 BBR 加速
#   - 配置防火墙
#   - 生成客户端配置和分享链接
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# 颜色定义
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

#-------------------------------------------------------------------------------
# 配置变量
#-------------------------------------------------------------------------------
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
CERT_DIR="${XRAY_CONFIG_DIR}/certs"
CLIENT_CONFIG_FILE="${XRAY_CONFIG_DIR}/client-config.txt"
SHARE_LINK_FILE="${XRAY_CONFIG_DIR}/vless-ws-link.txt"
VRS_PROTOCOL_ID="vless-ws"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../lib/xray-protocol-guard.sh"

# 默认配置
PORT=443
WS_PATH="/ws"

#-------------------------------------------------------------------------------
# 工具函数
#-------------------------------------------------------------------------------
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║     VLESS + WebSocket + TLS 一键安装脚本 for Debian/Ubuntu    ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

#-------------------------------------------------------------------------------
# 系统检查
#-------------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        log_info "请使用: sudo bash $0"
        exit 1
    fi
    log_success "Root 权限检查通过"
}

check_system() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法检测操作系统"
        exit 1
    fi
    source /etc/os-release
    if [[ "$ID" != "debian" && "$ID" != "ubuntu" ]]; then
        log_warn "此脚本针对 Debian/Ubuntu 优化，当前系统: $ID"
        read -p "是否继续？(y/N): " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 1
    fi
    log_success "系统检查通过: $PRETTY_NAME"
}

check_port() {
    log_info "检查端口 ${PORT} 是否可用..."
    if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
        log_warn "端口 ${PORT} 已被占用，切换到 8443"
        PORT=8443
        if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
            log_error "备用端口 ${PORT} 也被占用"
            exit 1
        fi
    fi
    log_success "将使用端口: ${PORT}"
}

#-------------------------------------------------------------------------------
# 安装依赖
#-------------------------------------------------------------------------------
install_dependencies() {
    log_info "更新软件源并安装依赖..."
    apt-get update > /dev/null 2>&1
    apt-get install -y curl wget unzip jq openssl cron qrencode > /dev/null 2>&1
    log_success "依赖安装完成"
}

#-------------------------------------------------------------------------------
# 安装 Xray-core
#-------------------------------------------------------------------------------
install_xray() {
    log_info "正在安装 Xray-core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    if [[ ! -f /usr/local/bin/xray ]]; then
        log_error "Xray 安装失败"
        exit 1
    fi
    local version=$(/usr/local/bin/xray version | head -n1 | awk '{print $2}')
    log_success "Xray ${version} 安装完成"
}

#-------------------------------------------------------------------------------
# 生成自签 TLS 证书
#-------------------------------------------------------------------------------
generate_self_signed_cert() {
    log_info "生成自签 TLS 证书..."
    mkdir -p "$CERT_DIR"

    # 使用服务器 IP 作为 CN
    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "localhost")

    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "${CERT_DIR}/server.key" \
        -out "${CERT_DIR}/server.crt" \
        -subj "/CN=${server_ip}" \
        -days 3650 2>/dev/null

    chmod 644 "${CERT_DIR}/server.crt"
    chmod 600 "${CERT_DIR}/server.key"
    log_success "TLS 证书生成完成 (有效期 10 年)"
}

#-------------------------------------------------------------------------------
# 生成配置
#-------------------------------------------------------------------------------
generate_config() {
    log_info "生成 Xray 配置..."
    mkdir -p "$XRAY_CONFIG_DIR"

    # 生成 UUID
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
                "clients": [
                    {
                        "id": "${UUID}",
                        "level": 0
                    }
                ],
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
                "wsSettings": {
                    "path": "${WS_PATH}"
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
    log_success "配置文件生成完成"
}

#-------------------------------------------------------------------------------
# 配置服务与防火墙
#-------------------------------------------------------------------------------
configure_service() {
    log_info "启动 Xray 服务..."
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray
    sleep 2
    if systemctl is-active --quiet xray; then
        log_success "Xray 服务启动成功"
    else
        log_error "Xray 服务启动失败"
        systemctl status xray
        exit 1
    fi
}

configure_firewall() {
    log_info "配置防火墙..."
    if command -v ufw &> /dev/null; then
        ufw allow ${PORT}/tcp > /dev/null 2>&1 || true
        ufw --force enable > /dev/null 2>&1 || true
        log_success "UFW 已开放端口 ${PORT}"
    elif command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
        log_success "iptables 已开放端口 ${PORT}"
    else
        log_warn "未检测到防火墙"
    fi
}

enable_bbr() {
    log_info "启用 BBR..."
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        log_success "BBR 已启用"
        return
    fi
    local major minor
    major=$(uname -r | cut -d. -f1)
    minor=$(uname -r | cut -d. -f2)
    if [[ "$major" -lt 4 ]] || [[ "$major" -eq 4 && "$minor" -lt 9 ]]; then
        log_warn "内核不支持 BBR (需要 4.9+)"
        return
    fi
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    log_success "BBR 启用成功"
}

#-------------------------------------------------------------------------------
# 生成客户端配置
#-------------------------------------------------------------------------------
generate_client_config() {
    log_info "生成客户端配置..."

    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")

    # VLESS 分享链接
    # 注意：自签证书需要客户端允许不安全连接 (allowInsecure=1)
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

───────────────────────────────────────────────────────────────────────────────
                              分享链接
───────────────────────────────────────────────────────────────────────────────

${share_link}

───────────────────────────────────────────────────────────────────────────────
                              重要提示
───────────────────────────────────────────────────────────────────────────────

1. 使用自签证书，客户端需开启 "允许不安全连接" (allowInsecure)
2. 查看配置: cat ${CLIENT_CONFIG_FILE}
3. 查看链接: cat ${SHARE_LINK_FILE}
4. 服务状态: systemctl status xray
5. 卸载: bash $(dirname "$0")/uninstall.sh

═══════════════════════════════════════════════════════════════════════════════
EOF

    log_success "客户端配置已保存到 ${CLIENT_CONFIG_FILE}"

    # 显示终端二维码
    if command -v qrencode &> /dev/null; then
        echo ""
        echo -e "${CYAN}扫描二维码导入配置:${NC}"
        qrencode -t ANSIUTF8 "$share_link"
    fi
}

#-------------------------------------------------------------------------------
# 主函数
#-------------------------------------------------------------------------------
main() {
    print_banner
    parse_xray_guard_args "$@"
    echo ""
    log_info "开始安装 VLESS + WebSocket + TLS..."
    echo ""

    check_root
    check_system
    check_xray_config_ownership
    check_port
    echo ""

    install_dependencies
    install_xray
    echo ""

    generate_self_signed_cert
    generate_config
    write_xray_protocol_marker
    echo ""

    configure_service
    configure_firewall
    enable_bbr
    echo ""

    generate_client_config
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    安装完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    cat "$CLIENT_CONFIG_FILE"
}

main "$@"

# [For Future AI]
# 1. 假设系统为 Debian/Ubuntu，使用 apt-get 安装依赖
# 2. 使用自签证书，客户端需配置 allowInsecure=1
# 3. 与 VLESS+Reality 共享 Xray-core，但配置不同
# 4. 边缘情况：端口 443 被占用时自动切换到 8443
# 5. 依赖 Xray 官方安装脚本和 systemd 服务
