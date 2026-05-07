#!/bin/bash

#===============================================================================
# IPsec/L2TP 一键安装脚本
# 适用于 Debian/Ubuntu 系统
#
# __ai_context__:
#   IPsec/L2TP 是兼容性最广的 VPN 方案，Windows/macOS/iOS/Android 均原生支持。
#   使用 StrongSwan (IPsec) + xl2tpd (L2TP) 实现。
#   通过预共享密钥 (PSK) 认证，配置最简单。
#
# 功能：
#   - 安装 StrongSwan + xl2tpd
#   - 使用 PSK (预共享密钥) 认证
#   - 配置 L2TP over IPsec
#   - 生成所有平台的连接参数
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CLIENT_CONFIG_FILE="/etc/ipsec.d/client-config-l2tp.txt"

# VPN 配置
VPN_LOCAL_IP="10.55.55.1"
VPN_REMOTE_RANGE="10.55.55.10-10.55.55.250"
VPN_DNS="1.1.1.1"

# 认证配置
PSK=""
VPN_USER="vpnuser"
VPN_PASSWORD=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../lib/firewall-ssh-guard.sh"

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║       IPsec/L2TP 一键安装脚本 for Debian/Ubuntu                ║"
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
# 安装组件
#-------------------------------------------------------------------------------
install_packages() {
    log_info "安装 StrongSwan 和 xl2tpd..."
    apt-get update > /dev/null 2>&1
    apt-get install -y strongswan xl2tpd ppp curl openssl iproute2 iptables procps > /dev/null 2>&1
    log_success "安装完成"
}

#-------------------------------------------------------------------------------
# 生成配置
#-------------------------------------------------------------------------------
generate_config() {
    log_info "生成配置..."

    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")

    # 生成随机密钥和密码
    PSK=$(openssl rand -base64 20)
    VPN_PASSWORD=$(openssl rand -base64 12)

    mkdir -p /etc/ipsec.d

    # IPsec 配置 (ipsec.conf)
    cat > /etc/ipsec.conf << EOF
# IPsec/L2TP 配置
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

    # IPsec 密钥 (ipsec.secrets)
    cat > /etc/ipsec.secrets << EOF
# IPsec PSK (预共享密钥)
: PSK "${PSK}"
EOF
    chmod 600 /etc/ipsec.secrets

    # L2TP 配置 (xl2tpd.conf)
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

    # PPP 选项
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

    # PPP 用户认证
    cat > /etc/ppp/chap-secrets << EOF
# client    server    password    IP
${VPN_USER}    l2tpd    ${VPN_PASSWORD}    *
EOF
    chmod 600 /etc/ppp/chap-secrets

    log_success "配置完成"
}

#-------------------------------------------------------------------------------
# 启用 IP 转发
#-------------------------------------------------------------------------------
enable_ip_forward() {
    log_info "启用 IP 转发..."
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1

    local main_interface
    main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    [[ -z "$main_interface" ]] && main_interface="eth0"

    iptables -t nat -A POSTROUTING -s 10.55.55.0/24 -o ${main_interface} -j MASQUERADE
    iptables -A FORWARD -s 10.55.55.0/24 -j ACCEPT
    iptables -A FORWARD -d 10.55.55.0/24 -j ACCEPT

    # 允许 IPsec 端口
    ensure_ssh_iptables_rules
    iptables -C INPUT -p udp --dport 500 -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p udp --dport 500 -j ACCEPT
    iptables -C INPUT -p udp --dport 4500 -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p udp --dport 4500 -j ACCEPT
    iptables -C INPUT -p udp --dport 1701 -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p udp --dport 1701 -j ACCEPT

    log_success "IP 转发和 NAT 已配置，SSH 端口已保留"
}

#-------------------------------------------------------------------------------
# 启动服务
#-------------------------------------------------------------------------------
start_services() {
    log_info "启动服务..."

    systemctl enable strongswan-starter 2>/dev/null || systemctl enable strongswan 2>/dev/null || true
    systemctl restart strongswan-starter 2>/dev/null || systemctl restart strongswan 2>/dev/null || ipsec restart

    systemctl enable xl2tpd
    systemctl restart xl2tpd
    sleep 2

    local ipsec_ok=false
    local l2tp_ok=false

    if ipsec status > /dev/null 2>&1; then
        ipsec_ok=true
        log_success "IPsec (StrongSwan) 启动成功"
    else
        log_error "IPsec 启动失败"
    fi

    if systemctl is-active --quiet xl2tpd; then
        l2tp_ok=true
        log_success "L2TP (xl2tpd) 启动成功"
    else
        log_error "L2TP 启动失败"
    fi

    if [[ "$ipsec_ok" != "true" || "$l2tp_ok" != "true" ]]; then
        log_error "某些服务启动失败，请检查日志"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# 生成客户端配置
#-------------------------------------------------------------------------------
generate_client_config() {
    log_info "生成客户端配置..."

    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")

    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                     IPsec/L2TP 客户端配置
═══════════════════════════════════════════════════════════════════════════════

服务器地址: ${server_ip}
VPN 类型: L2TP/IPsec PSK
预共享密钥 (PSK): ${PSK}
用户名: ${VPN_USER}
密码: ${VPN_PASSWORD}

───────────────────────────────────────────────────────────────────────────────
                         iOS 配置步骤
───────────────────────────────────────────────────────────────────────────────

设置 → 通用 → VPN → 添加 VPN 配置
  - 类型: L2TP
  - 服务器: ${server_ip}
  - 帐户: ${VPN_USER}
  - 密码: ${VPN_PASSWORD}
  - 密钥: ${PSK}

───────────────────────────────────────────────────────────────────────────────
                       macOS 配置步骤
───────────────────────────────────────────────────────────────────────────────

系统偏好设置 → 网络 → + → VPN
  - 接口: VPN
  - VPN 类型: L2TP over IPSec
  - 服务器地址: ${server_ip}
  - 帐户名称: ${VPN_USER}
  - 鉴定设置:
    - 密码: ${VPN_PASSWORD}
    - 共享密钥: ${PSK}

───────────────────────────────────────────────────────────────────────────────
                       Windows 配置步骤
───────────────────────────────────────────────────────────────────────────────

设置 → 网络 → VPN → 添加 VPN
  - VPN 提供商: Windows (内置)
  - VPN 类型: 使用预共享密钥的 L2TP/IPsec
  - 服务器: ${server_ip}
  - 预共享密钥: ${PSK}
  - 用户名: ${VPN_USER}
  - 密码: ${VPN_PASSWORD}

───────────────────────────────────────────────────────────────────────────────
                       Android 配置步骤
───────────────────────────────────────────────────────────────────────────────

设置 → 网络 → VPN → 添加
  - 类型: L2TP/IPSec PSK
  - 服务器: ${server_ip}
  - IPSec 预共享密钥: ${PSK}
  - 用户名: ${VPN_USER}
  - 密码: ${VPN_PASSWORD}

───────────────────────────────────────────────────────────────────────────────
                              重要提示
───────────────────────────────────────────────────────────────────────────────

1. 所有主流操作系统都原生支持 L2TP/IPsec，无需安装额外软件
2. 端口: UDP 500 + UDP 4500 + UDP 1701
3. 服务状态: ipsec status && systemctl status xl2tpd
4. 卸载: bash $(dirname "$0")/uninstall.sh

═══════════════════════════════════════════════════════════════════════════════
EOF
    chmod 600 "$CLIENT_CONFIG_FILE"

    log_success "配置已保存到 ${CLIENT_CONFIG_FILE}"
}

main() {
    print_banner
    echo ""
    check_root
    check_system
    echo ""
    install_packages
    generate_config
    echo ""
    enable_ip_forward
    start_services
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
# 1. IPsec/L2TP 使用 StrongSwan + xl2tpd + ppp
# 2. 使用 PSK 认证（最简单，兼容性最广）
# 3. 使用 IKEv1 (keyexchange=ikev1) 兼容旧设备
# 4. L2TP 端口 1701 + IPsec 端口 500/4500
# 5. PPP 认证使用 MSCHAPv2
# 6. 使用 10.55.55.0/24 子网避免与其他 VPN 冲突
