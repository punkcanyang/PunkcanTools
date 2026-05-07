#!/bin/bash

#===============================================================================
# WireGuard 一键安装脚本 (CentOS/RHEL 版本)
#
# __ai_context__:
#   CentOS 版 WireGuard 需要 EPEL 和 elrepo 仓库来安装内核模块。
#   CentOS 8+ 的内核已内置 WireGuard 支持。
#===============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

WG_DIR="/etc/wireguard"
WG_CONFIG="${WG_DIR}/wg0.conf"
CLIENT_DIR="${WG_DIR}/clients"
CLIENT_CONFIG_FILE="${WG_DIR}/client-config.txt"
PORT=51820
WG_SUBNET="10.66.66"
SERVER_WG_IP="${WG_SUBNET}.1"
CLIENT_WG_IP="${WG_SUBNET}.2"
DNS="1.1.1.1, 8.8.8.8"
PKG_MANAGER=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }; log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }; log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║       WireGuard 一键安装脚本 for CentOS/RHEL                   ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() { [[ $EUID -ne 0 ]] && { log_error "需要 root 权限"; exit 1; }; log_success "Root OK"; }
check_system() {
    source /etc/os-release 2>/dev/null; command -v dnf &> /dev/null && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
    log_success "系统: $PRETTY_NAME ($PKG_MANAGER)"
}
check_port() { ss -ulnp 2>/dev/null | grep -q ":${PORT} " && PORT=51821; log_success "端口: ${PORT}/udp"; }

install_wireguard() {
    log_info "安装 WireGuard..."
    $PKG_MANAGER install -y epel-release > /dev/null 2>&1 || true

    # CentOS 8+ 内核已支持 WireGuard，只需安装工具
    # CentOS 7 需要 elrepo 内核
    $PKG_MANAGER install -y wireguard-tools qrencode > /dev/null 2>&1 || {
        # 尝试安装 kmod-wireguard (CentOS 8)
        $PKG_MANAGER install -y kmod-wireguard wireguard-tools qrencode > /dev/null 2>&1 || {
            log_error "WireGuard 安装失败，可能需要升级内核"
            exit 1
        }
    }

    if ! command -v wg &> /dev/null; then
        log_error "WireGuard 安装失败"; exit 1
    fi
    log_success "WireGuard 安装完成"
}

enable_ip_forward() {
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
    log_success "IP 转发已启用"
}

generate_config() {
    log_info "生成密钥和配置..."
    mkdir -p "$WG_DIR" "$CLIENT_DIR"; chmod 700 "$WG_DIR"

    local server_private_key server_public_key client_private_key client_public_key client_preshared_key
    server_private_key=$(wg genkey); server_public_key=$(echo "$server_private_key" | wg pubkey)
    client_private_key=$(wg genkey); client_public_key=$(echo "$client_private_key" | wg pubkey)
    client_preshared_key=$(wg genpsk)

    local main_interface
    main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    [[ -z "$main_interface" ]] && main_interface="eth0"

    cat > "$WG_CONFIG" << EOF
[Interface]
Address = ${SERVER_WG_IP}/24
ListenPort = ${PORT}
PrivateKey = ${server_private_key}
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${main_interface} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${main_interface} -j MASQUERADE

[Peer]
PublicKey = ${client_public_key}
PresharedKey = ${client_preshared_key}
AllowedIPs = ${CLIENT_WG_IP}/32
EOF
    chmod 600 "$WG_CONFIG"

    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")

    local client_conf="${CLIENT_DIR}/client1.conf"
    cat > "$client_conf" << EOF
[Interface]
PrivateKey = ${client_private_key}
Address = ${CLIENT_WG_IP}/24
DNS = ${DNS}

[Peer]
PublicKey = ${server_public_key}
PresharedKey = ${client_preshared_key}
Endpoint = ${server_ip}:${PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                    WireGuard 客户端配置 (CentOS)
═══════════════════════════════════════════════════════════════════════════════
服务器: ${server_ip}:${PORT} (UDP) | 客户端 IP: ${CLIENT_WG_IP}/24

客户端配置文件: ${client_conf}
下载: scp root@${server_ip}:${client_conf} ./client1.conf

服务状态: wg show / systemctl status wg-quick@wg0
卸载: bash $(dirname "$0")/uninstall-centos.sh
═══════════════════════════════════════════════════════════════════════════════
EOF
    log_success "配置完成"
}

start_wireguard() {
    systemctl enable wg-quick@wg0; systemctl start wg-quick@wg0; sleep 2
    systemctl is-active --quiet wg-quick@wg0 && log_success "WireGuard 启动成功" || { log_error "启动失败"; exit 1; }
}

configure_firewall() {
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=${PORT}/udp > /dev/null 2>&1
        firewall-cmd --permanent --add-masquerade > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        log_success "firewalld 已开放 ${PORT}/udp"
    fi
}

main() {
    print_banner; echo ""; check_root; check_system; check_port; echo ""
    install_wireguard; enable_ip_forward; echo ""
    generate_config; echo ""
    start_wireguard; configure_firewall; echo ""
    echo -e "${GREEN}════════ 安装完成！════════${NC}\n"
    cat "$CLIENT_CONFIG_FILE"
    local client_conf="${CLIENT_DIR}/client1.conf"
    if command -v qrencode &> /dev/null && [[ -f "$client_conf" ]]; then
        echo -e "\n${CYAN}手机扫描导入:${NC}\n"; qrencode -t ANSIUTF8 < "$client_conf"
    fi
}
main "$@"
