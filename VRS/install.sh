#!/bin/bash

#===============================================================================
# VLESS + Reality 一键安装脚本
# 适用于 Debian 12 系统
# 
# 功能：
#   - 安装 Xray-core
#   - 配置 VLESS + Reality
#   - 启用 BBR 加速
#   - 配置防火墙
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
STRUCTURED_JSON_FILE="${XRAY_CONFIG_DIR}/vless-reality.json"
STRUCTURED_YAML_FILE="${XRAY_CONFIG_DIR}/vless-reality.yaml"
VRS_PROTOCOL_ID="vless-reality"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VRS_LIB_DIR="${VRS_LIB_DIR:-${SCRIPT_DIR}/lib}"
# shellcheck source=lib/firewall-ssh-guard.sh
source "${VRS_LIB_DIR}/firewall-ssh-guard.sh"
# shellcheck source=lib/xray-protocol-guard.sh
source "${VRS_LIB_DIR}/xray-protocol-guard.sh"
# shellcheck source=lib/network-utils.sh
source "${VRS_LIB_DIR}/network-utils.sh"
# shellcheck source=lib/installer-helpers.sh
source "${VRS_LIB_DIR}/installer-helpers.sh"

# 默认配置
PORT=443
DEST="www.microsoft.com"
DEST_PORT=443
REPLACE_EXISTING=false
NON_INTERACTIVE=false
PORT_EXPLICIT=false
UUID=""
SHORT_ID=""
SERVER_IP_OVERRIDE=""
OUTPUT_FORMAT="text"

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

show_usage() {
    cat << EOF
用法: $0 [选项]

选项:
  --port PORT          指定 VLESS 监听端口
  --dest HOST          指定 Reality 回落目标和 SNI，默认 www.microsoft.com
  --dest-port PORT     指定 Reality 回落目标端口，默认 443
  --uuid UUID          指定客户端 UUID；未指定时自动生成
  --short-id HEX       指定 Reality short ID；未指定时自动生成
  --server-ip IP       指定写入客户端设定的服务器地址；未指定时自动检测公网 IPv4
  --json               安装完成后在 stdout 输出 JSON 合约
  --yaml               安装完成后在 stdout 输出 YAML 合约
  --yes                非互动模式；遇到风险时直接失败，不询问继续
  --non-interactive    同 --yes
  --replace            允许覆盖既有 Xray 配置
  -h, --help           显示此帮助
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --port)
                [[ $# -ge 2 ]] || { log_error "--port 需要参数"; exit 1; }
                PORT="$2"
                PORT_EXPLICIT=true
                shift 2
                ;;
            --dest)
                [[ $# -ge 2 ]] || { log_error "--dest 需要参数"; exit 1; }
                DEST="$2"
                shift 2
                ;;
            --dest-port)
                [[ $# -ge 2 ]] || { log_error "--dest-port 需要参数"; exit 1; }
                DEST_PORT="$2"
                shift 2
                ;;
            --uuid)
                [[ $# -ge 2 ]] || { log_error "--uuid 需要参数"; exit 1; }
                UUID="$2"
                shift 2
                ;;
            --short-id)
                [[ $# -ge 2 ]] || { log_error "--short-id 需要参数"; exit 1; }
                SHORT_ID="$2"
                shift 2
                ;;
            --server-ip)
                [[ $# -ge 2 ]] || { log_error "--server-ip 需要参数"; exit 1; }
                SERVER_IP_OVERRIDE="$2"
                shift 2
                ;;
            --json)
                OUTPUT_FORMAT="json"
                shift
                ;;
            --yaml)
                OUTPUT_FORMAT="yaml"
                shift
                ;;
            --yes|--non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --replace)
                REPLACE_EXISTING=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

is_valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -ge 1 && "$1" -le 65535 ]]
}

validate_args() {
    if ! is_valid_port "$PORT"; then
        log_error "无效端口: $PORT"
        exit 1
    fi

    if ! is_valid_port "$DEST_PORT"; then
        log_error "无效 Reality 目标端口: $DEST_PORT"
        exit 1
    fi

    if [[ -n "$UUID" && ! "$UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        log_error "无效 UUID: $UUID"
        exit 1
    fi

    if [[ -n "$SHORT_ID" && ! "$SHORT_ID" =~ ^[0-9a-fA-F]{2,16}$ ]]; then
        log_error "无效 short ID，必须是 2 到 16 位十六进制"
        exit 1
    fi

    if [[ -n "$SHORT_ID" && $(( ${#SHORT_ID} % 2 )) -ne 0 ]]; then
        log_error "无效 short ID，长度必须为偶数"
        exit 1
    fi
}

# 进度指示器
print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║       VLESS + Reality 一键安装脚本 for Debian/Ubuntu          ║"
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
    
    # 支持 Debian 和 Ubuntu
    if [[ "$ID" != "debian" && "$ID" != "ubuntu" ]]; then
        log_warn "此脚本针对 Debian/Ubuntu 系统优化，当前系统: $ID"
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            log_error "非互动模式不允许在未明确支援的系统上继续"
            exit 1
        fi
        read -r -p "是否继续安装？(y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            exit 1
        fi
    fi
    
    log_success "系统检查通过: $PRETTY_NAME"
}

check_network() {
    # 注意：此时可能还没有 curl，使用 apt-get update 测试网络
    echo -ne "${YELLOW}[...]${NC} 测试网络连接并更新软件源..."
    if apt-get update > /dev/null 2>&1; then
        echo -e "\r${GREEN}[✓]${NC} 网络连接正常，软件源已更新    "
        return 0
    fi
    
    echo -e "\r${YELLOW}[!]${NC} 网络检测失败 (可能是 DNS 或防火墙问题)"
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        log_error "非互动模式下网络检测失败，停止安装"
        exit 1
    fi
    read -r -p "是否继续安装？(y/N): " confirm
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

        if [[ "$PORT_EXPLICIT" == "true" ]]; then
            log_error "已明确指定端口 ${PORT}，不会自动切换备用端口"
            exit 1
        fi
        
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

check_xray_config_conflict() {
    if [[ "$REPLACE_EXISTING" == "true" ]]; then
        ALLOW_REPLACE=true
    fi
    XRAY_CONFIG_FILE="$XRAY_CONFIG_FILE" XRAY_CONFIG_DIR="$XRAY_CONFIG_DIR" \
    VRS_PROTOCOL_ID="$VRS_PROTOCOL_ID" check_xray_config_ownership
}

#-------------------------------------------------------------------------------
# 安装依赖
#-------------------------------------------------------------------------------
install_dependencies() {
    log_info "安装必要依赖包..."
    
    local packages=("curl" "wget" "unzip" "jq" "openssl" "cron" "qrencode")
    local total=${#packages[@]}
    local current=0
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    
    for pkg in "${packages[@]}"; do
        current=$((current + 1))
        
        if dpkg -s "$pkg" > /dev/null 2>&1; then
            echo -e "${GREEN}[${current}/${total}]${NC} ${pkg} ${CYAN}(已安装)${NC}"
        else
            # 后台安装并显示动态进度
            apt-get install -y "$pkg" > /dev/null 2>&1 &
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
    
    log_success "依赖安装完成"
}

#-------------------------------------------------------------------------------
# 安装 Xray-core
#-------------------------------------------------------------------------------
install_xray() {
    log_info "正在下载并安装 Xray-core (这可能需要几分钟)..."
    echo ""

    if ! secure_run_xray_installer @ install; then
        log_error "Xray 安装脚本执行失败"
        exit 1
    fi

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
    # 新版: PrivateKey: xxx / Password: xxx (Password 是 Public Key)
    # 旧版: Private key: xxx / Public key: xxx
    if echo "$KEYS" | grep -q "PrivateKey:"; then
        # 新版格式 (Xray 25.x+)
        PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey:" | awk '{print $2}')
        PUBLIC_KEY=$(echo "$KEYS" | grep "Password:" | awk '{print $2}')
    else
        # 旧版格式
        PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
        PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
    fi
    
    # 验证密钥是否生成成功
    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
        log_error "密钥生成失败"
        log_info "xray x25519 输出: $KEYS"
        exit 1
    fi

    # 规范公钥为 base64url，无 padding（Reality 客户端要求）
    PUBLIC_KEY=$(to_base64url "$PUBLIC_KEY")
    PRIVATE_KEY=$(to_base64url "$PRIVATE_KEY")
    
    # 生成 UUID
    if [[ -z "$UUID" ]]; then
        UUID=$(cat /proc/sys/kernel/random/uuid)
    fi
    
    # 生成 Short ID (8位16进制)
    if [[ -z "$SHORT_ID" ]]; then
        SHORT_ID=$(openssl rand -hex 4)
    fi
    
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

    chmod 600 "$XRAY_CONFIG_FILE"
    chmod 700 "$XRAY_CONFIG_DIR"
    write_xray_protocol_marker

    # 创建日志目录
    mkdir -p /var/log/xray
    chmod 750 /var/log/xray 2>/dev/null || true

    log_success "Xray 配置文件生成完成"
}

#-------------------------------------------------------------------------------
# 配置服务
#-------------------------------------------------------------------------------
configure_service() {
    log_info "配置 Xray 服务..."
    
    # 启用并启动服务
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray
    
    # 等待服务启动
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
# 配置防火墙
#-------------------------------------------------------------------------------
configure_firewall() {
    log_info "配置防火墙..."

    local handled=false

    if command -v ufw &> /dev/null; then
        ensure_ssh_ufw_rules
        ufw allow "${PORT}/tcp" > /dev/null 2>&1 || true
        ufw --force enable > /dev/null 2>&1 || true
        log_success "UFW 防火墙已配置，端口 ${PORT} 已开放，SSH 端口已保留"
        handled=true
    fi

    if is_pure_nftables_backend; then
        ensure_ssh_nftables_rules
        nft list table inet vrs_proxy >/dev/null 2>&1 || nft add table inet vrs_proxy 2>/dev/null || true
        nft list chain inet vrs_proxy input >/dev/null 2>&1 || \
            nft 'add chain inet vrs_proxy input { type filter hook input priority 0 ; policy accept ; }' 2>/dev/null || true
        if ! nft list chain inet vrs_proxy input 2>/dev/null | grep -q "tcp dport ${PORT} accept"; then
            nft add rule inet vrs_proxy input tcp dport "${PORT}" accept 2>/dev/null || true
        fi
        log_success "nftables 防火墙已配置，端口 ${PORT} 已开放，SSH 端口已保留"
        handled=true
    fi

    if [[ "$handled" != "true" ]] && command -v iptables &> /dev/null; then
        ensure_ssh_iptables_rules
        iptables -C INPUT -p tcp --dport "${PORT}" -j ACCEPT 2>/dev/null || \
            iptables -I INPUT -p tcp --dport "${PORT}" -j ACCEPT

        # 保存规则
        if command -v iptables-save &> /dev/null; then
            iptables-save > /etc/iptables.rules

            # 创建开机恢复规则
            mkdir -p /etc/network/if-pre-up.d
            cat > /etc/network/if-pre-up.d/iptables << 'EOF'
#!/bin/sh
iptables-restore < /etc/iptables.rules
EOF
            chmod +x /etc/network/if-pre-up.d/iptables
        fi
        log_success "iptables 防火墙已配置，端口 ${PORT} 已开放"
        handled=true
    fi

    if [[ "$handled" != "true" ]]; then
        log_warn "未检测到防火墙，跳过配置"
    fi
}

#-------------------------------------------------------------------------------
# 启用 BBR
#-------------------------------------------------------------------------------
enable_bbr() {
    log_info "启用 BBR 拥塞控制..."
    ensure_bbr_enabled || true
}

#-------------------------------------------------------------------------------
# 配置健康检查定时任务
#-------------------------------------------------------------------------------
setup_health_check() {
    log_info "配置健康检查定时任务..."

    # 复制健康检查脚本
    if [[ -f "${SCRIPT_DIR}/health-check.sh" ]]; then
        cp "${SCRIPT_DIR}/health-check.sh" /usr/local/bin/xray-health-check.sh
        chmod 755 /usr/local/bin/xray-health-check.sh

        # 添加定时任务 (每小时执行一次) — 先清除旧条目，再写入新条目
        remove_crontab_lines_matching 'xray-health-check'
        ( crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/xray-health-check.sh >> /var/log/xray/health-check.log 2>&1" ) | crontab -

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

    # 部署共享 lib 到固定位置，便于已安装的卸载脚本使用
    if [[ -d "${SCRIPT_DIR}/lib" ]]; then
        mkdir -p /usr/local/share/vrs/lib
        cp "${SCRIPT_DIR}/lib"/*.sh /usr/local/share/vrs/lib/ 2>/dev/null || true
        chmod 644 /usr/local/share/vrs/lib/*.sh 2>/dev/null || true
    fi

    # 复制显示配置脚本
    if [[ -f "${SCRIPT_DIR}/show-config.sh" ]]; then
        cp "${SCRIPT_DIR}/show-config.sh" /usr/local/bin/xray-show-config
        chmod 755 /usr/local/bin/xray-show-config
        log_success "配置查看脚本已安装: xray-show-config"
    fi

    # 复制卸载脚本
    if [[ -f "${SCRIPT_DIR}/uninstall.sh" ]]; then
        cp "${SCRIPT_DIR}/uninstall.sh" /usr/local/bin/xray-uninstall.sh
        chmod 755 /usr/local/bin/xray-uninstall.sh
        log_success "卸载脚本已安装: xray-uninstall.sh"
    fi
}

#-------------------------------------------------------------------------------
# 生成客户端配置
#-------------------------------------------------------------------------------
generate_client_config() {
    log_info "生成客户端配置..."

    # 获取服务器公网 IP（严格校验，拒绝包含换行/控制字符的响应）
    if [[ -n "$SERVER_IP_OVERRIDE" ]]; then
        if ! is_valid_ip "$SERVER_IP_OVERRIDE"; then
            log_error "--server-ip 必须是合法的 IPv4 / IPv6 地址: $SERVER_IP_OVERRIDE"
            exit 1
        fi
        SERVER_IP="$SERVER_IP_OVERRIDE"
    else
        SERVER_IP=$(detect_public_ipv4 || true)
    fi

    if [[ -z "$SERVER_IP" ]]; then
        log_warn "无法获取公网 IP，请手动替换配置中的 SERVER_IP"
        SERVER_IP="YOUR_SERVER_IP"
    fi
    
    # 生成 VLESS 分享链接
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#VLESS-Reality"
    
    # 保存纯链接文件 (方便复制)
    echo -n "$VLESS_LINK" > "$VLESS_LINK_FILE"
    chmod 600 "$VLESS_LINK_FILE"
    log_success "VLESS 分享链接已保存到 ${VLESS_LINK_FILE}"
    
    # 生成二维码图片
    if command -v qrencode &> /dev/null; then
        qrencode -o "$QR_CODE_FILE" -s 10 -m 2 "$VLESS_LINK"
        chmod 600 "$QR_CODE_FILE"
        log_success "二维码图片已保存到 ${QR_CODE_FILE}"
    fi
    
    # 保存完整客户端配置
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

    chmod 600 "$CLIENT_CONFIG_FILE"
    log_success "完整配置已保存到 ${CLIENT_CONFIG_FILE}"
}

write_structured_outputs() {
    log_info "生成 AI 结构化输出..."

    local service_status
    service_status=$(systemctl is-active xray 2>/dev/null || true)
    if [[ -z "$service_status" ]]; then
        service_status="unknown"
    fi

    local generated_at
    generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    cat > "$STRUCTURED_JSON_FILE" << EOF
{
  "schemaVersion": "vrs.vless-reality.v1",
  "generatedAt": "$(json_escape "$generated_at")",
  "protocol": "vless-reality",
  "core": "xray-core",
  "server": "$(json_escape "$SERVER_IP")",
  "port": ${PORT},
  "uuid": "$(json_escape "$UUID")",
  "flow": "xtls-rprx-vision",
  "transport": "tcp",
  "security": "reality",
  "sni": "$(json_escape "$DEST")",
  "dest": "$(json_escape "$DEST")",
  "destPort": ${DEST_PORT},
  "publicKey": "$(json_escape "$PUBLIC_KEY")",
  "shortId": "$(json_escape "$SHORT_ID")",
  "fingerprint": "chrome",
  "shareLink": "$(json_escape "$VLESS_LINK")",
  "paths": {
    "xrayConfig": "$(json_escape "$XRAY_CONFIG_FILE")",
    "clientConfig": "$(json_escape "$CLIENT_CONFIG_FILE")",
    "shareLink": "$(json_escape "$VLESS_LINK_FILE")",
    "qrCode": "$(json_escape "$QR_CODE_FILE")",
    "json": "$(json_escape "$STRUCTURED_JSON_FILE")",
    "yaml": "$(json_escape "$STRUCTURED_YAML_FILE")"
  },
  "service": {
    "name": "xray",
    "status": "$(json_escape "$service_status")",
    "statusCommand": "systemctl status xray",
    "restartCommand": "systemctl restart xray",
    "logCommand": "journalctl -u xray -f"
  },
  "healthCheck": {
    "command": "/usr/local/bin/xray-health-check.sh",
    "cron": "0 * * * * /usr/local/bin/xray-health-check.sh >> /var/log/xray/health-check.log 2>&1"
  }
}
EOF
    chmod 600 "$STRUCTURED_JSON_FILE"

    cat > "$STRUCTURED_YAML_FILE" << EOF
schemaVersion: "vrs.vless-reality.v1"
generatedAt: "$(json_escape "$generated_at")"
protocol: "vless-reality"
core: "xray-core"
server: "$(json_escape "$SERVER_IP")"
port: ${PORT}
uuid: "$(json_escape "$UUID")"
flow: "xtls-rprx-vision"
transport: "tcp"
security: "reality"
sni: "$(json_escape "$DEST")"
dest: "$(json_escape "$DEST")"
destPort: ${DEST_PORT}
publicKey: "$(json_escape "$PUBLIC_KEY")"
shortId: "$(json_escape "$SHORT_ID")"
fingerprint: "chrome"
shareLink: "$(json_escape "$VLESS_LINK")"
paths:
  xrayConfig: "$(json_escape "$XRAY_CONFIG_FILE")"
  clientConfig: "$(json_escape "$CLIENT_CONFIG_FILE")"
  shareLink: "$(json_escape "$VLESS_LINK_FILE")"
  qrCode: "$(json_escape "$QR_CODE_FILE")"
  json: "$(json_escape "$STRUCTURED_JSON_FILE")"
  yaml: "$(json_escape "$STRUCTURED_YAML_FILE")"
service:
  name: "xray"
  status: "$(json_escape "$service_status")"
  statusCommand: "systemctl status xray"
  restartCommand: "systemctl restart xray"
  logCommand: "journalctl -u xray -f"
healthCheck:
  command: "/usr/local/bin/xray-health-check.sh"
  cron: "0 * * * * /usr/local/bin/xray-health-check.sh >> /var/log/xray/health-check.log 2>&1"
EOF
    chmod 600 "$STRUCTURED_YAML_FILE"

    log_success "AI JSON 输出已保存到 ${STRUCTURED_JSON_FILE}"
    log_success "AI YAML 输出已保存到 ${STRUCTURED_YAML_FILE}"
}

print_client_config() {
    echo ""
    case "$OUTPUT_FORMAT" in
        json)
            cat "$STRUCTURED_JSON_FILE"
            ;;
        yaml)
            cat "$STRUCTURED_YAML_FILE"
            ;;
        *)
            cat "$CLIENT_CONFIG_FILE"
            ;;
    esac
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
    check_xray_config_conflict
    
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
    write_structured_outputs
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    安装完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    
    print_client_config
}

# 执行主函数
parse_args "$@"
validate_args
main
