#!/bin/bash

#===============================================================================
# IKEv2 (StrongSwan) 一键安装脚本
# 适用于 Debian/Ubuntu 系统
#
# __ai_context__:
#   IKEv2 是 iOS/macOS/Windows 10+ 原生支持的 VPN 协议。
#   使用 StrongSwan 实现，自建 CA 签发服务器/客户端证书。
#   特别适合 Apple 设备用户，可直接在系统设置中配置。
#
# 功能：
#   - 安装 StrongSwan
#   - 自建 CA + 服务器证书
#   - 配置 IKEv2 VPN
#   - 生成 iOS .mobileconfig 和连接参数
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

IPSEC_DIR="/etc/ipsec.d"
STRONGSWAN_DIR="/etc/strongswan"
CLIENT_DIR="${IPSEC_DIR}/clients"
CLIENT_CONFIG_FILE="${IPSEC_DIR}/client-config.txt"

# VPN 配置
VPN_SUBNET="10.10.10.0/24"
VPN_DNS="1.1.1.1,8.8.8.8"

# 证书相关
CA_CN="VPN CA"
SERVER_CN=""
VPN_USER="vpnuser"
VPN_PASSWORD=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║     IKEv2 (StrongSwan) 一键安装脚本 for Debian/Ubuntu         ║"
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
# 安装 StrongSwan
#-------------------------------------------------------------------------------
install_strongswan() {
    log_info "安装 StrongSwan..."
    apt-get update > /dev/null 2>&1
    apt-get install -y strongswan strongswan-pki libcharon-extra-plugins > /dev/null 2>&1

    if ! command -v ipsec &> /dev/null; then
        log_error "StrongSwan 安装失败"
        exit 1
    fi
    log_success "StrongSwan 安装完成"
}

#-------------------------------------------------------------------------------
# 生成证书
#-------------------------------------------------------------------------------
generate_certificates() {
    log_info "生成 CA 和服务器证书..."

    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")
    SERVER_CN="$server_ip"

    mkdir -p "${IPSEC_DIR}/private" "${IPSEC_DIR}/cacerts" "${IPSEC_DIR}/certs" "$CLIENT_DIR"

    # 生成 CA 私钥和证书
    ipsec pki --gen --type ec --size 256 --outform pem \
        > "${IPSEC_DIR}/private/ca-key.pem"

    ipsec pki --self --ca --lifetime 3650 \
        --in "${IPSEC_DIR}/private/ca-key.pem" \
        --dn "CN=${CA_CN}" \
        --outform pem \
        > "${IPSEC_DIR}/cacerts/ca-cert.pem"

    log_success "CA 证书生成完成"

    # 生成服务器私钥和证书
    ipsec pki --gen --type ec --size 256 --outform pem \
        > "${IPSEC_DIR}/private/server-key.pem"

    ipsec pki --pub --in "${IPSEC_DIR}/private/server-key.pem" --outform pem \
        | ipsec pki --issue --lifetime 3650 \
            --cacert "${IPSEC_DIR}/cacerts/ca-cert.pem" \
            --cakey "${IPSEC_DIR}/private/ca-key.pem" \
            --dn "CN=${SERVER_CN}" \
            --san "${SERVER_CN}" \
            --flag serverAuth --flag ikeIntermediate \
            --outform pem \
        > "${IPSEC_DIR}/certs/server-cert.pem"

    # 设置权限
    chmod 600 "${IPSEC_DIR}/private/"*.pem

    log_success "服务器证书生成完成"
}

#-------------------------------------------------------------------------------
# 生成 StrongSwan 配置
#-------------------------------------------------------------------------------
generate_config() {
    log_info "生成 StrongSwan 配置..."

    # 生成 VPN 用户密码
    VPN_PASSWORD=$(openssl rand -base64 16)

    # ipsec.conf
    cat > /etc/ipsec.conf << EOF
# StrongSwan IKEv2 配置
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn ikev2-vpn
    auto=add
    type=tunnel
    keyexchange=ikev2

    # 服务端设置
    left=%any
    leftid=${SERVER_CN}
    leftcert=server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0

    # 客户端设置
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=${VPN_SUBNET}
    rightdns=${VPN_DNS}
    rightsendcert=never

    # 加密套件
    ike=aes256-sha256-modp2048,aes256-sha256-ecp256!
    esp=aes256-sha256!

    # 其他
    dpdaction=clear
    dpddelay=300s
    rekey=no
    fragmentation=yes
    eap_identity=%identity
EOF

    # ipsec.secrets
    cat > /etc/ipsec.secrets << EOF
# StrongSwan 密钥配置
: ECDSA server-key.pem
${VPN_USER} : EAP "${VPN_PASSWORD}"
EOF

    chmod 600 /etc/ipsec.secrets
    log_success "配置完成"
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

    local main_interface
    main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    [[ -z "$main_interface" ]] && main_interface="eth0"

    iptables -t nat -A POSTROUTING -s ${VPN_SUBNET} -o ${main_interface} -j MASQUERADE
    iptables -A FORWARD -s ${VPN_SUBNET} -j ACCEPT

    log_success "IP 转发和 NAT 配置完成"
}

#-------------------------------------------------------------------------------
# 启动服务
#-------------------------------------------------------------------------------
start_service() {
    log_info "启动 StrongSwan..."
    systemctl enable strongswan-starter 2>/dev/null || systemctl enable strongswan 2>/dev/null || true
    systemctl restart strongswan-starter 2>/dev/null || systemctl restart strongswan 2>/dev/null || ipsec restart

    sleep 2
    if ipsec status > /dev/null 2>&1; then
        log_success "StrongSwan 启动成功"
    else
        log_error "StrongSwan 启动失败"
        exit 1
    fi
}

configure_firewall() {
    if command -v ufw &> /dev/null; then
        ufw allow 500/udp > /dev/null 2>&1 || true
        ufw allow 4500/udp > /dev/null 2>&1 || true
        log_success "UFW 已开放 500/udp 和 4500/udp"
    elif command -v iptables &> /dev/null; then
        iptables -I INPUT -p udp --dport 500 -j ACCEPT
        iptables -I INPUT -p udp --dport 4500 -j ACCEPT
        log_success "iptables 已开放端口"
    fi
}

#-------------------------------------------------------------------------------
# 生成客户端配置
#-------------------------------------------------------------------------------
generate_client_config() {
    log_info "生成客户端配置..."

    local server_ip="$SERVER_CN"

    # 复制 CA 证书供客户端下载
    cp "${IPSEC_DIR}/cacerts/ca-cert.pem" "${CLIENT_DIR}/ca-cert.pem"

    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                     IKEv2 (StrongSwan) 客户端配置
═══════════════════════════════════════════════════════════════════════════════

服务器地址: ${server_ip}
VPN 类型: IKEv2
认证方式: EAP (用户名/密码)
用户名: ${VPN_USER}
密码: ${VPN_PASSWORD}

CA 证书: ${CLIENT_DIR}/ca-cert.pem

───────────────────────────────────────────────────────────────────────────────
                        iOS / macOS 配置步骤
───────────────────────────────────────────────────────────────────────────────

1. 下载 CA 证书到设备:
   scp root@${server_ip}:${CLIENT_DIR}/ca-cert.pem ./

2. iOS: 设置 → 通用 → VPN → 添加 VPN 配置
   - 类型: IKEv2
   - 服务器: ${server_ip}
   - 远程 ID: ${server_ip}
   - 用户鉴定: 用户名
   - 用户名: ${VPN_USER}
   - 密码: ${VPN_PASSWORD}

3. macOS: 系统偏好设置 → 网络 → + → VPN → IKEv2
   - 服务器地址: ${server_ip}
   - 远程 ID: ${server_ip}
   - 鉴定设置 → 用户名: ${VPN_USER} / 密码: ${VPN_PASSWORD}

注意: 需先安装 CA 证书并信任

───────────────────────────────────────────────────────────────────────────────
                       Windows 10/11 配置步骤
───────────────────────────────────────────────────────────────────────────────

1. 导入 CA 证书到 "受信任的根证书颁发机构"
2. 设置 → 网络和 Internet → VPN → 添加 VPN
   - VPN 提供商: Windows (内置)
   - 连接名称: IKEv2-VPN
   - 服务器名称: ${server_ip}
   - VPN 类型: IKEv2
   - 登录信息: 用户名和密码
   - 用户名: ${VPN_USER}
   - 密码: ${VPN_PASSWORD}

───────────────────────────────────────────────────────────────────────────────
                              重要提示
───────────────────────────────────────────────────────────────────────────────

1. 客户端必须安装并信任 CA 证书
2. iOS/macOS 原生支持 IKEv2，无需额外 App
3. 服务状态: ipsec status
4. 查看日志: journalctl -u strongswan-starter -f
5. 卸载: bash $(dirname "$0")/uninstall.sh

═══════════════════════════════════════════════════════════════════════════════
EOF

    log_success "配置已保存到 ${CLIENT_CONFIG_FILE}"
}

main() {
    print_banner
    echo ""
    check_root
    check_system
    echo ""
    install_strongswan
    generate_certificates
    echo ""
    generate_config
    enable_ip_forward
    echo ""
    start_service
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
# 1. IKEv2 使用 StrongSwan 实现
# 2. 使用 EAP-MSCHAPv2 用户名密码认证（最易配置）
# 3. 需要在客户端安装并信任自建 CA 证书
# 4. iOS/macOS/Windows 10+ 原生支持 IKEv2
# 5. 端口 500/UDP + 4500/UDP
# 6. 依赖 libcharon-extra-plugins 提供 EAP 支持
