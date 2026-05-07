#!/bin/bash

#===============================================================================
# WireGuard 一键安装脚本
# 适用于 Debian/Ubuntu 系统
#
# __ai_context__:
#   WireGuard 是内核级别的 VPN，性能极佳。
#   使用 UDP 传输，密钥对认证。安装 wireguard 内核模块和工具。
#   自动配置 NAT 和 IP 转发。
#
# 功能：
#   - 安装 WireGuard 内核模块和工具
#   - 自动生成服务端/客户端密钥
#   - 配置 NAT 和 IP 转发
#   - 生成客户端 .conf 文件和二维码
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

WG_DIR="/etc/wireguard"
WG_CONFIG="${WG_DIR}/wg0.conf"
CLIENT_DIR="${WG_DIR}/clients"
CLIENT_CONFIG_FILE="${WG_DIR}/client-config.txt"

PORT=51820
# WireGuard 使用 10.66.66.0/24 作为内网子网
WG_SUBNET="10.66.66"
SERVER_WG_IP="${WG_SUBNET}.1"
CLIENT_WG_IP="${WG_SUBNET}.2"
DNS="1.1.1.1, 8.8.8.8"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║        WireGuard 一键安装脚本 for Debian/Ubuntu                ║"
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
    if ss -ulnp 2>/dev/null | grep -q ":${PORT} "; then
        PORT=51821
        log_warn "51820 被占用，使用 ${PORT}"
    fi
    log_success "端口: ${PORT}/udp"
}

#-------------------------------------------------------------------------------
# 安装 WireGuard
#-------------------------------------------------------------------------------
install_wireguard() {
    log_info "安装 WireGuard..."
    apt-get update > /dev/null 2>&1
    apt-get install -y wireguard wireguard-tools qrencode > /dev/null 2>&1

    # 验证安装
    if ! command -v wg &> /dev/null; then
        log_error "WireGuard 安装失败"
        exit 1
    fi
    log_success "WireGuard 安装完成"
}

#-------------------------------------------------------------------------------
# 启用 IP 转发
#-------------------------------------------------------------------------------
enable_ip_forward() {
    log_info "启用 IP 转发..."

    # 启用 IPv4 转发
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi

    # 立即生效
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
    log_success "IP 转发已启用"
}

#-------------------------------------------------------------------------------
# 生成密钥和配置
#-------------------------------------------------------------------------------
generate_config() {
    log_info "生成密钥和配置..."
    mkdir -p "$WG_DIR" "$CLIENT_DIR"
    chmod 700 "$WG_DIR"

    # 生成服务端密钥
    local server_private_key
    local server_public_key
    server_private_key=$(wg genkey)
    server_public_key=$(echo "$server_private_key" | wg pubkey)

    # 生成客户端密钥
    local client_private_key
    local client_public_key
    local client_preshared_key
    client_private_key=$(wg genkey)
    client_public_key=$(echo "$client_private_key" | wg pubkey)
    client_preshared_key=$(wg genpsk)

    # 检测主网卡
    local main_interface
    main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [[ -z "$main_interface" ]]; then
        main_interface="eth0"
        log_warn "无法检测主网卡，使用默认 eth0"
    fi

    # 生成服务端配置
    cat > "$WG_CONFIG" << EOF
# WireGuard 服务端配置
[Interface]
Address = ${SERVER_WG_IP}/24
ListenPort = ${PORT}
PrivateKey = ${server_private_key}

# NAT 规则：使客户端流量通过服务器上网
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${main_interface} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${main_interface} -j MASQUERADE

# 客户端 1
[Peer]
PublicKey = ${client_public_key}
PresharedKey = ${client_preshared_key}
AllowedIPs = ${CLIENT_WG_IP}/32
EOF

    chmod 600 "$WG_CONFIG"

    # 获取服务器公网 IP
    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")

    # 生成客户端配置文件
    local client_conf="${CLIENT_DIR}/client1.conf"
    cat > "$client_conf" << EOF
# WireGuard 客户端配置
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

    # 保存客户端信息到总配置文件
    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                       WireGuard 客户端配置
═══════════════════════════════════════════════════════════════════════════════

服务器地址: ${server_ip}
端口: ${PORT} (UDP)
服务端公钥: ${server_public_key}
客户端内网 IP: ${CLIENT_WG_IP}/24
DNS: ${DNS}

───────────────────────────────────────────────────────────────────────────────
                         客户端配置文件内容
───────────────────────────────────────────────────────────────────────────────

$(cat "$client_conf")

───────────────────────────────────────────────────────────────────────────────
                              重要提示
───────────────────────────────────────────────────────────────────────────────

1. 客户端配置文件: ${client_conf}
2. 下载到本地: scp root@${server_ip}:${client_conf} ./client1.conf
3. Windows/Mac/iOS/Android 都有 WireGuard 官方客户端
4. 导入 .conf 文件即可使用
5. 服务状态: wg show / systemctl status wg-quick@wg0
6. 卸载: bash $(dirname "$0")/uninstall.sh

═══════════════════════════════════════════════════════════════════════════════
EOF

    log_success "密钥和配置生成完成"
}

#-------------------------------------------------------------------------------
# 启动 WireGuard
#-------------------------------------------------------------------------------
start_wireguard() {
    log_info "启动 WireGuard..."
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
    sleep 2

    if systemctl is-active --quiet wg-quick@wg0; then
        log_success "WireGuard 启动成功"
    else
        log_error "WireGuard 启动失败"
        systemctl status wg-quick@wg0
        exit 1
    fi
}

configure_firewall() {
    if command -v ufw &> /dev/null; then
        ufw allow ${PORT}/udp > /dev/null 2>&1 || true
        log_success "UFW 已开放 ${PORT}/udp"
    elif command -v iptables &> /dev/null; then
        iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT
        log_success "iptables 已开放 ${PORT}/udp"
    fi
}

#-------------------------------------------------------------------------------
# 主函数
#-------------------------------------------------------------------------------
main() {
    print_banner
    echo ""
    check_root
    check_system
    check_port
    echo ""
    install_wireguard
    enable_ip_forward
    echo ""
    generate_config
    echo ""
    start_wireguard
    configure_firewall
    echo ""

    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    安装完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    cat "$CLIENT_CONFIG_FILE"

    # 显示二维码
    local client_conf="${CLIENT_DIR}/client1.conf"
    if command -v qrencode &> /dev/null && [[ -f "$client_conf" ]]; then
        echo ""
        echo -e "${CYAN}手机扫描二维码导入配置:${NC}"
        echo ""
        qrencode -t ANSIUTF8 < "$client_conf"
    fi
}

main "$@"

# [For Future AI]
# 1. WireGuard 使用内核模块，性能最佳
# 2. 需要开启 IP 转发和 NAT 规则
# 3. 使用 wg-quick@wg0 作为 systemd 服务名
# 4. 客户端 .conf 可直接导入官方 WireGuard 客户端
# 5. 默认使用 10.66.66.0/24 子网
# 6. 自动检测主网卡用于 NAT 规则
