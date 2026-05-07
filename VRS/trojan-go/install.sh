#!/bin/bash

#===============================================================================
# Trojan-Go 一键安装脚本
# 适用于 Debian/Ubuntu 系统
#
# __ai_context__:
#   Trojan-Go 是 Trojan 协议的 Go 语言实现，支持 WebSocket 和 CDN 中转。
#   相比 Xray 的 Trojan，Trojan-Go 有独立的二进制和配置格式。
#
# 功能：
#   - 安装 Trojan-Go 二进制
#   - 支持 WebSocket 模式 (可 CDN 中转)
#   - 自签 TLS 证书
#   - 生成 trojan:// 分享链接
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TROJAN_GO_DIR="/etc/trojan-go"
TROJAN_GO_CONFIG="${TROJAN_GO_DIR}/config.json"
CERT_DIR="${TROJAN_GO_DIR}/certs"
CLIENT_CONFIG_FILE="${TROJAN_GO_DIR}/client-config.txt"
SHARE_LINK_FILE="${TROJAN_GO_DIR}/trojan-go-link.txt"

PORT=443
WS_PATH="/trojan-ws"
PASSWORD=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║      Trojan-Go 一键安装脚本 for Debian/Ubuntu                  ║"
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
    if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
        PORT=8443
        log_warn "443 被占用，使用 ${PORT}"
    fi
    log_success "端口: ${PORT}"
}

install_dependencies() {
    log_info "安装依赖..."
    apt-get update > /dev/null 2>&1
    apt-get install -y curl wget unzip openssl qrencode > /dev/null 2>&1
    log_success "完成"
}

#-------------------------------------------------------------------------------
# 安装 Trojan-Go
#-------------------------------------------------------------------------------
install_trojan_go() {
    log_info "安装 Trojan-Go..."
    mkdir -p "$TROJAN_GO_DIR"

    local arch
    case "$(uname -m)" in
        x86_64)  arch="linux-amd64" ;;
        aarch64) arch="linux-arm64" ;;
        armv7l)  arch="linux-armv7" ;;
        *)       log_error "不支持的架构: $(uname -m)"; exit 1 ;;
    esac

    # 从 GitHub 下载最新版
    local latest_url
    latest_url=$(curl -sL "https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest" \
        | grep "browser_download_url" \
        | grep "${arch}" \
        | grep "\.zip" \
        | head -1 \
        | cut -d '"' -f 4)

    if [[ -z "$latest_url" ]]; then
        log_error "无法获取 Trojan-Go 下载链接"
        exit 1
    fi

    local tmp_dir=$(mktemp -d)
    wget -q -O "${tmp_dir}/trojan-go.zip" "$latest_url"
    unzip -o "${tmp_dir}/trojan-go.zip" -d "${tmp_dir}" > /dev/null
    cp "${tmp_dir}/trojan-go" /usr/local/bin/trojan-go
    chmod +x /usr/local/bin/trojan-go
    rm -rf "$tmp_dir"

    log_success "Trojan-Go 安装完成"
}

generate_cert() {
    log_info "生成自签证书..."
    mkdir -p "$CERT_DIR"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "${CERT_DIR}/server.key" \
        -out "${CERT_DIR}/server.crt" \
        -subj "/CN=www.microsoft.com" \
        -days 3650 2>/dev/null
    chmod 644 "${CERT_DIR}/server.crt"
    chmod 600 "${CERT_DIR}/server.key"
    log_success "证书生成完成"
}

generate_config() {
    log_info "生成配置..."
    PASSWORD=$(openssl rand -base64 24)

    cat > "$TROJAN_GO_CONFIG" << EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": ${PORT},
    "remote_addr": "www.microsoft.com",
    "remote_port": 443,
    "password": [
        "${PASSWORD}"
    ],
    "ssl": {
        "cert": "${CERT_DIR}/server.crt",
        "key": "${CERT_DIR}/server.key",
        "sni": "www.microsoft.com",
        "fallback_addr": "www.microsoft.com",
        "fallback_port": 443
    },
    "websocket": {
        "enabled": true,
        "path": "${WS_PATH}",
        "host": "www.microsoft.com"
    },
    "mux": {
        "enabled": true,
        "concurrency": 8,
        "idle_timeout": 60
    }
}
EOF

    log_success "配置完成"
}

configure_service() {
    log_info "配置服务..."

    cat > /etc/systemd/system/trojan-go.service << 'EOF'
[Unit]
Description=Trojan-Go Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan-go/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable trojan-go
    systemctl restart trojan-go
    sleep 2

    if systemctl is-active --quiet trojan-go; then
        log_success "Trojan-Go 服务启动成功"
    else
        log_error "启动失败"
        systemctl status trojan-go
        exit 1
    fi
}

configure_firewall() {
    if command -v ufw &> /dev/null; then
        ufw allow ${PORT}/tcp > /dev/null 2>&1 || true
    elif command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
    fi
    log_success "防火墙已配置"
}

enable_bbr() {
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then return; fi
    local major=$(uname -r | cut -d. -f1)
    local minor=$(uname -r | cut -d. -f2)
    if [[ "$major" -ge 5 ]] || [[ "$major" -eq 4 && "$minor" -ge 9 ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p > /dev/null 2>&1
    fi
}

generate_client_config() {
    log_info "生成客户端配置..."

    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || echo "YOUR_SERVER_IP")

    local encoded_password
    encoded_password=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${PASSWORD}'))" 2>/dev/null || echo "${PASSWORD}")

    # Trojan-Go 分享链接 (兼容通用 Trojan 格式)
    local share_link="trojan://${encoded_password}@${server_ip}:${PORT}?security=tls&type=ws&host=www.microsoft.com&path=${WS_PATH}&sni=www.microsoft.com&allowInsecure=1#Trojan-Go"

    echo -n "$share_link" > "$SHARE_LINK_FILE"

    cat > "$CLIENT_CONFIG_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
                       Trojan-Go 客户端配置
═══════════════════════════════════════════════════════════════════════════════

服务器地址: ${server_ip}
端口: ${PORT}
密码: ${PASSWORD}
传输协议: WebSocket
WebSocket 路径: ${WS_PATH}
安全类型: TLS (自签证书)
多路复用: 开启

───────────────────────────────────────────────────────────────────────────────
                              分享链接
───────────────────────────────────────────────────────────────────────────────

${share_link}

───────────────────────────────────────────────────────────────────────────────
                       Trojan-Go 客户端 JSON 配置
───────────────────────────────────────────────────────────────────────────────

{
    "run_type": "client",
    "local_addr": "127.0.0.1",
    "local_port": 1080,
    "remote_addr": "${server_ip}",
    "remote_port": ${PORT},
    "password": ["${PASSWORD}"],
    "ssl": {
        "verify": false,
        "sni": "www.microsoft.com"
    },
    "websocket": {
        "enabled": true,
        "path": "${WS_PATH}",
        "host": "www.microsoft.com"
    },
    "mux": {
        "enabled": true,
        "concurrency": 8,
        "idle_timeout": 60
    }
}

───────────────────────────────────────────────────────────────────────────────
                              重要提示
───────────────────────────────────────────────────────────────────────────────

1. 支持 WebSocket，可通过 CDN 中转 (如 Cloudflare)
2. 自签证书，客户端需设置 verify=false
3. 推荐客户端: Trojan-Go, Clash, Shadowrocket
4. 服务状态: systemctl status trojan-go
5. 卸载: bash $(dirname "$0")/uninstall.sh

═══════════════════════════════════════════════════════════════════════════════
EOF

    log_success "配置已保存"

    if command -v qrencode &> /dev/null; then
        echo ""
        qrencode -t ANSIUTF8 "$share_link"
    fi
}

main() {
    print_banner
    echo ""
    check_root
    check_system
    check_port
    echo ""
    install_dependencies
    install_trojan_go
    echo ""
    generate_cert
    generate_config
    echo ""
    configure_service
    configure_firewall
    enable_bbr
    echo ""
    generate_client_config
    echo ""
    echo -e "${GREEN}════════ 安装完成！════════${NC}"
    echo ""
    cat "$CLIENT_CONFIG_FILE"
}

main "$@"

# [For Future AI]
# 1. Trojan-Go 从 p4gefau1t/trojan-go GitHub releases 下载
# 2. 默认开启 WebSocket 支持 CDN 中转
# 3. 开启 mux 多路复用增加性能
# 4. systemd 服务名 trojan-go
# 5. 与 Xray 的 Trojan 实现独立，互不冲突
