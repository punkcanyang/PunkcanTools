#!/bin/bash

#===============================================================================
# VLESS + Reality 一键安装脚本 (CentOS/RHEL 版本)
# 适用于 CentOS 7/8/9, RHEL, Rocky Linux, AlmaLinux
# 
# 功能：
#   - 安装 Xray-core
#   - 配置 VLESS + Reality
#   - 启用 BBR 加速
#   - 配置防火墙 (firewalld)
#   - 生成客户端配置
#   - 设置健康检查定时任务
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
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# 配置变量
#-------------------------------------------------------------------------------
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
CLIENT_CONFIG_FILE="${XRAY_CONFIG_DIR}/client-config.txt"
VLESS_LINK_FILE="${XRAY_CONFIG_DIR}/vless-link.txt"
QR_CODE_FILE="${XRAY_CONFIG_DIR}/vless-qrcode.png"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 默认配置
PORT=443
DEST="www.microsoft.com"
DEST_PORT=443

# 包管理器 (yum 或 dnf)
PKG_MANAGER=""

#-------------------------------------------------------------------------------
# 工具函数
#-------------------------------------------------------------------------------
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

# 进度指示器
show_progress() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        printf "\r${YELLOW}[%s]${NC} %s " "${spin:i++%10:1}" "$msg"
        sleep 0.1
    done
    printf "\r"
}

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║   VLESS + Reality 一键安装脚本 for CentOS/RHEL                ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

#-------------------------------------------------------------------------------
# 检查系统环境
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
    
    # 检测包管理器
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    else
        log_error "未找到 yum 或 dnf 包管理器"
        exit 1
    fi
    
    # 支持 CentOS, RHEL, Rocky, Alma
    case "$ID" in
        centos|rhel|rocky|almalinux|fedora)
            log_success "系统检查通过: $PRETTY_NAME (使用 $PKG_MANAGER)"
            ;;
        *)
            log_warn "此脚本针对 CentOS/RHEL 系统优化，当前系统: $ID"
            read -p "是否继续安装？(y/N): " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                exit 1
            fi
            ;;
    esac
}

check_network() {
    echo -ne "${YELLOW}[...]${NC} 测试网络连接..."
    if $PKG_MANAGER makecache -q > /dev/null 2>&1; then
        echo -e "\r${GREEN}[✓]${NC} 网络连接正常，软件源已更新    "
        return 0
    fi
    
    echo -e "\r${YELLOW}[!]${NC} 网络检测失败 (可能是 DNS 或防火墙问题)"
    read -p "是否继续安装？(y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_error "安装已取消"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# 检查端口是否可用
#-------------------------------------------------------------------------------
check_port() {
    log_info "检查端口 ${PORT} 是否可用..."
    
    # 检查端口是否被占用
    if ss -tlnp 2>/dev/null | grep -q ":${PORT} " || netstat -tlnp 2>/dev/null | grep -q ":${PORT} "; then
        log_warn "端口 ${PORT} 已被占用!"
        
        # 显示占用进程
        local process=$(ss -tlnp 2>/dev/null | grep ":${PORT} " | head -1 || netstat -tlnp 2>/dev/null | grep ":${PORT} " | head -1)
        log_info "占用进程: $process"
        
        # 自动切换到备用端口
        PORT=8443
        log_info "自动切换到备用端口: ${PORT}"
        
        # 检查备用端口
        if ss -tlnp 2>/dev/null | grep -q ":${PORT} " || netstat -tlnp 2>/dev/null | grep -q ":${PORT} "; then
            log_error "备用端口 ${PORT} 也被占用，请手动指定可用端口"
            exit 1
        fi
    fi
    
    log_success "将使用端口: ${PORT}"
}

#-------------------------------------------------------------------------------
# 安装 EPEL 仓库
#-------------------------------------------------------------------------------
install_epel() {
    log_info "检查 EPEL 仓库..."
    
    if rpm -q epel-release > /dev/null 2>&1; then
        log_success "EPEL 仓库已安装"
        return 0
    fi
    
    echo -ne "${YELLOW}[...]${NC} 安装 EPEL 仓库..."
    
    # CentOS 8+ / RHEL 8+ / Rocky / Alma
    if $PKG_MANAGER install -y epel-release > /dev/null 2>&1; then
        echo -e "\r${GREEN}[✓]${NC} EPEL 仓库安装成功    "
        return 0
    fi
    
    # 备用方法 (RHEL)
    source /etc/os-release
    local major_version=$(echo "$VERSION_ID" | cut -d. -f1)
    
    if $PKG_MANAGER install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${major_version}.noarch.rpm" > /dev/null 2>&1; then
        echo -e "\r${GREEN}[✓]${NC} EPEL 仓库安装成功    "
        return 0
    fi
    
    echo -e "\r${YELLOW}[!]${NC} EPEL 仓库安装失败，某些依赖可能无法安装"
}

#-------------------------------------------------------------------------------
# 安装依赖
#-------------------------------------------------------------------------------
install_dependencies() {
    log_info "安装必要依赖包..."
    
    # CentOS 使用 cronie 而非 cron
    local packages=("curl" "wget" "unzip" "jq" "openssl" "cronie" "qrencode")
    local total=${#packages[@]}
    local current=0
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    
    for pkg in "${packages[@]}"; do
        current=$((current + 1))
        
        if rpm -q "$pkg" > /dev/null 2>&1; then
            echo -e "${GREEN}[${current}/${total}]${NC} ${pkg} ${CYAN}(已安装)${NC}"
        else
            # 后台安装并显示动态进度
            $PKG_MANAGER install -y "$pkg" > /dev/null 2>&1 &
            local pid=$!
            local i=0
            
            while kill -0 $pid 2>/dev/null; do
                printf "\r${YELLOW}[${current}/${total}]${NC} 安装 ${pkg}... ${spin:i++%10:1} "
                sleep 0.1
            done
            
            wait $pid
            local result=$?
            
            if [[ $result -eq 0 ]]; then
                printf "\r${GREEN}[${current}/${total}]${NC} ${pkg} ${GREEN}✓${NC}              \n"
            else
                printf "\r${RED}[${current}/${total}]${NC} ${pkg} ${RED}失败${NC}          \n"
            fi
        fi
    done
    
    # 启用 cronie 服务
    systemctl enable crond > /dev/null 2>&1 || true
    systemctl start crond > /dev/null 2>&1 || true
    
    log_success "依赖安装完成"
}

#-------------------------------------------------------------------------------
# 安装 Xray-core
#-------------------------------------------------------------------------------
install_xray() {
    log_info "正在下载并安装 Xray-core (这可能需要几分钟)..."
    echo ""
    
    # 使用官方安装脚本 (显示输出)
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    echo ""
    if [[ ! -f /usr/local/bin/xray ]]; then
        log_error "Xray 安装失败"
        exit 1
    fi
    
    # 获取版本信息
    XRAY_VERSION=$(/usr/local/bin/xray version | head -n1 | awk '{print $2}')
    log_success "Xray ${XRAY_VERSION} 安装完成"
}

#-------------------------------------------------------------------------------
# 生成密钥和配置
#-------------------------------------------------------------------------------
generate_keys() {
    log_info "生成 Reality 密钥对..."
    
    # 生成 x25519 密钥对
    KEYS=$(/usr/local/bin/xray x25519)
    
    # 兼容新版 (25.x) 和旧版格式
    if echo "$KEYS" | grep -q "PrivateKey:"; then
        PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey:" | awk '{print $2}')
        PUBLIC_KEY=$(echo "$KEYS" | grep "Password:" | awk '{print $2}')
    else
        PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
        PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
    fi
    
    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
        log_error "密钥生成失败"
        exit 1
    fi
    
    # 生成 UUID
    UUID=$(cat /proc/sys/kernel/random/uuid)
    
    # 生成 Short ID
    SHORT_ID=$(openssl rand -hex 4)
    
    log_success "密钥生成完成"
    log_info "Private Key: ${PRIVATE_KEY:0:10}..."
    log_info "Public Key: ${PUBLIC_KEY:0:10}..."
}

generate_xray_config() {
    log_info "生成 Xray 配置文件..."
    
    mkdir -p "$XRAY_CONFIG_DIR"
    
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
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "${DEST}:${DEST_PORT}",
                    "xver": 0,
                    "serverNames": [
                        "${DEST}"
                    ],
                    "privateKey": "${PRIVATE_KEY}",
                    "shortIds": [
                        "${SHORT_ID}"
                    ]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
}
EOF

    mkdir -p /var/log/xray
    
    log_success "Xray 配置文件生成完成"
}

#-------------------------------------------------------------------------------
# 配置服务
#-------------------------------------------------------------------------------
configure_service() {
    log_info "配置 Xray 服务..."
    
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

#-------------------------------------------------------------------------------
# 配置防火墙 (firewalld)
#-------------------------------------------------------------------------------
configure_firewall() {
    log_info "配置防火墙..."
    
    # 检测防火墙类型
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        # 使用 firewalld
        firewall-cmd --permanent --add-port=${PORT}/tcp > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        log_success "firewalld 防火墙已配置，端口 ${PORT} 已开放"
    elif command -v iptables &> /dev/null; then
        # 使用 iptables
        iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
        
        # 保存规则 (CentOS 7)
        if command -v iptables-save &> /dev/null; then
            iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
        fi
        
        # 使用 iptables-services (如果安装)
        if systemctl is-active --quiet iptables 2>/dev/null; then
            service iptables save 2>/dev/null || true
        fi
        
        log_success "iptables 防火墙已配置，端口 ${PORT} 已开放"
    else
        log_warn "未检测到活动的防火墙，跳过配置"
        log_info "如需手动开放端口，请运行:"
        echo "  firewall-cmd --permanent --add-port=${PORT}/tcp && firewall-cmd --reload"
    fi
}

#-------------------------------------------------------------------------------
# 启用 BBR
#-------------------------------------------------------------------------------
enable_bbr() {
    log_info "启用 BBR 拥塞控制..."
    
    KERNEL_VERSION=$(uname -r | cut -d. -f1,2)
    KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
    KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)
    
    if [[ "$KERNEL_MAJOR" -lt 4 ]] || [[ "$KERNEL_MAJOR" -eq 4 && "$KERNEL_MINOR" -lt 9 ]]; then
        log_warn "内核版本 ${KERNEL_VERSION} 不支持 BBR (需要 4.9+)"
        log_info "CentOS 7 用户可考虑升级内核: yum install elrepo-release && yum --enablerepo=elrepo-kernel install kernel-ml"
        return
    fi
    
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        log_success "BBR 已经启用"
        return
    fi
    
    cat >> /etc/sysctl.conf << EOF

# BBR 拥塞控制
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    
    sysctl -p > /dev/null 2>&1
    
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        log_success "BBR 启用成功"
    else
        log_warn "BBR 启用可能需要重启系统"
    fi
}

#-------------------------------------------------------------------------------
# 配置健康检查定时任务
#-------------------------------------------------------------------------------
setup_health_check() {
    log_info "配置健康检查定时任务..."
    
    if [[ -f "${SCRIPT_DIR}/health-check.sh" ]]; then
        cp "${SCRIPT_DIR}/health-check.sh" /usr/local/bin/xray-health-check.sh
        chmod +x /usr/local/bin/xray-health-check.sh
        
        (crontab -l 2>/dev/null | grep -v "xray-health-check"; echo "0 * * * * /usr/local/bin/xray-health-check.sh >> /var/log/xray/health-check.log 2>&1") | crontab -
        
        log_success "健康检查定时任务已配置 (每小时执行)"
    else
        log_warn "未找到 health-check.sh，跳过定时任务配置"
    fi
}

#-------------------------------------------------------------------------------
# 安装管理脚本
#-------------------------------------------------------------------------------
install_scripts() {
    log_info "安装管理脚本..."
    
    if [[ -f "${SCRIPT_DIR}/show-config.sh" ]]; then
        cp "${SCRIPT_DIR}/show-config.sh" /usr/local/bin/xray-show-config
        chmod +x /usr/local/bin/xray-show-config
        log_success "配置查看脚本已安装: xray-show-config"
    fi
    
    if [[ -f "${SCRIPT_DIR}/uninstall-centos.sh" ]]; then
        cp "${SCRIPT_DIR}/uninstall-centos.sh" /usr/local/bin/xray-uninstall.sh
        chmod +x /usr/local/bin/xray-uninstall.sh
        log_success "卸载脚本已安装: xray-uninstall.sh"
    fi
}

#-------------------------------------------------------------------------------
# 生成客户端配置
#-------------------------------------------------------------------------------
generate_client_config() {
    log_info "生成客户端配置..."
    
    SERVER_IP=$(curl -s4 ifconfig.me || curl -s4 ip.sb || curl -s4 ipinfo.io/ip)
    
    if [[ -z "$SERVER_IP" ]]; then
        log_warn "无法获取公网 IP，请手动替换配置中的 SERVER_IP"
        SERVER_IP="YOUR_SERVER_IP"
    fi
    
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#VLESS-Reality"
    
    echo -n "$VLESS_LINK" > "$VLESS_LINK_FILE"
    log_success "VLESS 分享链接已保存到 ${VLESS_LINK_FILE}"
    
    if command -v qrencode &> /dev/null; then
        qrencode -o "$QR_CODE_FILE" -s 10 -m 2 "$VLESS_LINK"
        log_success "二维码图片已保存到 ${QR_CODE_FILE}"
    fi
    
    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                         VLESS + Reality 客户端配置
═══════════════════════════════════════════════════════════════════════════════

服务器地址: ${SERVER_IP}
端口: ${PORT}
UUID: ${UUID}
Flow: xtls-rprx-vision
传输协议: tcp
安全类型: reality
SNI: ${DEST}
Public Key: ${PUBLIC_KEY}
Short ID: ${SHORT_ID}
指纹: chrome

───────────────────────────────────────────────────────────────────────────────
                              VLESS 分享链接
───────────────────────────────────────────────────────────────────────────────

${VLESS_LINK}

───────────────────────────────────────────────────────────────────────────────
                            V2rayN / Clash 配置
───────────────────────────────────────────────────────────────────────────────

{
    "type": "vless",
    "tag": "VLESS-Reality",
    "server": "${SERVER_IP}",
    "server_port": ${PORT},
    "uuid": "${UUID}",
    "flow": "xtls-rprx-vision",
    "tls": {
        "enabled": true,
        "server_name": "${DEST}",
        "utls": {
            "enabled": true,
            "fingerprint": "chrome"
        },
        "reality": {
            "enabled": true,
            "public_key": "${PUBLIC_KEY}",
            "short_id": "${SHORT_ID}"
        }
    }
}

═══════════════════════════════════════════════════════════════════════════════
                                 重要提示
═══════════════════════════════════════════════════════════════════════════════

1. 请将上述配置导入到您的代理客户端 (V2rayN, Clash, Shadowrocket 等)
2. 扫描二维码或复制链接: xray-show-config --qr
3. 查看纯链接: cat ${VLESS_LINK_FILE}
4. 配置文件保存位置: ${CLIENT_CONFIG_FILE}
5. 查看服务状态: systemctl status xray
6. 查看日志: journalctl -u xray -f
7. 卸载命令: bash /usr/local/bin/xray-uninstall.sh

═══════════════════════════════════════════════════════════════════════════════
EOF

    log_success "完整配置已保存到 ${CLIENT_CONFIG_FILE}"
}

print_client_config() {
    echo ""
    cat "$CLIENT_CONFIG_FILE"
    echo ""
}

#-------------------------------------------------------------------------------
# 主函数
#-------------------------------------------------------------------------------
main() {
    print_banner
    
    echo ""
    log_info "开始安装 VLESS + Reality..."
    echo ""
    
    # 系统检查
    check_root
    check_system
    check_network
    check_port
    
    echo ""
    
    # 安装 EPEL (CentOS 需要)
    install_epel
    
    echo ""
    
    # 安装过程
    install_dependencies
    install_xray
    
    echo ""
    
    # 生成配置
    generate_keys
    generate_xray_config
    
    echo ""
    
    # 配置服务和系统
    configure_service
    configure_firewall
    enable_bbr
    setup_health_check
    install_scripts
    
    echo ""
    
    # 生成客户端配置
    generate_client_config
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    安装完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    
    print_client_config
}

# 执行主函数
main "$@"
