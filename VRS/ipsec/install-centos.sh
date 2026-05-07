#!/bin/bash

#===============================================================================
# IPsec/L2TP 一键安装脚本 (CentOS/RHEL 版本)
#===============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

CLIENT_CONFIG_FILE="/etc/ipsec.d/client-config-l2tp.txt"
VPN_LOCAL_IP="10.55.55.1"
VPN_REMOTE_RANGE="10.55.55.10-10.55.55.250"
VPN_DNS="1.1.1.1"
PSK=""; VPN_USER="vpnuser"; VPN_PASSWORD=""
PKG_MANAGER=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }; log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }; log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../lib/firewall-ssh-guard.sh"

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║     IPsec/L2TP 一键安装脚本 for CentOS/RHEL                    ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() { [[ $EUID -ne 0 ]] && { log_error "需要 root 权限"; exit 1; }; log_success "Root OK"; }
check_system() {
    source /etc/os-release 2>/dev/null; command -v dnf &> /dev/null && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
    log_success "系统: $PRETTY_NAME ($PKG_MANAGER)"
}

install_packages() {
    log_info "安装 StrongSwan 和 xl2tpd..."
    $PKG_MANAGER install -y epel-release > /dev/null 2>&1 || true
    $PKG_MANAGER install -y strongswan xl2tpd ppp curl openssl iproute iptables procps-ng > /dev/null 2>&1
    log_success "安装完成"
}

generate_config() {
    log_info "生成配置..."
    PSK=$(openssl rand -base64 20)
    VPN_PASSWORD=$(openssl rand -base64 12)
    mkdir -p /etc/ipsec.d

    cat > /etc/ipsec.conf << EOF
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn l2tp-psk
    auto=add
    keyexchange=ikev1
    type=transport
    left=%defaultroute
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    authby=secret
    rekey=no
    forceencaps=yes
EOF

    cat > /etc/ipsec.secrets << EOF
: PSK "${PSK}"
EOF
    chmod 600 /etc/ipsec.secrets

    cat > /etc/xl2tpd/xl2tpd.conf << EOF
[global]
port = 1701
[lns default]
ip range = ${VPN_REMOTE_RANGE}
local ip = ${VPN_LOCAL_IP}
require chap = yes
refuse pap = yes
require authentication = yes
name = L2TP-VPN
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

    cat > /etc/ppp/options.xl2tpd << EOF
ipcp-accept-local
ipcp-accept-remote
require-mschap-v2
ms-dns ${VPN_DNS}
noccp
auth
mtu 1280
mru 1280
proxyarp
connect-delay 5000
EOF

    cat > /etc/ppp/chap-secrets << EOF
${VPN_USER}    l2tpd    ${VPN_PASSWORD}    *
EOF
    chmod 600 /etc/ppp/chap-secrets
    log_success "配置完成"
}

enable_ip_forward() {
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1

    local main_interface; main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    [[ -z "$main_interface" ]] && main_interface="eth0"

    iptables -t nat -A POSTROUTING -s 10.55.55.0/24 -o ${main_interface} -j MASQUERADE
    iptables -A FORWARD -s 10.55.55.0/24 -j ACCEPT
    iptables -A FORWARD -d 10.55.55.0/24 -j ACCEPT
    ensure_ssh_iptables_rules
    iptables -C INPUT -p udp --dport 500 -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p udp --dport 500 -j ACCEPT
    iptables -C INPUT -p udp --dport 4500 -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p udp --dport 4500 -j ACCEPT
    iptables -C INPUT -p udp --dport 1701 -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p udp --dport 1701 -j ACCEPT
    log_success "IP 转发和 NAT 已配置，SSH 端口已保留"
}

start_services() {
    systemctl enable strongswan 2>/dev/null || true
    systemctl restart strongswan 2>/dev/null || ipsec restart
    systemctl enable xl2tpd; systemctl restart xl2tpd
    sleep 2
    ipsec status > /dev/null 2>&1 && log_success "IPsec 启动成功" || log_error "IPsec 启动失败"
    systemctl is-active --quiet xl2tpd && log_success "L2TP 启动成功" || log_error "L2TP 启动失败"
}

configure_firewall() {
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        ensure_ssh_firewalld_rules
        firewall-cmd --permanent --add-port=500/udp --add-port=4500/udp --add-port=1701/udp > /dev/null 2>&1
        firewall-cmd --permanent --add-masquerade > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        log_success "firewalld 已配置，SSH 端口已保留"
    fi
}

generate_client_config() {
    local server_ip; server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")
    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                  IPsec/L2TP 客户端配置 (CentOS)
═══════════════════════════════════════════════════════════════════════════════
服务器: ${server_ip} | VPN 类型: L2TP/IPsec PSK
预共享密钥: ${PSK}
用户名: ${VPN_USER} | 密码: ${VPN_PASSWORD}

── iOS: 设置 → VPN → L2TP → 服务器=${server_ip}, 帐户=${VPN_USER}, 密钥=${PSK}
── macOS: 网络 → VPN → L2TP over IPSec
── Windows: VPN → L2TP/IPsec (预共享密钥)
── Android: VPN → L2TP/IPSec PSK

服务状态: ipsec status && systemctl status xl2tpd
卸载: bash $(dirname "$0")/uninstall-centos.sh
═══════════════════════════════════════════════════════════════════════════════
EOF
    chmod 600 "$CLIENT_CONFIG_FILE"
    log_success "配置已保存"
}

main() {
    print_banner; echo ""; check_root; check_system; echo ""
    install_packages; generate_config; echo ""
    enable_ip_forward; start_services; configure_firewall; echo ""
    generate_client_config
    echo -e "\n${GREEN}════════ 安装完成！════════${NC}\n"
    cat "$CLIENT_CONFIG_FILE"
}
main "$@"
