#!/bin/bash

#===============================================================================
# OpenVPN 一键安装脚本
# 适用于 Debian/Ubuntu 系统
#
# __ai_context__:
#   OpenVPN 是经典的 SSL VPN 方案。使用 Easy-RSA 建立 CA 和证书体系。
#   生成一体化 .ovpn 客户端配置文件，包含证书和密钥。
#   默认使用 UDP 1194 端口，支持全流量代理。
#
# 功能：
#   - 安装 OpenVPN + Easy-RSA
#   - 自动建立 CA 和服务器/客户端证书
#   - 配置 NAT 和 IP 转发
#   - 生成 .ovpn 一体化客户端配置
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

OPENVPN_DIR="/etc/openvpn"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
CLIENT_DIR="${OPENVPN_DIR}/clients"
CLIENT_CONFIG_FILE="${OPENVPN_DIR}/client-config.txt"

PORT=1194
PROTOCOL="udp"
# OpenVPN 使用 10.8.0.0/24 子网
VPN_SUBNET="10.8.0.0"
VPN_NETMASK="255.255.255.0"
DNS1="1.1.1.1"
DNS2="8.8.8.8"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../lib/firewall-ssh-guard.sh"

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║         OpenVPN 一键安装脚本 for Debian/Ubuntu                 ║"
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

#-------------------------------------------------------------------------------
# 安装 OpenVPN 和 Easy-RSA
#-------------------------------------------------------------------------------
install_openvpn() {
    log_info "安装 OpenVPN 和 Easy-RSA..."
    apt-get update > /dev/null 2>&1
    apt-get install -y openvpn easy-rsa iptables curl iproute2 procps > /dev/null 2>&1

    if ! command -v openvpn &> /dev/null; then
        log_error "OpenVPN 安装失败"
        exit 1
    fi
    log_success "OpenVPN 安装完成: $(openvpn --version | head -1 | awk '{print $2}')"
}

#-------------------------------------------------------------------------------
# 初始化 PKI 和生成证书
#-------------------------------------------------------------------------------
setup_pki() {
    log_info "初始化 PKI 和生成证书..."

    # 初始化 Easy-RSA
    mkdir -p "$EASYRSA_DIR"
    cp -r /usr/share/easy-rsa/* "$EASYRSA_DIR/" 2>/dev/null || \
    cp -r /usr/share/doc/easy-rsa/examples/easyrsa3/* "$EASYRSA_DIR/" 2>/dev/null || true

    cd "$EASYRSA_DIR"

    # 设置变量
    cat > vars << EOF
set_var EASYRSA_ALGO        ec
set_var EASYRSA_CURVE       prime256v1
set_var EASYRSA_DIGEST      "sha256"
set_var EASYRSA_REQ_CN      "OpenVPN-CA"
set_var EASYRSA_BATCH       "yes"
EOF

    # 初始化 PKI
    ./easyrsa init-pki > /dev/null 2>&1

    # 生成 CA (不加密)
    ./easyrsa --batch build-ca nopass > /dev/null 2>&1
    log_success "CA 证书生成完成"

    # 生成服务器证书
    ./easyrsa --batch build-server-full server nopass > /dev/null 2>&1
    log_success "服务器证书生成完成"

    # 生成客户端证书
    ./easyrsa --batch build-client-full client1 nopass > /dev/null 2>&1
    log_success "客户端证书生成完成"

    # 生成 TLS 认证密钥
    openvpn --genkey secret "${OPENVPN_DIR}/tls-auth.key"
    chmod 600 "${OPENVPN_DIR}/tls-auth.key"
    log_success "TLS 认证密钥生成完成"

    cd - > /dev/null
}

#-------------------------------------------------------------------------------
# 生成 OpenVPN 服务端配置
#-------------------------------------------------------------------------------
generate_server_config() {
    log_info "生成服务端配置..."

    cat > "${OPENVPN_DIR}/server.conf" << EOF
# OpenVPN 服务端配置
port ${PORT}
proto ${PROTOCOL}
dev tun

ca ${EASYRSA_DIR}/pki/ca.crt
cert ${EASYRSA_DIR}/pki/issued/server.crt
key ${EASYRSA_DIR}/pki/private/server.key

tls-auth ${OPENVPN_DIR}/tls-auth.key 0
auth SHA256
cipher AES-256-GCM

server ${VPN_SUBNET} ${VPN_NETMASK}

# 推送路由和 DNS
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS ${DNS1}"
push "dhcp-option DNS ${DNS2}"

# 性能设置
keepalive 10 120
persist-key
persist-tun
user nobody
group nogroup

# 日志
status /var/log/openvpn/status.log
log-append /var/log/openvpn/openvpn.log
verb 3
mute 20

# 允许多个客户端使用同一证书
duplicate-cn
EOF

    mkdir -p /var/log/openvpn
    log_success "服务端配置完成"
}

#-------------------------------------------------------------------------------
# 启用 IP 转发和 NAT
#-------------------------------------------------------------------------------
enable_ip_forward() {
    log_info "启用 IP 转发..."
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1

    # 检测主网卡并配置 NAT
    local main_interface
    main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    [[ -z "$main_interface" ]] && main_interface="eth0"

    iptables -t nat -A POSTROUTING -s ${VPN_SUBNET}/24 -o ${main_interface} -j MASQUERADE
    iptables -A FORWARD -i tun0 -j ACCEPT
    iptables -A FORWARD -o tun0 -j ACCEPT
    ensure_ssh_iptables_rules

    # 持久化 iptables 规则
    if command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables.rules
        mkdir -p /etc/network/if-pre-up.d
        cat > /etc/network/if-pre-up.d/iptables << 'IPTEOF'
#!/bin/sh
iptables-restore < /etc/iptables.rules
IPTEOF
        chmod +x /etc/network/if-pre-up.d/iptables
    fi

    log_success "IP 转发和 NAT 配置完成"
}

#-------------------------------------------------------------------------------
# 启动 OpenVPN
#-------------------------------------------------------------------------------
start_openvpn() {
    log_info "启动 OpenVPN..."
    systemctl enable openvpn@server
    systemctl restart openvpn@server
    sleep 3

    if systemctl is-active --quiet openvpn@server; then
        log_success "OpenVPN 启动成功"
    else
        log_error "OpenVPN 启动失败"
        systemctl status openvpn@server
        exit 1
    fi
}

configure_firewall() {
    if command -v ufw &> /dev/null; then
        ensure_ssh_ufw_rules
        ufw allow ${PORT}/${PROTOCOL} > /dev/null 2>&1 || true
        log_success "UFW 已开放 ${PORT}/${PROTOCOL}，SSH 端口已保留"
    fi
}

#-------------------------------------------------------------------------------
# 生成 .ovpn 客户端配置
#-------------------------------------------------------------------------------
generate_client_config() {
    log_info "生成客户端配置..."
    mkdir -p "$CLIENT_DIR"
    chmod 700 "$CLIENT_DIR"

    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")

    local ovpn_file="${CLIENT_DIR}/client1.ovpn"

    cat > "$ovpn_file" << EOF
# OpenVPN 客户端配置
client
dev tun
proto ${PROTOCOL}
remote ${server_ip} ${PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-GCM
key-direction 1
verb 3

<ca>
$(cat "${EASYRSA_DIR}/pki/ca.crt")
</ca>

<cert>
$(cat "${EASYRSA_DIR}/pki/issued/client1.crt")
</cert>

<key>
$(cat "${EASYRSA_DIR}/pki/private/client1.key")
</key>

<tls-auth>
$(cat "${OPENVPN_DIR}/tls-auth.key")
</tls-auth>
EOF
    chmod 600 "$ovpn_file"

    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                       OpenVPN 客户端配置
═══════════════════════════════════════════════════════════════════════════════

服务器地址: ${server_ip}
端口: ${PORT} (${PROTOCOL^^})
加密: AES-256-GCM
认证: SHA256

───────────────────────────────────────────────────────────────────────────────
                              重要提示
───────────────────────────────────────────────────────────────────────────────

1. 客户端配置文件 (.ovpn): ${ovpn_file}
2. 下载到本地: scp root@${server_ip}:${ovpn_file} ./client1.ovpn
3. 客户端推荐:
   - Windows: OpenVPN GUI / OpenVPN Connect
   - macOS: Tunnelblick / OpenVPN Connect
   - iOS/Android: OpenVPN Connect
   - Linux: openvpn --config client1.ovpn
4. 导入 .ovpn 文件即可连接
5. 服务状态: systemctl status openvpn@server
6. 查看日志: tail -f /var/log/openvpn/openvpn.log
7. 卸载: bash $(dirname "$0")/uninstall.sh

═══════════════════════════════════════════════════════════════════════════════
EOF
    chmod 600 "$CLIENT_CONFIG_FILE"

    log_success ".ovpn 客户端配置已保存到 ${ovpn_file}"
}

main() {
    print_banner
    echo ""
    check_root
    check_system
    echo ""
    install_openvpn
    setup_pki
    echo ""
    generate_server_config
    enable_ip_forward
    echo ""
    start_openvpn
    configure_firewall
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
# 1. OpenVPN 使用 Easy-RSA 建立 CA 和证书体系
# 2. 使用 EC (prime256v1) 而非 RSA 以提升性能
# 3. 生成一体化 .ovpn 文件包含所有证书
# 4. 需要 IP 转发和 NAT 规则
# 5. systemd 服务名: openvpn@server
# 6. duplicate-cn 允许多设备共用证书
