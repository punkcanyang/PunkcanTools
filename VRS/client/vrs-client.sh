#!/bin/bash
set -e

CLIENT_VERSION="0.1.0"
SCHEMA_VERSION="vrs.vless-reality.v1"
DEFAULT_PROFILE_NAME="default"
DEFAULT_PRIORITY="100"
DEFAULT_CHECK_URL="https://www.gstatic.com/generate_204"
DEFAULT_WATCH_INTERVAL="60"
XRAY_INSTALL_SCRIPT_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

VRS_CLIENT_HOME="${VRS_CLIENT_HOME:-$HOME/.vrs/client}"
PROFILES_DIR="${VRS_CLIENT_HOME}/profiles"
XRAY_DIR="${VRS_CLIENT_HOME}/xray"
RUN_DIR="${VRS_CLIENT_HOME}/run"
LOG_DIR="${VRS_CLIENT_HOME}/logs"
INDEX_FILE="${PROFILES_DIR}/index.json"
INDEX_LOCK_DIR="${PROFILES_DIR}/index.lock"
SOCKS_PORT="${VRS_SOCKS_PORT:-10808}"
HTTP_PORT="${VRS_HTTP_PORT:-10809}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

usage() {
    cat <<EOF
VRS local command line client ${CLIENT_VERSION}

Usage:
  bash client/vrs-client.sh import <vless-reality.json> [--name NAME] [--priority N]
  bash client/vrs-client.sh use --name NAME [--url URL]
  bash client/vrs-client.sh auto-use [--url URL]
  bash client/vrs-client.sh current
  bash client/vrs-client.sh start [--name NAME]
  bash client/vrs-client.sh stop [--name NAME]
  bash client/vrs-client.sh restart [--name NAME]
  bash client/vrs-client.sh status [--name NAME]
  bash client/vrs-client.sh check [--name NAME] [--url URL]
  bash client/vrs-client.sh watch [--interval SEC] [--url URL] [--once]
  bash client/vrs-client.sh logs [--name NAME]
  bash client/vrs-client.sh list [--sorted]
  bash client/vrs-client.sh export [--name NAME]
  bash client/vrs-client.sh config [--name NAME]
  bash client/vrs-client.sh check-core
  bash client/vrs-client.sh install-core
  bash client/vrs-client.sh service <install|uninstall|start|stop|restart|status> [--name NAME]
  bash client/vrs-client.sh watch-service <install|uninstall|start|stop|restart|status> [--interval SEC] [--url URL]

Environment:
  VRS_CLIENT_HOME  Client state directory, default: \$HOME/.vrs/client
  XRAY_BIN         Xray executable path, default: first xray found in PATH
  VRS_SOCKS_PORT   Local SOCKS inbound port, default: 10808
  VRS_HTTP_PORT    Local HTTP inbound port, default: 10809

Notes:
  - P2 first version supports VLESS + Reality JSON contract only.
  - Run install-core first if Xray-core is not installed locally.
  - Generated profile and Xray config files are chmod 600.
EOF
}

ensure_base_dirs() {
    mkdir -p "$PROFILES_DIR" "$XRAY_DIR" "$RUN_DIR" "$LOG_DIR"
    chmod 700 "$VRS_CLIENT_HOME" "$PROFILES_DIR" "$XRAY_DIR" "$RUN_DIR" "$LOG_DIR" 2>/dev/null || true

    if [ ! -f "$INDEX_FILE" ]; then
        cat > "$INDEX_FILE" <<EOF
{
  "schemaVersion": "vrs.client.profiles.v1",
  "current": "",
  "profiles": {}
}
EOF
        chmod 600 "$INDEX_FILE"
    fi
}

validate_profile_name() {
    local name="$1"

    if [ -z "$name" ]; then
        log_error "profile 名称不可为空"
        exit 1
    fi

    case "$name" in
        *[!A-Za-z0-9._-]*)
            log_error "profile 名称只能使用英数字、点、底线或连字符: $name"
            exit 1
            ;;
    esac
}

validate_port() {
    local value="$1"
    local label="$2"

    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
        log_error "无效${label}: $value"
        exit 1
    fi
}

validate_priority() {
    local value="$1"

    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 999999 ]; then
        log_error "无效 priority: $value"
        exit 1
    fi
}

validate_interval() {
    local value="$1"

    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 5 ] || [ "$value" -gt 86400 ]; then
        log_error "无效 interval: ${value}; 范围需为 5-86400 秒"
        exit 1
    fi
}

validate_local_ports() {
    validate_port "$SOCKS_PORT" " SOCKS 端口"
    validate_port "$HTTP_PORT" " HTTP 端口"

    if [ "$SOCKS_PORT" = "$HTTP_PORT" ]; then
        log_error "SOCKS 与 HTTP 本地端口不可相同: $SOCKS_PORT"
        exit 1
    fi
}

profile_file() {
    printf '%s/%s.json\n' "$PROFILES_DIR" "$1"
}

xray_config_file() {
    printf '%s/%s.config.json\n' "$XRAY_DIR" "$1"
}

pid_file() {
    printf '%s/%s.pid\n' "$RUN_DIR" "$1"
}

access_log_file() {
    printf '%s/%s.access.log\n' "$LOG_DIR" "$1"
}

error_log_file() {
    printf '%s/%s.error.log\n' "$LOG_DIR" "$1"
}

runner_log_file() {
    printf '%s/%s.runner.log\n' "$LOG_DIR" "$1"
}

watcher_log_file() {
    printf '%s/watcher.log\n' "$LOG_DIR"
}

json_get() {
    local file="$1"
    local path="$2"

    if command -v jq >/dev/null 2>&1; then
        jq -er ".${path}" "$file"
        return
    fi

    if command -v node >/dev/null 2>&1; then
        node -e '
const fs = require("fs");
const file = process.argv[1];
const path = process.argv[2].split(".");
const data = JSON.parse(fs.readFileSync(file, "utf8"));
let value = data;
for (const key of path) {
  if (value === undefined || value === null || !(key in value)) process.exit(1);
  value = value[key];
}
if (value === undefined || value === null || value === false) process.exit(1);
if (typeof value === "object") console.log(JSON.stringify(value));
else console.log(String(value));
' "$file" "$path"
        return
    fi

    log_error "需要 jq 或 node 其中之一来解析 JSON"
    exit 1
}

required_json_field() {
    local file="$1"
    local path="$2"
    local value

    if ! value=$(json_get "$file" "$path" 2>/dev/null); then
        log_error "JSON contract 缺少必要字段: $path"
        exit 1
    fi

    printf '%s\n' "$value"
}

optional_json_field() {
    local file="$1"
    local path="$2"
    local fallback="$3"
    local value

    if value=$(json_get "$file" "$path" 2>/dev/null); then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$fallback"
    fi
}

current_profile_name() {
    if [ ! -f "$INDEX_FILE" ]; then
        return 0
    fi

    if command -v jq >/dev/null 2>&1; then
        jq -r '.current // empty' "$INDEX_FILE"
        return
    fi

    if command -v node >/dev/null 2>&1; then
        node -e '
const fs = require("fs");
const file = process.argv[1];
const data = JSON.parse(fs.readFileSync(file, "utf8"));
if (data.current) console.log(data.current);
' "$INDEX_FILE"
        return
    fi
}

now_utc() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

write_json_atomic() {
    local target_file="$1"
    local temp_file

    temp_file=$(mktemp)
    cat > "$temp_file"
    mv "$temp_file" "$target_file"
    chmod 600 "$target_file"
}

lock_index() {
    local i

    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        if mkdir "$INDEX_LOCK_DIR" 2>/dev/null; then
            trap 'rmdir "$INDEX_LOCK_DIR" 2>/dev/null || true' EXIT
            return
        fi
        sleep 0.1
    done

    log_error "profile index 正在被其他进程写入，请稍后重试"
    exit 1
}

unlock_index() {
    rmdir "$INDEX_LOCK_DIR" 2>/dev/null || true
    trap - EXIT
}

index_set_profile() {
    local name="$1"
    local priority="$2"
    local profile_path
    local config_path
    local now

    profile_path=$(profile_file "$name")
    config_path=$(xray_config_file "$name")
    now=$(now_utc)
    lock_index

    if command -v jq >/dev/null 2>&1; then
        jq \
            --arg name "$name" \
            --argjson priority "$priority" \
            --arg profilePath "$profile_path" \
            --arg xrayConfigPath "$config_path" \
            --arg now "$now" '
              .schemaVersion = "vrs.client.profiles.v1" |
              .profiles = (.profiles // {}) |
              .profiles[$name] as $old |
              .profiles[$name] = {
                name: $name,
                priority: $priority,
                enabled: ($old.enabled // true),
                lastStatus: ($old.lastStatus // "unknown"),
                latencyMs: ($old.latencyMs // null),
                failureCount: ($old.failureCount // 0),
                lastCheckedAt: ($old.lastCheckedAt // null),
                lastUsedAt: ($old.lastUsedAt // null),
                importedAt: ($old.importedAt // $now),
                updatedAt: $now,
                profilePath: $profilePath,
                xrayConfigPath: $xrayConfigPath
              } |
              if (.current // "") == "" then .current = $name else . end
            ' "$INDEX_FILE" | write_json_atomic "$INDEX_FILE"
        unlock_index
        return
    fi

    if command -v node >/dev/null 2>&1; then
        VRS_INDEX_NAME="$name" \
        VRS_INDEX_PRIORITY="$priority" \
        VRS_INDEX_PROFILE_PATH="$profile_path" \
        VRS_INDEX_XRAY_CONFIG_PATH="$config_path" \
        VRS_INDEX_NOW="$now" \
        node -e '
const fs = require("fs");
const file = process.argv[1];
const data = JSON.parse(fs.readFileSync(file, "utf8"));
const name = process.env.VRS_INDEX_NAME;
const old = (data.profiles && data.profiles[name]) || {};
data.schemaVersion = "vrs.client.profiles.v1";
data.profiles = data.profiles || {};
data.profiles[name] = {
  name,
  priority: Number(process.env.VRS_INDEX_PRIORITY),
  enabled: old.enabled ?? true,
  lastStatus: old.lastStatus ?? "unknown",
  latencyMs: old.latencyMs ?? null,
  failureCount: old.failureCount ?? 0,
  lastCheckedAt: old.lastCheckedAt ?? null,
  lastUsedAt: old.lastUsedAt ?? null,
  importedAt: old.importedAt ?? process.env.VRS_INDEX_NOW,
  updatedAt: process.env.VRS_INDEX_NOW,
  profilePath: process.env.VRS_INDEX_PROFILE_PATH,
  xrayConfigPath: process.env.VRS_INDEX_XRAY_CONFIG_PATH
};
if (!data.current) data.current = name;
process.stdout.write(JSON.stringify(data, null, 2) + "\n");
' "$INDEX_FILE" | write_json_atomic "$INDEX_FILE"
        unlock_index
        return
    fi

    unlock_index
    log_error "需要 jq 或 node 更新 profile index"
    exit 1
}

index_set_current() {
    local name="$1"
    local now

    now=$(now_utc)
    lock_index

    if command -v jq >/dev/null 2>&1; then
        jq --arg name "$name" --arg now "$now" '
          .current = $name |
          .profiles[$name].lastUsedAt = $now
        ' "$INDEX_FILE" | write_json_atomic "$INDEX_FILE"
        unlock_index
        return
    fi

    if command -v node >/dev/null 2>&1; then
        VRS_INDEX_NAME="$name" VRS_INDEX_NOW="$now" node -e '
const fs = require("fs");
const file = process.argv[1];
const data = JSON.parse(fs.readFileSync(file, "utf8"));
const name = process.env.VRS_INDEX_NAME;
data.current = name;
if (data.profiles && data.profiles[name]) data.profiles[name].lastUsedAt = process.env.VRS_INDEX_NOW;
process.stdout.write(JSON.stringify(data, null, 2) + "\n");
' "$INDEX_FILE" | write_json_atomic "$INDEX_FILE"
        unlock_index
        return
    fi

    unlock_index
    log_error "需要 jq 或 node 更新 current profile"
    exit 1
}

index_record_check() {
    local name="$1"
    local status="$2"
    local latency_ms="${3:-}"
    local now

    now=$(now_utc)
    lock_index

    if command -v jq >/dev/null 2>&1; then
        jq \
            --arg name "$name" \
            --arg status "$status" \
            --arg latencyMs "$latency_ms" \
            --arg now "$now" '
              .profiles[$name].lastStatus = $status |
              .profiles[$name].latencyMs = (if $latencyMs == "" then null else ($latencyMs | tonumber) end) |
              .profiles[$name].lastCheckedAt = $now |
              .profiles[$name].failureCount = (
                if $status == "online" then 0
                else ((.profiles[$name].failureCount // 0) + 1)
                end
              )
            ' "$INDEX_FILE" | write_json_atomic "$INDEX_FILE"
        unlock_index
        return
    fi

    if command -v node >/dev/null 2>&1; then
        VRS_INDEX_NAME="$name" \
        VRS_INDEX_STATUS="$status" \
        VRS_INDEX_LATENCY_MS="$latency_ms" \
        VRS_INDEX_NOW="$now" \
        node -e '
const fs = require("fs");
const file = process.argv[1];
const data = JSON.parse(fs.readFileSync(file, "utf8"));
const name = process.env.VRS_INDEX_NAME;
data.profiles = data.profiles || {};
data.profiles[name] = data.profiles[name] || { name, priority: 100, enabled: true };
const profile = data.profiles[name];
profile.lastStatus = process.env.VRS_INDEX_STATUS;
profile.latencyMs = process.env.VRS_INDEX_LATENCY_MS === "" ? null : Number(process.env.VRS_INDEX_LATENCY_MS);
profile.lastCheckedAt = process.env.VRS_INDEX_NOW;
profile.failureCount = profile.lastStatus === "online" ? 0 : (Number(profile.failureCount || 0) + 1);
process.stdout.write(JSON.stringify(data, null, 2) + "\n");
' "$INDEX_FILE" | write_json_atomic "$INDEX_FILE"
        unlock_index
        return
    fi

    unlock_index
    log_error "需要 jq 或 node 更新检查结果"
    exit 1
}

index_emit_profiles() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '
          .current as $current |
          (.profiles // {}) |
          to_entries |
          sort_by(.value.priority, .key)[] |
          [
            .key,
            (.value.priority // 100),
            (.value.enabled // true),
            (.value.lastStatus // "unknown"),
            (if .value.latencyMs == null then "-" else (.value.latencyMs | tostring) end),
            (.value.failureCount // 0),
            (if .key == $current then "*" else "" end)
          ] | @tsv
        ' "$INDEX_FILE"
        return
    fi

    if command -v node >/dev/null 2>&1; then
        node -e '
const fs = require("fs");
const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const profiles = Object.values(data.profiles || {}).sort((a, b) => {
  const pa = Number(a.priority ?? 100);
  const pb = Number(b.priority ?? 100);
  if (pa !== pb) return pa - pb;
  return String(a.name).localeCompare(String(b.name));
});
for (const p of profiles) {
  console.log([
    p.name,
    p.priority ?? 100,
    p.enabled ?? true,
    p.lastStatus ?? "unknown",
    p.latencyMs ?? "-",
    p.failureCount ?? 0,
    p.name === data.current ? "*" : ""
  ].join("\t"));
}
' "$INDEX_FILE"
        return
    fi

    log_error "需要 jq 或 node 读取 profile index"
    exit 1
}

index_emit_candidates() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '
          def status_rank:
            if (.lastStatus // "unknown") == "online" then 0
            elif (.lastStatus // "unknown") == "unknown" then 1
            else 2
            end;
          (.profiles // {}) |
          to_entries |
          map(select((.value.enabled // true) == true)) |
          sort_by(
            (.value.priority // 100),
            (.value | status_rank),
            (if .value.latencyMs == null then 999999999 else .value.latencyMs end),
            (.value.failureCount // 0),
            .key
          )[] |
          [
            .key,
            (.value.priority // 100),
            (.value.lastStatus // "unknown"),
            (if .value.latencyMs == null then "-" else (.value.latencyMs | tostring) end),
            (.value.failureCount // 0)
          ] | @tsv
        ' "$INDEX_FILE"
        return
    fi

    if command -v node >/dev/null 2>&1; then
        node -e '
const fs = require("fs");
const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const rank = (status) => status === "online" ? 0 : status === "unknown" ? 1 : 2;
const profiles = Object.values(data.profiles || {})
  .filter((p) => (p.enabled ?? true) === true)
  .sort((a, b) => {
    const pa = Number(a.priority ?? 100);
    const pb = Number(b.priority ?? 100);
    if (pa !== pb) return pa - pb;
    const ra = rank(a.lastStatus ?? "unknown");
    const rb = rank(b.lastStatus ?? "unknown");
    if (ra !== rb) return ra - rb;
    const la = a.latencyMs == null ? 999999999 : Number(a.latencyMs);
    const lb = b.latencyMs == null ? 999999999 : Number(b.latencyMs);
    if (la !== lb) return la - lb;
    const fa = Number(a.failureCount ?? 0);
    const fb = Number(b.failureCount ?? 0);
    if (fa !== fb) return fa - fb;
    return String(a.name).localeCompare(String(b.name));
  });
for (const p of profiles) {
  console.log([
    p.name,
    p.priority ?? 100,
    p.lastStatus ?? "unknown",
    p.latencyMs ?? "-",
    p.failureCount ?? 0
  ].join("\t"));
}
' "$INDEX_FILE"
        return
    fi

    log_error "需要 jq 或 node 读取候选线路"
    exit 1
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

xml_escape() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

systemd_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

script_path() {
    local source_path="$0"
    local script_dir
    local script_name

    case "$source_path" in
        /*)
            printf '%s\n' "$source_path"
            ;;
        */*)
            script_dir=$(cd "$(dirname "$source_path")" && pwd)
            script_name=$(basename "$source_path")
            printf '%s/%s\n' "$script_dir" "$script_name"
            ;;
        *)
            if command -v "$source_path" >/dev/null 2>&1; then
                command -v "$source_path"
            else
                printf '%s/%s\n' "$(pwd)" "$source_path"
            fi
            ;;
    esac
}

resolve_xray() {
    if [ -n "${XRAY_BIN:-}" ]; then
        if [ -x "$XRAY_BIN" ]; then
            printf '%s\n' "$XRAY_BIN"
            return 0
        fi
        log_error "XRAY_BIN 不存在或不可执行: $XRAY_BIN"
        return 1
    fi

    if command -v xray >/dev/null 2>&1; then
        command -v xray
        return 0
    fi

    if [ -x "/usr/local/bin/xray" ]; then
        printf '%s\n' "/usr/local/bin/xray"
        return 0
    fi

    if [ -x "/opt/homebrew/bin/xray" ]; then
        printf '%s\n' "/opt/homebrew/bin/xray"
        return 0
    fi

    return 1
}

print_xray_hint() {
    log_warn "找不到本地 Xray-core。"
    echo "请先安装 Xray-core，并确认 xray 在 PATH 中，或设置 XRAY_BIN=/path/to/xray。"
}

parse_profile_args() {
    PROFILE_NAME="$DEFAULT_PROFILE_NAME"
    PROFILE_NAME_EXPLICIT="0"

    while [ $# -gt 0 ]; do
        case "$1" in
            --name)
                if [ $# -lt 2 ]; then
                    log_error "--name 需要参数"
                    exit 1
                fi
                PROFILE_NAME="$2"
                PROFILE_NAME_EXPLICIT="1"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    if [ "$PROFILE_NAME_EXPLICIT" -eq 0 ]; then
        local current_name
        current_name=$(current_profile_name 2>/dev/null || true)
        if [ -n "$current_name" ]; then
            PROFILE_NAME="$current_name"
        fi
    fi

    validate_profile_name "$PROFILE_NAME"
}

validate_contract() {
    local contract_file="$1"
    local schema_version
    local protocol
    local core
    local transport
    local security
    local port
    local dest_port

    schema_version=$(required_json_field "$contract_file" "schemaVersion")
    protocol=$(required_json_field "$contract_file" "protocol")
    core=$(required_json_field "$contract_file" "core")
    transport=$(required_json_field "$contract_file" "transport")
    security=$(required_json_field "$contract_file" "security")
    port=$(required_json_field "$contract_file" "port")
    dest_port=$(required_json_field "$contract_file" "destPort")

    if [ "$schema_version" != "$SCHEMA_VERSION" ]; then
        log_error "不支援的 schemaVersion: $schema_version"
        exit 1
    fi

    if [ "$protocol" != "vless-reality" ] || [ "$core" != "xray-core" ]; then
        log_error "P2 第一版只支援 xray-core 的 vless-reality contract"
        exit 1
    fi

    if [ "$transport" != "tcp" ] || [ "$security" != "reality" ]; then
        log_error "P2 第一版只支援 TCP + Reality"
        exit 1
    fi

    validate_port "$port" "远端端口"
    validate_port "$dest_port" " Reality destPort"

    required_json_field "$contract_file" "server" >/dev/null
    required_json_field "$contract_file" "uuid" >/dev/null
    required_json_field "$contract_file" "flow" >/dev/null
    required_json_field "$contract_file" "sni" >/dev/null
    required_json_field "$contract_file" "publicKey" >/dev/null
    required_json_field "$contract_file" "shortId" >/dev/null
}

generate_xray_config() {
    local name="$1"
    local source_file
    local output_file
    local access_log
    local error_log
    local server
    local port
    local uuid
    local flow
    local sni
    local public_key
    local short_id
    local fingerprint

    source_file=$(profile_file "$name")
    output_file=$(xray_config_file "$name")
    access_log=$(access_log_file "$name")
    error_log=$(error_log_file "$name")

    server=$(required_json_field "$source_file" "server")
    port=$(required_json_field "$source_file" "port")
    uuid=$(required_json_field "$source_file" "uuid")
    flow=$(required_json_field "$source_file" "flow")
    sni=$(required_json_field "$source_file" "sni")
    public_key=$(required_json_field "$source_file" "publicKey")
    short_id=$(required_json_field "$source_file" "shortId")
    fingerprint=$(optional_json_field "$source_file" "fingerprint" "chrome")

    validate_local_ports
    validate_port "$port" "远端端口"

    touch "$access_log" "$error_log"
    chmod 600 "$access_log" "$error_log" 2>/dev/null || true

    cat > "$output_file" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$(json_escape "$access_log")",
    "error": "$(json_escape "$error_log")"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "port": ${SOCKS_PORT},
      "protocol": "socks",
      "settings": {
        "udp": true
      }
    },
    {
      "tag": "http-in",
      "listen": "127.0.0.1",
      "port": ${HTTP_PORT},
      "protocol": "http",
      "settings": {}
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$(json_escape "$server")",
            "port": ${port},
            "users": [
              {
                "id": "$(json_escape "$uuid")",
                "encryption": "none",
                "flow": "$(json_escape "$flow")"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "$(json_escape "$sni")",
          "fingerprint": "$(json_escape "$fingerprint")",
          "publicKey": "$(json_escape "$public_key")",
          "shortId": "$(json_escape "$short_id")"
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ]
}
EOF

    chmod 600 "$output_file"
}

import_profile() {
    local contract_file=""
    local target_file
    local priority="$DEFAULT_PRIORITY"

    PROFILE_NAME="$DEFAULT_PROFILE_NAME"

    while [ $# -gt 0 ]; do
        case "$1" in
            --name)
                if [ $# -lt 2 ]; then
                    log_error "--name 需要参数"
                    exit 1
                fi
                PROFILE_NAME="$2"
                shift 2
                ;;
            --priority)
                if [ $# -lt 2 ]; then
                    log_error "--priority 需要参数"
                    exit 1
                fi
                priority="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                if [ -n "$contract_file" ]; then
                    log_error "只能汇入一个 JSON contract"
                    exit 1
                fi
                contract_file="$1"
                shift
                ;;
        esac
    done

    validate_profile_name "$PROFILE_NAME"
    validate_priority "$priority"

    if [ -z "$contract_file" ]; then
        log_error "缺少 JSON contract 路径"
        exit 1
    fi

    if [ ! -f "$contract_file" ]; then
        log_error "找不到 JSON contract: $contract_file"
        exit 1
    fi

    ensure_base_dirs
    validate_contract "$contract_file"

    target_file=$(profile_file "$PROFILE_NAME")
    cp "$contract_file" "$target_file"
    chmod 600 "$target_file"

    generate_xray_config "$PROFILE_NAME"
    index_set_profile "$PROFILE_NAME" "$priority"

    log_success "已汇入 profile: $PROFILE_NAME"
    echo "Priority: $priority"
    echo "Profile: $target_file"
    echo "Xray config: $(xray_config_file "$PROFILE_NAME")"
    echo "Local SOCKS: 127.0.0.1:${SOCKS_PORT}"
    echo "Local HTTP: 127.0.0.1:${HTTP_PORT}"
}

require_profile() {
    local name="$1"
    local file

    file=$(profile_file "$name")
    if [ ! -f "$file" ]; then
        log_error "找不到 profile: $name。请先执行 import。"
        exit 1
    fi
}

require_xray_config() {
    local name="$1"
    local config

    config=$(xray_config_file "$name")
    if [ ! -f "$config" ]; then
        require_profile "$name"
        generate_xray_config "$name"
    fi
}

is_pid_running() {
    local name="$1"
    local file
    local pid

    file=$(pid_file "$name")
    if [ ! -f "$file" ]; then
        return 1
    fi

    pid=$(cat "$file" 2>/dev/null || true)
    if [ -z "$pid" ]; then
        return 1
    fi

    kill -0 "$pid" 2>/dev/null
}

service_label() {
    printf 'io.punkcan.vrs.%s\n' "$1"
}

systemd_unit_name() {
    printf 'vrs-client-%s.service\n' "$1"
}

watch_service_label() {
    printf 'io.punkcan.vrs.watch\n'
}

watch_systemd_unit_name() {
    printf 'vrs-client-watch.service\n'
}

launchd_plist_file() {
    printf '%s/Library/LaunchAgents/%s.plist\n' "$HOME" "$(service_label "$1")"
}

watch_launchd_plist_file() {
    printf '%s/Library/LaunchAgents/%s.plist\n' "$HOME" "$(watch_service_label)"
}

systemd_unit_file() {
    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    printf '%s/systemd/user/%s\n' "$config_home" "$(systemd_unit_name "$1")"
}

watch_systemd_unit_file() {
    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    printf '%s/systemd/user/%s\n' "$config_home" "$(watch_systemd_unit_name)"
}

is_service_running() {
    local name="$1"
    local os_name
    local label
    local unit

    os_name=$(uname -s)
    case "$os_name" in
        Darwin)
            label=$(service_label "$name")
            launchctl print "gui/$(id -u)/${label}" 2>/dev/null | grep -q 'state = running'
            ;;
        Linux)
            unit=$(systemd_unit_name "$name")
            command -v systemctl >/dev/null 2>&1 && systemctl --user is-active --quiet "$unit"
            ;;
        *)
            return 1
            ;;
    esac
}

is_watch_service_running() {
    local os_name
    local unit

    os_name=$(uname -s)
    case "$os_name" in
        Darwin)
            launchctl print "gui/$(id -u)/$(watch_service_label)" 2>/dev/null | grep -q 'state = running'
            ;;
        Linux)
            unit=$(watch_systemd_unit_name)
            command -v systemctl >/dev/null 2>&1 && systemctl --user is-active --quiet "$unit"
            ;;
        *)
            return 1
            ;;
    esac
}

is_running() {
    local name="$1"

    is_pid_running "$name" || is_service_running "$name"
}

stop_profile_runtime() {
    local name="$1"

    if is_pid_running "$name"; then
        stop_client --name "$name"
    elif is_service_running "$name"; then
        stop_service --name "$name"
    fi
}

write_launchd_plist() {
    local name="$1"
    local plist
    local label
    local current_script
    local run_log

    plist=$(launchd_plist_file "$name")
    label=$(service_label "$name")
    current_script=$(script_path)
    run_log=$(runner_log_file "$name")

    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$(xml_escape "$label")</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$(xml_escape "$current_script")</string>
    <string>run-foreground</string>
    <string>--name</string>
    <string>$(xml_escape "$name")</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>VRS_CLIENT_HOME</key>
    <string>$(xml_escape "$VRS_CLIENT_HOME")</string>
    <key>XRAY_BIN</key>
    <string>$(xml_escape "${XRAY_BIN:-}")</string>
    <key>VRS_SOCKS_PORT</key>
    <string>$(xml_escape "$SOCKS_PORT")</string>
    <key>VRS_HTTP_PORT</key>
    <string>$(xml_escape "$HTTP_PORT")</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$(xml_escape "$run_log")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$run_log")</string>
</dict>
</plist>
EOF

    chmod 600 "$plist"
}

write_systemd_unit() {
    local name="$1"
    local unit_file
    local unit_name
    local current_script
    local run_log

    unit_file=$(systemd_unit_file "$name")
    unit_name=$(systemd_unit_name "$name")
    current_script=$(script_path)
    run_log=$(runner_log_file "$name")

    mkdir -p "$(dirname "$unit_file")"

    cat > "$unit_file" <<EOF
[Unit]
Description=VRS Xray Client profile ${name}
After=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash "$(systemd_escape "$current_script")" run-foreground --name "$(systemd_escape "$name")"
Restart=always
RestartSec=5
Environment="VRS_CLIENT_HOME=$(systemd_escape "$VRS_CLIENT_HOME")"
Environment="XRAY_BIN=$(systemd_escape "${XRAY_BIN:-}")"
Environment="VRS_SOCKS_PORT=$(systemd_escape "$SOCKS_PORT")"
Environment="VRS_HTTP_PORT=$(systemd_escape "$HTTP_PORT")"
StandardOutput=append:$(systemd_escape "$run_log")
StandardError=append:$(systemd_escape "$run_log")

[Install]
WantedBy=default.target
EOF

    chmod 600 "$unit_file"
    log_info "systemd unit: $unit_name"
}

install_service() {
    local os_name
    local plist
    local unit

    parse_profile_args "$@"
    ensure_base_dirs
    require_xray_config "$PROFILE_NAME"

    if ! resolve_xray >/dev/null 2>&1; then
        print_xray_hint
        exit 1
    fi

    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            write_launchd_plist "$PROFILE_NAME"
            plist=$(launchd_plist_file "$PROFILE_NAME")
            launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
            launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || launchctl load -w "$plist"
            launchctl kickstart -k "gui/$(id -u)/$(service_label "$PROFILE_NAME")" >/dev/null 2>&1 || true
            log_success "已安装并启动 launchd service: $(service_label "$PROFILE_NAME")"
            ;;
        Linux)
            if ! command -v systemctl >/dev/null 2>&1; then
                log_error "Linux service 模式需要 systemctl"
                exit 1
            fi
            write_systemd_unit "$PROFILE_NAME"
            unit=$(systemd_unit_name "$PROFILE_NAME")
            systemctl --user daemon-reload
            systemctl --user enable --now "$unit"
            log_success "已安装并启动 systemd user service: $unit"
            ;;
        *)
            log_error "不支援的本地系统: $os_name"
            exit 1
            ;;
    esac
}

uninstall_service() {
    local os_name
    local plist
    local unit
    local unit_file

    parse_profile_args "$@"
    ensure_base_dirs
    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            plist=$(launchd_plist_file "$PROFILE_NAME")
            launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || launchctl unload "$plist" >/dev/null 2>&1 || true
            rm -f "$plist"
            log_success "已移除 launchd service: $(service_label "$PROFILE_NAME")"
            ;;
        Linux)
            if ! command -v systemctl >/dev/null 2>&1; then
                log_error "Linux service 模式需要 systemctl"
                exit 1
            fi
            unit=$(systemd_unit_name "$PROFILE_NAME")
            unit_file=$(systemd_unit_file "$PROFILE_NAME")
            systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
            rm -f "$unit_file"
            systemctl --user daemon-reload
            log_success "已移除 systemd user service: $unit"
            ;;
        *)
            log_error "不支援的本地系统: $os_name"
            exit 1
            ;;
    esac
}

start_service() {
    local os_name
    local plist
    local unit

    parse_profile_args "$@"
    ensure_base_dirs
    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            plist=$(launchd_plist_file "$PROFILE_NAME")
            if [ ! -f "$plist" ]; then
                log_error "找不到 launchd plist，请先执行 service install"
                exit 1
            fi
            launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || true
            launchctl kickstart -k "gui/$(id -u)/$(service_label "$PROFILE_NAME")"
            ;;
        Linux)
            unit=$(systemd_unit_name "$PROFILE_NAME")
            systemctl --user start "$unit"
            ;;
        *)
            log_error "不支援的本地系统: $os_name"
            exit 1
            ;;
    esac
}

stop_service() {
    local os_name
    local plist
    local unit

    parse_profile_args "$@"
    ensure_base_dirs
    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            plist=$(launchd_plist_file "$PROFILE_NAME")
            launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || launchctl unload "$plist"
            ;;
        Linux)
            unit=$(systemd_unit_name "$PROFILE_NAME")
            systemctl --user stop "$unit"
            ;;
        *)
            log_error "不支援的本地系统: $os_name"
            exit 1
            ;;
    esac
}

status_service() {
    local os_name
    local unit

    parse_profile_args "$@"
    ensure_base_dirs
    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            launchctl print "gui/$(id -u)/$(service_label "$PROFILE_NAME")"
            ;;
        Linux)
            unit=$(systemd_unit_name "$PROFILE_NAME")
            systemctl --user status "$unit"
            ;;
        *)
            log_error "不支援的本地系统: $os_name"
            exit 1
            ;;
    esac
}

restart_service() {
    local os_name
    local unit

    parse_profile_args "$@"
    ensure_base_dirs
    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            launchctl kickstart -k "gui/$(id -u)/$(service_label "$PROFILE_NAME")"
            ;;
        Linux)
            unit=$(systemd_unit_name "$PROFILE_NAME")
            systemctl --user restart "$unit"
            ;;
        *)
            log_error "不支援的本地系统: $os_name"
            exit 1
            ;;
    esac
}

service_client() {
    local service_action="${1:-}"

    if [ -z "$service_action" ]; then
        log_error "service 需要子命令: install|uninstall|start|stop|restart|status"
        exit 1
    fi

    shift

    case "$service_action" in
        install)
            install_service "$@"
            ;;
        uninstall)
            uninstall_service "$@"
            ;;
        start)
            start_service "$@"
            ;;
        stop)
            stop_service "$@"
            ;;
        restart)
            restart_service "$@"
            ;;
        status)
            status_service "$@"
            ;;
        *)
            log_error "未知 service 子命令: $service_action"
            exit 1
            ;;
    esac
}

run_foreground() {
    local xray_bin
    local config

    parse_profile_args "$@"
    ensure_base_dirs
    require_xray_config "$PROFILE_NAME"

    if ! xray_bin=$(resolve_xray); then
        print_xray_hint
        exit 1
    fi

    config=$(xray_config_file "$PROFILE_NAME")
    exec "$xray_bin" run -config "$config"
}

start_client() {
    local xray_bin
    local config
    local pid_path
    local run_log

    parse_profile_args "$@"
    ensure_base_dirs
    require_xray_config "$PROFILE_NAME"

    if is_running "$PROFILE_NAME"; then
        log_success "profile 已在运行: $PROFILE_NAME"
        return
    fi

    if ! xray_bin=$(resolve_xray); then
        print_xray_hint
        exit 1
    fi

    config=$(xray_config_file "$PROFILE_NAME")
    pid_path=$(pid_file "$PROFILE_NAME")
    run_log=$(runner_log_file "$PROFILE_NAME")

    nohup "$xray_bin" run -config "$config" >> "$run_log" 2>&1 &
    echo "$!" > "$pid_path"
    chmod 600 "$pid_path" "$run_log" 2>/dev/null || true

    sleep 1

    if is_running "$PROFILE_NAME"; then
        log_success "已启动 profile: $PROFILE_NAME"
        echo "Local SOCKS: 127.0.0.1:${SOCKS_PORT}"
        echo "Local HTTP: 127.0.0.1:${HTTP_PORT}"
    else
        log_error "Xray 启动失败，请查看日志: $run_log"
        exit 1
    fi
}

stop_client() {
    local pid_path
    local pid
    local i

    parse_profile_args "$@"
    ensure_base_dirs
    pid_path=$(pid_file "$PROFILE_NAME")

    if ! is_pid_running "$PROFILE_NAME"; then
        if is_service_running "$PROFILE_NAME"; then
            log_warn "profile 由 service 管理，请使用 service stop: $PROFILE_NAME"
            return
        fi
        log_warn "profile 未在运行: $PROFILE_NAME"
        [ -f "$pid_path" ] && rm -f "$pid_path"
        return
    fi

    pid=$(cat "$pid_path")
    kill "$pid"

    for i in 1 2 3 4 5 6 7 8 9 10; do
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$pid_path"
            log_success "已停止 profile: $PROFILE_NAME"
            return
        fi
        sleep 1
    done

    log_warn "进程仍在运行，PID: $pid"
}

restart_client() {
    stop_client "$@"
    start_client "$@"
}

status_client() {
    local profile_path
    local config_path
    local server
    local port

    parse_profile_args "$@"
    ensure_base_dirs
    profile_path=$(profile_file "$PROFILE_NAME")
    config_path=$(xray_config_file "$PROFILE_NAME")

    if [ -f "$profile_path" ]; then
        server=$(optional_json_field "$profile_path" "server" "unknown")
        port=$(optional_json_field "$profile_path" "port" "unknown")
    else
        server="missing"
        port="missing"
    fi

    if is_pid_running "$PROFILE_NAME"; then
        log_success "running: $PROFILE_NAME"
    elif is_service_running "$PROFILE_NAME"; then
        log_success "running by service: $PROFILE_NAME"
    else
        log_warn "stopped: $PROFILE_NAME"
    fi

    echo "Server: ${server}:${port}"
    echo "Local SOCKS: 127.0.0.1:${SOCKS_PORT}"
    echo "Local HTTP: 127.0.0.1:${HTTP_PORT}"
    echo "Profile: $profile_path"
    echo "Xray config: $config_path"
}

check_client() {
    local check_url="$DEFAULT_CHECK_URL"
    local result
    local http_code
    local total_time
    local latency_ms
    local current_name

    PROFILE_NAME="$DEFAULT_PROFILE_NAME"
    PROFILE_NAME_EXPLICIT="0"

    while [ $# -gt 0 ]; do
        case "$1" in
            --name)
                if [ $# -lt 2 ]; then
                    log_error "--name 需要参数"
                    exit 1
                fi
                PROFILE_NAME="$2"
                PROFILE_NAME_EXPLICIT="1"
                shift 2
                ;;
            --url)
                if [ $# -lt 2 ]; then
                    log_error "--url 需要参数"
                    exit 1
                fi
                check_url="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    if [ "$PROFILE_NAME_EXPLICIT" -eq 0 ]; then
        current_name=$(current_profile_name 2>/dev/null || true)
        if [ -n "$current_name" ]; then
            PROFILE_NAME="$current_name"
        fi
    fi

    validate_profile_name "$PROFILE_NAME"
    ensure_base_dirs
    require_profile "$PROFILE_NAME"

    if ! is_running "$PROFILE_NAME"; then
        index_record_check "$PROFILE_NAME" "offline" ""
        log_error "profile 未运行，无法检查连线: $PROFILE_NAME"
        exit 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        index_record_check "$PROFILE_NAME" "offline" ""
        log_error "需要 curl 执行连线检查"
        exit 1
    fi

    if ! result=$(curl -sS -o /dev/null -w '%{http_code} %{time_total}' --max-time 15 --socks5-hostname "127.0.0.1:${SOCKS_PORT}" "$check_url" 2>/dev/null); then
        index_record_check "$PROFILE_NAME" "offline" ""
        log_error "连线检查失败: $check_url"
        exit 1
    fi

    http_code=$(printf '%s' "$result" | awk '{print $1}')
    total_time=$(printf '%s' "$result" | awk '{print $2}')
    latency_ms=$(awk -v seconds="$total_time" 'BEGIN { printf "%.0f", seconds * 1000 }')

    case "$http_code" in
        2*|3*)
            index_record_check "$PROFILE_NAME" "online" "$latency_ms"
            log_success "连线可用: HTTP ${http_code}, ${total_time}s"
            ;;
        *)
            index_record_check "$PROFILE_NAME" "offline" "$latency_ms"
            log_error "连线异常: HTTP ${http_code}, ${total_time}s"
            exit 1
            ;;
    esac
}

logs_client() {
    local error_log
    local run_log

    parse_profile_args "$@"
    ensure_base_dirs
    error_log=$(error_log_file "$PROFILE_NAME")
    run_log=$(runner_log_file "$PROFILE_NAME")

    echo "== Xray error log =="
    if [ -f "$error_log" ]; then
        tail -n 80 "$error_log"
    else
        echo "(missing) $error_log"
    fi

    echo
    echo "== Runner log =="
    if [ -f "$run_log" ]; then
        tail -n 80 "$run_log"
    else
        echo "(missing) $run_log"
    fi

    echo
    echo "== Watcher log =="
    if [ -f "$(watcher_log_file)" ]; then
        tail -n 80 "$(watcher_log_file)"
    else
        echo "(missing) $(watcher_log_file)"
    fi
}

list_profiles() {
    local sorted="0"
    local name
    local found=0
    local priority
    local enabled
    local status
    local latency
    local failures
    local current_marker
    local runtime

    while [ $# -gt 0 ]; do
        case "$1" in
            --sorted)
                sorted="1"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    ensure_base_dirs

    if [ "$sorted" -eq 1 ]; then
        printf '%-24s %-8s %-10s %-10s %-8s\n' "NAME" "PRIORITY" "STATUS" "LATENCY" "FAILS"

        while IFS=$'\t' read -r name priority status latency failures; do
            [ -n "$name" ] || continue
            found=1
            printf '%-24s %-8s %-10s %-10s %-8s\n' "$name" "$priority" "$status" "$latency" "$failures"
        done < <(index_emit_candidates)

        if [ "$found" -eq 0 ]; then
            log_warn "没有 enabled=true 的候选 profile"
        fi
        return
    fi

    printf '%-2s %-24s %-8s %-8s %-10s %-10s %-8s %s\n' "" "NAME" "PRIORITY" "ENABLED" "STATUS" "LATENCY" "FAILS" "RUNTIME"

    while IFS=$'\t' read -r name priority enabled status latency failures current_marker; do
        [ -n "$name" ] || continue
        found=1
        if is_running "$name"; then
            runtime="running"
        else
            runtime="stopped"
        fi

        printf '%-2s %-24s %-8s %-8s %-10s %-10s %-8s %s\n' \
            "$current_marker" "$name" "$priority" "$enabled" "$status" "$latency" "$failures" "$runtime"
    done < <(index_emit_profiles)

    if [ "$found" -eq 0 ]; then
        log_warn "尚未汇入任何 profile"
    fi
}

current_profile() {
    local current_name

    ensure_base_dirs
    current_name=$(current_profile_name 2>/dev/null || true)

    if [ -z "$current_name" ]; then
        log_warn "尚未选择 current profile"
        exit 1
    fi

    echo "$current_name"
    status_client --name "$current_name"
}

service_installed() {
    local name="$1"
    local os_name

    os_name=$(uname -s)
    case "$os_name" in
        Darwin)
            [ -f "$(launchd_plist_file "$name")" ]
            ;;
        Linux)
            [ -f "$(systemd_unit_file "$name")" ]
            ;;
        *)
            return 1
            ;;
    esac
}

use_profile() {
    local check_url="$DEFAULT_CHECK_URL"
    local old_profile
    local positional_name=""

    PROFILE_NAME=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --name)
                if [ $# -lt 2 ]; then
                    log_error "--name 需要参数"
                    exit 1
                fi
                PROFILE_NAME="$2"
                shift 2
                ;;
            --url)
                if [ $# -lt 2 ]; then
                    log_error "--url 需要参数"
                    exit 1
                fi
                check_url="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                if [ -n "$positional_name" ]; then
                    log_error "只能指定一个 profile"
                    exit 1
                fi
                positional_name="$1"
                shift
                ;;
        esac
    done

    if [ -z "$PROFILE_NAME" ]; then
        PROFILE_NAME="$positional_name"
    fi

    if [ -z "$PROFILE_NAME" ]; then
        log_error "use 需要指定 --name NAME"
        exit 1
    fi

    validate_profile_name "$PROFILE_NAME"
    ensure_base_dirs
    require_profile "$PROFILE_NAME"
    require_xray_config "$PROFILE_NAME"

    old_profile=$(current_profile_name 2>/dev/null || true)

    if [ -n "$old_profile" ] && [ "$old_profile" != "$PROFILE_NAME" ]; then
        stop_profile_runtime "$old_profile"
    fi

    index_set_current "$PROFILE_NAME"
    log_success "已选择 profile: $PROFILE_NAME"

    if ! resolve_xray >/dev/null 2>&1; then
        index_record_check "$PROFILE_NAME" "offline" ""
        print_xray_hint
        exit 1
    fi

    if service_installed "$PROFILE_NAME"; then
        start_service --name "$PROFILE_NAME"
    else
        start_client --name "$PROFILE_NAME"
    fi

    check_client --name "$PROFILE_NAME" --url "$check_url"
}

auto_use_profile() {
    local check_url="$DEFAULT_CHECK_URL"
    local name
    local priority
    local status
    local latency
    local failures
    local attempted=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --url)
                if [ $# -lt 2 ]; then
                    log_error "--url 需要参数"
                    exit 1
                fi
                check_url="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    ensure_base_dirs

    while IFS=$'\t' read -r name priority status latency failures; do
        [ -n "$name" ] || continue
        attempted=1
        log_info "尝试线路: ${name} priority=${priority} status=${status} latency=${latency} failures=${failures}"
        stop_profile_runtime "$name"

        if ( use_profile --name "$name" --url "$check_url" ); then
            log_success "auto-use 已选择可用线路: $name"
            return
        fi

        log_warn "线路不可用，继续尝试下一条: $name"
    done < <(index_emit_candidates)

    if [ "$attempted" -eq 0 ]; then
        log_error "没有 enabled=true 的候选 profile"
    else
        log_error "所有候选线路都不可用"
    fi

    exit 1
}

watch_once() {
    local check_url="$1"
    local current_name

    ensure_base_dirs
    current_name=$(current_profile_name 2>/dev/null || true)

    if [ -n "$current_name" ]; then
        log_info "检查 current profile: $current_name"
        if ( check_client --name "$current_name" --url "$check_url" ); then
            return 0
        fi
        log_warn "current profile 不可用，开始自动选线: $current_name"
    else
        log_warn "尚未选择 current profile，开始自动选线"
    fi

    if ( auto_use_profile --url "$check_url" ); then
        return 0
    fi

    return 1
}

watch_client() {
    local check_url="$DEFAULT_CHECK_URL"
    local interval="$DEFAULT_WATCH_INTERVAL"
    local once="0"

    while [ $# -gt 0 ]; do
        case "$1" in
            --interval)
                if [ $# -lt 2 ]; then
                    log_error "--interval 需要参数"
                    exit 1
                fi
                interval="$2"
                shift 2
                ;;
            --url)
                if [ $# -lt 2 ]; then
                    log_error "--url 需要参数"
                    exit 1
                fi
                check_url="$2"
                shift 2
                ;;
            --once)
                once="1"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    validate_interval "$interval"
    ensure_base_dirs

    if [ "$once" -eq 1 ]; then
        if watch_once "$check_url"; then
            log_success "watch once 完成，线路可用"
            return
        fi
        log_error "watch once 完成，没有可用线路"
        exit 1
    fi

    log_info "watcher 启动，interval=${interval}s url=${check_url}"

    while true; do
        if ! watch_once "$check_url"; then
            log_warn "本轮健康检查没有可用线路，等待下一轮"
        fi
        sleep "$interval"
    done
}

write_watch_launchd_plist() {
    local interval="$1"
    local check_url="$2"
    local plist
    local current_script
    local watch_log

    plist=$(watch_launchd_plist_file)
    current_script=$(script_path)
    watch_log=$(watcher_log_file)

    mkdir -p "$HOME/Library/LaunchAgents"
    touch "$watch_log"
    chmod 600 "$watch_log" 2>/dev/null || true

    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$(xml_escape "$(watch_service_label)")</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$(xml_escape "$current_script")</string>
    <string>watch</string>
    <string>--interval</string>
    <string>$(xml_escape "$interval")</string>
    <string>--url</string>
    <string>$(xml_escape "$check_url")</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>VRS_CLIENT_HOME</key>
    <string>$(xml_escape "$VRS_CLIENT_HOME")</string>
    <key>XRAY_BIN</key>
    <string>$(xml_escape "${XRAY_BIN:-}")</string>
    <key>VRS_SOCKS_PORT</key>
    <string>$(xml_escape "$SOCKS_PORT")</string>
    <key>VRS_HTTP_PORT</key>
    <string>$(xml_escape "$HTTP_PORT")</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$(xml_escape "$watch_log")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$watch_log")</string>
</dict>
</plist>
EOF

    chmod 600 "$plist"
}

write_watch_systemd_unit() {
    local interval="$1"
    local check_url="$2"
    local unit_file
    local current_script
    local watch_log

    unit_file=$(watch_systemd_unit_file)
    current_script=$(script_path)
    watch_log=$(watcher_log_file)

    mkdir -p "$(dirname "$unit_file")"
    touch "$watch_log"
    chmod 600 "$watch_log" 2>/dev/null || true

    cat > "$unit_file" <<EOF
[Unit]
Description=VRS Xray Client watcher
After=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash "$(systemd_escape "$current_script")" watch --interval "$(systemd_escape "$interval")" --url "$(systemd_escape "$check_url")"
Restart=always
RestartSec=5
Environment="VRS_CLIENT_HOME=$(systemd_escape "$VRS_CLIENT_HOME")"
Environment="XRAY_BIN=$(systemd_escape "${XRAY_BIN:-}")"
Environment="VRS_SOCKS_PORT=$(systemd_escape "$SOCKS_PORT")"
Environment="VRS_HTTP_PORT=$(systemd_escape "$HTTP_PORT")"
StandardOutput=append:$(systemd_escape "$watch_log")
StandardError=append:$(systemd_escape "$watch_log")

[Install]
WantedBy=default.target
EOF

    chmod 600 "$unit_file"
}

install_watch_service() {
    local interval="$DEFAULT_WATCH_INTERVAL"
    local check_url="$DEFAULT_CHECK_URL"
    local os_name
    local plist
    local unit

    while [ $# -gt 0 ]; do
        case "$1" in
            --interval)
                if [ $# -lt 2 ]; then
                    log_error "--interval 需要参数"
                    exit 1
                fi
                interval="$2"
                shift 2
                ;;
            --url)
                if [ $# -lt 2 ]; then
                    log_error "--url 需要参数"
                    exit 1
                fi
                check_url="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    validate_interval "$interval"
    ensure_base_dirs
    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            write_watch_launchd_plist "$interval" "$check_url"
            plist=$(watch_launchd_plist_file)
            launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
            launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || launchctl load -w "$plist"
            launchctl kickstart -k "gui/$(id -u)/$(watch_service_label)" >/dev/null 2>&1 || true
            log_success "已安装并启动 watcher launchd service: $(watch_service_label)"
            ;;
        Linux)
            if ! command -v systemctl >/dev/null 2>&1; then
                log_error "Linux watch-service 需要 systemctl"
                exit 1
            fi
            write_watch_systemd_unit "$interval" "$check_url"
            unit=$(watch_systemd_unit_name)
            systemctl --user daemon-reload
            systemctl --user enable --now "$unit"
            log_success "已安装并启动 watcher systemd user service: $unit"
            ;;
        *)
            log_error "不支援的本地系统: $os_name"
            exit 1
            ;;
    esac
}

uninstall_watch_service() {
    local os_name
    local plist
    local unit
    local unit_file

    ensure_base_dirs
    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            plist=$(watch_launchd_plist_file)
            launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || launchctl unload "$plist" >/dev/null 2>&1 || true
            rm -f "$plist"
            log_success "已移除 watcher launchd service: $(watch_service_label)"
            ;;
        Linux)
            if ! command -v systemctl >/dev/null 2>&1; then
                log_error "Linux watch-service 需要 systemctl"
                exit 1
            fi
            unit=$(watch_systemd_unit_name)
            unit_file=$(watch_systemd_unit_file)
            systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
            rm -f "$unit_file"
            systemctl --user daemon-reload
            log_success "已移除 watcher systemd user service: $unit"
            ;;
        *)
            log_error "不支援的本地系统: $os_name"
            exit 1
            ;;
    esac
}

start_watch_service() {
    local os_name
    local plist
    local unit

    ensure_base_dirs
    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            plist=$(watch_launchd_plist_file)
            if [ ! -f "$plist" ]; then
                log_error "找不到 watcher launchd plist，请先执行 watch-service install"
                exit 1
            fi
            launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || true
            launchctl kickstart -k "gui/$(id -u)/$(watch_service_label)"
            ;;
        Linux)
            unit=$(watch_systemd_unit_name)
            systemctl --user start "$unit"
            ;;
        *)
            log_error "不支援的本地系统: $os_name"
            exit 1
            ;;
    esac
}

stop_watch_service() {
    local os_name
    local plist
    local unit

    ensure_base_dirs
    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            plist=$(watch_launchd_plist_file)
            launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || launchctl unload "$plist"
            ;;
        Linux)
            unit=$(watch_systemd_unit_name)
            systemctl --user stop "$unit"
            ;;
        *)
            log_error "不支援的本地系统: $os_name"
            exit 1
            ;;
    esac
}

restart_watch_service() {
    local os_name
    local unit

    ensure_base_dirs
    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            launchctl kickstart -k "gui/$(id -u)/$(watch_service_label)"
            ;;
        Linux)
            unit=$(watch_systemd_unit_name)
            systemctl --user restart "$unit"
            ;;
        *)
            log_error "不支援的本地系统: $os_name"
            exit 1
            ;;
    esac
}

status_watch_service() {
    local os_name
    local unit

    ensure_base_dirs
    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            launchctl print "gui/$(id -u)/$(watch_service_label)"
            ;;
        Linux)
            unit=$(watch_systemd_unit_name)
            systemctl --user status "$unit"
            ;;
        *)
            log_error "不支援的本地系统: $os_name"
            exit 1
            ;;
    esac
}

watch_service_client() {
    local service_action="${1:-}"

    if [ -z "$service_action" ]; then
        log_error "watch-service 需要子命令: install|uninstall|start|stop|restart|status"
        exit 1
    fi

    shift

    case "$service_action" in
        install)
            install_watch_service "$@"
            ;;
        uninstall)
            uninstall_watch_service "$@"
            ;;
        start)
            start_watch_service "$@"
            ;;
        stop)
            stop_watch_service "$@"
            ;;
        restart)
            restart_watch_service "$@"
            ;;
        status)
            status_watch_service "$@"
            ;;
        *)
            log_error "未知 watch-service 子命令: $service_action"
            exit 1
            ;;
    esac
}

export_profile() {
    local file

    parse_profile_args "$@"
    ensure_base_dirs
    require_profile "$PROFILE_NAME"
    file=$(profile_file "$PROFILE_NAME")
    cat "$file"
}

show_paths() {
    parse_profile_args "$@"
    ensure_base_dirs

    echo "Client home: $VRS_CLIENT_HOME"
    echo "Profile: $(profile_file "$PROFILE_NAME")"
    echo "Xray config: $(xray_config_file "$PROFILE_NAME")"
    echo "PID file: $(pid_file "$PROFILE_NAME")"
    echo "Access log: $(access_log_file "$PROFILE_NAME")"
    echo "Error log: $(error_log_file "$PROFILE_NAME")"
    echo "Runner log: $(runner_log_file "$PROFILE_NAME")"
    echo "Watcher log: $(watcher_log_file)"
}

check_core() {
    local xray_bin

    if ! xray_bin=$(resolve_xray); then
        print_xray_hint
        exit 1
    fi

    log_success "找到 Xray-core: $xray_bin"
    "$xray_bin" version
}

install_core_with_brew() {
    if ! command -v brew >/dev/null 2>&1; then
        return 1
    fi

    log_info "使用 Homebrew 安装 Xray-core"
    brew install xray
}

install_core_with_official_linux_script() {
    local temp_script
    local runner

    if ! command -v curl >/dev/null 2>&1; then
        log_error "Linux 自动安装需要 curl"
        exit 1
    fi

    temp_script=$(mktemp)
    log_info "下载 XTLS 官方 Xray 安装脚本"
    curl -fsSL "$XRAY_INSTALL_SCRIPT_URL" -o "$temp_script"
    chmod 700 "$temp_script"

    if [ "$(id -u)" -eq 0 ]; then
        runner=(bash "$temp_script")
    else
        if ! command -v sudo >/dev/null 2>&1; then
            log_error "Linux 自动安装需要 root 或 sudo"
            rm -f "$temp_script"
            exit 1
        fi
        runner=(sudo bash "$temp_script")
    fi

    log_info "使用 XTLS 官方安装脚本安装 Xray-core"
    "${runner[@]}" install --without-logfiles --no-update-service
    rm -f "$temp_script"
}

install_core() {
    local os_name

    if resolve_xray >/dev/null 2>&1; then
        log_success "Xray-core 已存在"
        check_core
        return
    fi

    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            if ! install_core_with_brew; then
                log_error "macOS 自动安装需要 Homebrew。请先安装 Homebrew 后重试。"
                exit 1
            fi
            ;;
        Linux)
            if ! install_core_with_brew; then
                install_core_with_official_linux_script
            fi
            ;;
        *)
            log_error "不支援的本地系统: $os_name"
            exit 1
            ;;
    esac

    check_core
}

main() {
    local command_name="${1:-help}"

    if [ $# -gt 0 ]; then
        shift
    fi

    case "$command_name" in
        import)
            import_profile "$@"
            ;;
        use)
            use_profile "$@"
            ;;
        auto-use)
            auto_use_profile "$@"
            ;;
        current)
            current_profile "$@"
            ;;
        start)
            start_client "$@"
            ;;
        stop)
            stop_client "$@"
            ;;
        restart)
            restart_client "$@"
            ;;
        status)
            status_client "$@"
            ;;
        check)
            check_client "$@"
            ;;
        watch)
            watch_client "$@"
            ;;
        logs)
            logs_client "$@"
            ;;
        list)
            list_profiles "$@"
            ;;
        export)
            export_profile "$@"
            ;;
        config)
            show_paths "$@"
            ;;
        check-core)
            check_core "$@"
            ;;
        install-core)
            install_core "$@"
            ;;
        service)
            service_client "$@"
            ;;
        watch-service)
            watch_service_client "$@"
            ;;
        run-foreground)
            run_foreground "$@"
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            log_error "未知命令: $command_name"
            usage
            exit 1
            ;;
    esac
}

main "$@"
