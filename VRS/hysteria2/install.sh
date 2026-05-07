#!/bin/bash

#===============================================================================
# Hysteria 2 一键安装脚本
# 适用于 Debian/Ubuntu 系统
#
# __ai_context__:
#   Hysteria 2 是基于 QUIC 协议的高速代理，特别适合高延迟/高丢包网络。
#   使用 UDP 传输，自签证书。安装官方 hysteria 二进制。
#
# 功能：
#   - 安装 Hysteria 2 服务端
#   - 自签 TLS 证书
#   - 配置 QUIC 传输
#   - 启用 BBR 加速
#   - 生成客户端配置和 hysteria2:// 分享链接
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

#-------------------------------------------------------------------------------
# 配置变量
#-------------------------------------------------------------------------------
HYSTERIA_DIR="/etc/hysteria"
HYSTERIA_CONFIG="${HYSTERIA_DIR}/config.yaml"
CERT_DIR="${HYSTERIA_DIR}/certs"
CLIENT_CONFIG_FILE="${HYSTERIA_DIR}/client-config.txt"
SHARE_LINK_FILE="${HYSTERIA_DIR}/hysteria2-link.txt"

PORT=443
# 密码使用随机生成
PASSWORD=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../lib/firewall-ssh-guard.sh"
source "${SCRIPT_DIR}/../lib/uri-encode.sh"

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║         Hysteria 2 一键安装脚本 for Debian/Ubuntu              ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
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
    log_info "检查端口 ${PORT}/udp 是否可用..."
    if ss -ulnp 2>/dev/null | grep -q ":${PORT} "; then
        log_warn "端口 ${PORT}/udp 已被占用，切换到 8443"
        PORT=8443
        if ss -ulnp 2>/dev/null | grep -q ":${PORT} "; then
            log_error "备用端口也被占用"
            exit 1
        fi
    fi
    log_success "将使用端口: ${PORT}/udp"
}

#-------------------------------------------------------------------------------
# 安装依赖和 Hysteria 2
#-------------------------------------------------------------------------------
install_dependencies() {
    log_info "安装依赖..."
    apt-get update > /dev/null 2>&1
    apt-get install -y curl wget openssl qrencode > /dev/null 2>&1
    log_success "依赖安装完成"
}

install_hysteria() {
    log_info "安装 Hysteria 2..."

    # 使用官方安装脚本
    bash <(curl -fsSL https://get.hy2.sh/)

    if [[ ! -f /usr/local/bin/hysteria ]]; then
        log_error "Hysteria 2 安装失败"
        exit 1
    fi

    local version=$(/usr/local/bin/hysteria version 2>/dev/null | head -1 || echo "unknown")
    log_success "Hysteria 2 安装完成: ${version}"
}

#-------------------------------------------------------------------------------
# 生成自签证书
#-------------------------------------------------------------------------------
generate_cert() {
    log_info "生成自签 TLS 证书..."
    mkdir -p "$CERT_DIR"

    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "localhost")

    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "${CERT_DIR}/server.key" \
        -out "${CERT_DIR}/server.crt" \
        -subj "/CN=bing.com" \
        -days 3650 2>/dev/null

    chmod 644 "${CERT_DIR}/server.crt"
    chmod 600 "${CERT_DIR}/server.key"
    log_success "TLS 证书生成完成"
}

#-------------------------------------------------------------------------------
# 生成配置
#-------------------------------------------------------------------------------
generate_config() {
    log_info "生成 Hysteria 2 配置..."
    mkdir -p "$HYSTERIA_DIR"

    # 生成随机密码
    PASSWORD=$(openssl rand -base64 32)

    cat > "$HYSTERIA_CONFIG" << EOF
# Hysteria 2 服务端配置

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

    chmod 600 "$HYSTERIA_CONFIG"
    log_success "配置文件生成完成"
}

#-------------------------------------------------------------------------------
# 配置 systemd 服务
#-------------------------------------------------------------------------------
configure_service() {
    log_info "配置 Hysteria 2 服务..."

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

    systemctl daemon-reload
    systemctl enable hysteria-server
    systemctl restart hysteria-server
    sleep 2

    if systemctl is-active --quiet hysteria-server; then
        log_success "Hysteria 2 服务启动成功"
    else
        log_error "Hysteria 2 服务启动失败"
        systemctl status hysteria-server
        exit 1
    fi
}

configure_firewall() {
    log_info "配置防火墙..."
    if command -v ufw &> /dev/null; then
        ensure_ssh_ufw_rules
        ufw allow ${PORT}/udp > /dev/null 2>&1 || true
        ufw --force enable > /dev/null 2>&1 || true
        log_success "UFW 已开放端口 ${PORT}/udp，SSH 端口已保留"
    elif command -v iptables &> /dev/null; then
        ensure_ssh_iptables_rules
        iptables -C INPUT -p udp --dport ${PORT} -j ACCEPT 2>/dev/null || \
            iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT
        log_success "iptables 已开放端口 ${PORT}/udp，SSH 端口已保留"
    fi
}

enable_bbr() {
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        log_success "BBR 已启用"
        return
    fi
    local major minor
    major=$(uname -r | cut -d. -f1)
    minor=$(uname -r | cut -d. -f2)
    if [[ "$major" -lt 4 ]] || [[ "$major" -eq 4 && "$minor" -lt 9 ]]; then
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

    # Hysteria 2 分享链接
    local encoded_password
    encoded_password=$(uri_encode_component "$PASSWORD")

    local share_link="hysteria2://${encoded_password}@${server_ip}:${PORT}?insecure=1&sni=bing.com#Hysteria2"

    echo -n "$share_link" > "$SHARE_LINK_FILE"
    chmod 600 "$SHARE_LINK_FILE"

    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                        Hysteria 2 客户端配置
═══════════════════════════════════════════════════════════════════════════════

服务器地址: ${server_ip}
端口: ${PORT} (UDP)
密码: ${PASSWORD}
TLS SNI: bing.com
跳过证书验证: 是 (自签证书)

───────────────────────────────────────────────────────────────────────────────
                              分享链接
───────────────────────────────────────────────────────────────────────────────

${share_link}

───────────────────────────────────────────────────────────────────────────────
                         Clash Meta 配置片段
───────────────────────────────────────────────────────────────────────────────

- name: "Hysteria2"
  type: hysteria2
  server: ${server_ip}
  port: ${PORT}
  password: "${PASSWORD}"
  sni: bing.com
  skip-cert-verify: true

───────────────────────────────────────────────────────────────────────────────
                              重要提示
───────────────────────────────────────────────────────────────────────────────

1. Hysteria 2 使用 UDP 协议，请确保防火墙/安全组开放 ${PORT}/UDP
2. 使用自签证书，客户端需开启 "跳过证书验证"
3. 推荐客户端: Clash Meta (mihomo), Shadowrocket, NekoBox
4. 服务状态: systemctl status hysteria-server
5. 卸载: bash $(dirname "$0")/uninstall.sh

═══════════════════════════════════════════════════════════════════════════════
EOF

    chmod 600 "$CLIENT_CONFIG_FILE"
    log_success "客户端配置已保存到 ${CLIENT_CONFIG_FILE}"

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
    echo ""
    log_info "开始安装 Hysteria 2..."
    echo ""

    check_root
    check_system
    check_port
    echo ""

    install_dependencies
    install_hysteria
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
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    安装完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    cat "$CLIENT_CONFIG_FILE"
}

main "$@"

# [For Future AI]
# 1. Hysteria 2 使用 QUIC/UDP 协议，需要开放 UDP 端口
# 2. 使用官方安装脚本 https://get.hy2.sh/
# 3. 自签证书 SNI 设置为 bing.com 作为伪装
# 4. 客户端需设置 insecure=1 跳过证书验证
# 5. systemd 服务名为 hysteria-server
