#!/bin/bash

#===============================================================================
# OpenVPN 一键安装脚本 (CentOS/RHEL 版本)
#===============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

OPENVPN_DIR="/etc/openvpn"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
CLIENT_DIR="${OPENVPN_DIR}/clients"
CLIENT_CONFIG_FILE="${OPENVPN_DIR}/client-config.txt"
PORT=1194; PROTOCOL="udp"
VPN_SUBNET="10.8.0.0"; VPN_NETMASK="255.255.255.0"
DNS1="1.1.1.1"; DNS2="8.8.8.8"
PKG_MANAGER=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }; log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }; log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../lib/firewall-ssh-guard.sh"

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║        OpenVPN 一键安装脚本 for CentOS/RHEL                    ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() { [[ $EUID -ne 0 ]] && { log_error "需要 root 权限"; exit 1; }; log_success "Root OK"; }
check_system() {
    source /etc/os-release 2>/dev/null; command -v dnf &> /dev/null && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
    log_success "系统: $PRETTY_NAME ($PKG_MANAGER)"
}

install_openvpn() {
    log_info "安装 OpenVPN 和 Easy-RSA..."
    $PKG_MANAGER install -y epel-release > /dev/null 2>&1 || true
    $PKG_MANAGER install -y openvpn easy-rsa iptables curl iproute procps-ng > /dev/null 2>&1
    command -v openvpn &> /dev/null || { log_error "安装失败"; exit 1; }
    log_success "OpenVPN 安装完成"
}

setup_pki() {
    log_info "初始化 PKI..."
    mkdir -p "$EASYRSA_DIR"
    # CentOS 的 easy-rsa 路径可能不同
    cp -r /usr/share/easy-rsa/3/* "$EASYRSA_DIR/" 2>/dev/null || \
    cp -r /usr/share/easy-rsa/* "$EASYRSA_DIR/" 2>/dev/null || true
    cd "$EASYRSA_DIR"

    cat > vars << EOF
set_var EASYRSA_ALGO        ec
set_var EASYRSA_CURVE       prime256v1
set_var EASYRSA_DIGEST      "sha256"
set_var EASYRSA_REQ_CN      "OpenVPN-CA"
set_var EASYRSA_BATCH       "yes"
EOF
    ./easyrsa init-pki > /dev/null 2>&1
    ./easyrsa --batch build-ca nopass > /dev/null 2>&1; log_success "CA 完成"
    ./easyrsa --batch build-server-full server nopass > /dev/null 2>&1; log_success "服务器证书完成"
    ./easyrsa --batch build-client-full client1 nopass > /dev/null 2>&1; log_success "客户端证书完成"
    openvpn --genkey secret "${OPENVPN_DIR}/tls-auth.key"
    chmod 600 "${OPENVPN_DIR}/tls-auth.key"
    cd - > /dev/null
}

generate_server_config() {
    cat > "${OPENVPN_DIR}/server.conf" << EOF
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
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS ${DNS1}"
push "dhcp-option DNS ${DNS2}"
keepalive 10 120
persist-key
persist-tun
user nobody
group nobody
status /var/log/openvpn/status.log
log-append /var/log/openvpn/openvpn.log
verb 3
duplicate-cn
EOF
    mkdir -p /var/log/openvpn
    log_success "服务端配置完成"
}

enable_ip_forward() {
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1

    local main_interface
    main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    [[ -z "$main_interface" ]] && main_interface="eth0"

    iptables -t nat -A POSTROUTING -s ${VPN_SUBNET}/24 -o ${main_interface} -j MASQUERADE
    iptables -A FORWARD -i tun0 -j ACCEPT; iptables -A FORWARD -o tun0 -j ACCEPT
    ensure_ssh_iptables_rules

    # 持久化
    if command -v iptables-save &> /dev/null; then
        iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
    fi
    log_success "IP 转发和 NAT 已配置"
}

start_openvpn() {
    systemctl enable openvpn@server; systemctl restart openvpn@server; sleep 3
    systemctl is-active --quiet openvpn@server && log_success "OpenVPN 启动成功" || { log_error "启动失败"; exit 1; }
}

configure_firewall() {
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        ensure_ssh_firewalld_rules
        firewall-cmd --permanent --add-port=${PORT}/${PROTOCOL} > /dev/null 2>&1
        firewall-cmd --permanent --add-masquerade > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        log_success "firewalld 已配置，SSH 端口已保留"
    fi
}

generate_client_config() {
    mkdir -p "$CLIENT_DIR"
    chmod 700 "$CLIENT_DIR"
    local server_ip; server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")
    local ovpn_file="${CLIENT_DIR}/client1.ovpn"

    cat > "$ovpn_file" << EOF
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
                    OpenVPN 客户端配置 (CentOS)
═══════════════════════════════════════════════════════════════════════════════
服务器: ${server_ip}:${PORT} (${PROTOCOL^^}) | 加密: AES-256-GCM

.ovpn 文件: ${ovpn_file}
下载: scp root@${server_ip}:${ovpn_file} ./client1.ovpn

服务状态: systemctl status openvpn@server
卸载: bash $(dirname "$0")/uninstall-centos.sh
═══════════════════════════════════════════════════════════════════════════════
EOF
    chmod 600 "$CLIENT_CONFIG_FILE"
    log_success ".ovpn 已保存到 ${ovpn_file}"
}

main() {
    print_banner; echo ""; check_root; check_system; echo ""
    install_openvpn; setup_pki; echo ""
    generate_server_config; enable_ip_forward; echo ""
    start_openvpn; configure_firewall; echo ""
    generate_client_config
    echo -e "\n${GREEN}════════ 安装完成！════════${NC}\n"
    cat "$CLIENT_CONFIG_FILE"
}
main "$@"
