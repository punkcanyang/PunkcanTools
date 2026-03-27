#!/bin/bash

#===============================================================================
# IKEv2 (StrongSwan) 一键安装脚本 (CentOS/RHEL 版本)
#===============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

IPSEC_DIR="/etc/ipsec.d"
CLIENT_DIR="${IPSEC_DIR}/clients"
CLIENT_CONFIG_FILE="${IPSEC_DIR}/client-config.txt"
VPN_SUBNET="10.10.10.0/24"
VPN_DNS="1.1.1.1,8.8.8.8"
CA_CN="VPN CA"
SERVER_CN=""
VPN_USER="vpnuser"
VPN_PASSWORD=""
PKG_MANAGER=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }; log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }; log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║   IKEv2 (StrongSwan) 安装脚本 for CentOS/RHEL                ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() { [[ $EUID -ne 0 ]] && { log_error "需要 root 权限"; exit 1; }; log_success "Root OK"; }
check_system() {
    source /etc/os-release 2>/dev/null; command -v dnf &> /dev/null && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
    log_success "系统: $PRETTY_NAME ($PKG_MANAGER)"
}

install_strongswan() {
    log_info "安装 StrongSwan..."
    $PKG_MANAGER install -y epel-release > /dev/null 2>&1 || true
    $PKG_MANAGER install -y strongswan > /dev/null 2>&1
    command -v ipsec &> /dev/null || $PKG_MANAGER install -y strongswan > /dev/null 2>&1
    command -v ipsec &> /dev/null || { log_error "StrongSwan 安装失败"; exit 1; }
    log_success "StrongSwan 安装完成"
}

generate_certificates() {
    log_info "生成证书..."
    local server_ip; server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")
    SERVER_CN="$server_ip"
    mkdir -p "${IPSEC_DIR}/private" "${IPSEC_DIR}/cacerts" "${IPSEC_DIR}/certs" "$CLIENT_DIR"

    ipsec pki --gen --type ec --size 256 --outform pem > "${IPSEC_DIR}/private/ca-key.pem"
    ipsec pki --self --ca --lifetime 3650 --in "${IPSEC_DIR}/private/ca-key.pem" \
        --dn "CN=${CA_CN}" --outform pem > "${IPSEC_DIR}/cacerts/ca-cert.pem"
    log_success "CA 证书完成"

    ipsec pki --gen --type ec --size 256 --outform pem > "${IPSEC_DIR}/private/server-key.pem"
    ipsec pki --pub --in "${IPSEC_DIR}/private/server-key.pem" --outform pem \
        | ipsec pki --issue --lifetime 3650 \
            --cacert "${IPSEC_DIR}/cacerts/ca-cert.pem" --cakey "${IPSEC_DIR}/private/ca-key.pem" \
            --dn "CN=${SERVER_CN}" --san "${SERVER_CN}" \
            --flag serverAuth --flag ikeIntermediate --outform pem \
        > "${IPSEC_DIR}/certs/server-cert.pem"
    chmod 600 "${IPSEC_DIR}/private/"*.pem
    log_success "服务器证书完成"
}

generate_config() {
    VPN_PASSWORD=$(openssl rand -base64 16)
    cat > /etc/ipsec.conf << EOF
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn ikev2-vpn
    auto=add
    type=tunnel
    keyexchange=ikev2
    left=%any
    leftid=${SERVER_CN}
    leftcert=server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=${VPN_SUBNET}
    rightdns=${VPN_DNS}
    rightsendcert=never
    ike=aes256-sha256-modp2048,aes256-sha256-ecp256!
    esp=aes256-sha256!
    dpdaction=clear
    dpddelay=300s
    rekey=no
    fragmentation=yes
    eap_identity=%identity
EOF

    cat > /etc/ipsec.secrets << EOF
: ECDSA server-key.pem
${VPN_USER} : EAP "${VPN_PASSWORD}"
EOF
    chmod 600 /etc/ipsec.secrets
    log_success "配置完成"
}

enable_ip_forward() {
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
    local main_interface; main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    [[ -z "$main_interface" ]] && main_interface="eth0"
    iptables -t nat -A POSTROUTING -s ${VPN_SUBNET} -o ${main_interface} -j MASQUERADE
    iptables -A FORWARD -s ${VPN_SUBNET} -j ACCEPT
    log_success "IP 转发已配置"
}

start_service() {
    systemctl enable strongswan 2>/dev/null || true
    systemctl restart strongswan 2>/dev/null || ipsec restart
    sleep 2
    ipsec status > /dev/null 2>&1 && log_success "StrongSwan 启动成功" || { log_error "启动失败"; exit 1; }
}

configure_firewall() {
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=500/udp --add-port=4500/udp > /dev/null 2>&1
        firewall-cmd --permanent --add-masquerade > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        log_success "firewalld 已配置"
    fi
}

generate_client_config() {
    cp "${IPSEC_DIR}/cacerts/ca-cert.pem" "${CLIENT_DIR}/ca-cert.pem"
    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                  IKEv2 (StrongSwan) 客户端配置 (CentOS)
═══════════════════════════════════════════════════════════════════════════════
服务器: ${SERVER_CN} | 认证: EAP (用户名/密码)
用户名: ${VPN_USER} | 密码: ${VPN_PASSWORD}
CA 证书: ${CLIENT_DIR}/ca-cert.pem

iOS: 设置 → VPN → IKEv2 → 服务器=${SERVER_CN}, 远程ID=${SERVER_CN}
macOS: 网络 → VPN → IKEv2

注意: 需先安装并信任 CA 证书
服务状态: ipsec status
卸载: bash $(dirname "$0")/uninstall-centos.sh
═══════════════════════════════════════════════════════════════════════════════
EOF
    log_success "配置已保存"
}

main() {
    print_banner; echo ""; check_root; check_system; echo ""
    install_strongswan; generate_certificates; echo ""
    generate_config; enable_ip_forward; echo ""
    start_service; configure_firewall; echo ""
    generate_client_config
    echo -e "\n${GREEN}════════ 安装完成！════════${NC}\n"
    cat "$CLIENT_CONFIG_FILE"
}
main "$@"
