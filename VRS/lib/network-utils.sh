#!/bin/bash

# Shared network / encoding helpers used by VRS installers.

if ! declare -f log_warn >/dev/null; then
    log_warn() { echo "[WARN] $1"; }
fi

# Strict IPv4 (dotted quad, 0-255 each).
is_valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local octet
    for octet in "${BASH_REMATCH[@]:1}"; do
        (( octet >= 0 && octet <= 255 )) || return 1
    done
    return 0
}

# Loose IPv6 — covers full, compressed (::), and IPv4-mapped forms. Rejects anything with whitespace or quotes.
is_valid_ipv6() {
    local ip="$1"
    [[ "$ip" =~ [[:space:]\"\\] ]] && return 1
    [[ "$ip" =~ ^[0-9a-fA-F:]+(\.[0-9.]+)?$ ]] || return 1
    [[ "$ip" == *::*::* ]] && return 1
    return 0
}

is_valid_ip() {
    is_valid_ipv4 "$1" || is_valid_ipv6 "$1"
}

# Detect server's public IPv4 with strict validation.
# Tries multiple providers; rejects any non-IP response (e.g. HTML error page, banner with newline).
# Echoes the IP on success, empty string on failure.
detect_public_ipv4() {
    local providers=(
        "https://ifconfig.me"
        "https://api.ipify.org"
        "https://ip.sb"
        "https://ipinfo.io/ip"
    )
    local provider raw candidate
    for provider in "${providers[@]}"; do
        raw=$(curl -fsS4 --max-time 5 "$provider" 2>/dev/null) || continue
        candidate=$(printf '%s' "$raw" | tr -d '[:space:]')
        if is_valid_ipv4 "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

# JSON-escape a string (RFC 8259): backslash, double-quote, control chars (U+0000-U+001F), DEL.
# Prefers jq when available for full correctness; falls back to a portable awk implementation.
json_escape() {
    local input="$1"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$input" | jq -Rs '.[1:-1]' 2>/dev/null
        return 0
    fi
    # Fallback: handle backslash, double quote, and the seven named control escapes.
    # Other control characters (< 0x20) are emitted as \u00XX.
    LC_ALL=C awk -v RS='' '
        BEGIN { for (i = 0; i < 32; i++) ctrl[sprintf("%c", i)] = sprintf("\\u%04x", i) }
        {
            s = $0
            out = ""
            n = length(s)
            for (k = 1; k <= n; k++) {
                c = substr(s, k, 1)
                if (c == "\\") { out = out "\\\\"; continue }
                if (c == "\"") { out = out "\\\""; continue }
                if (c == "\b") { out = out "\\b"; continue }
                if (c == "\f") { out = out "\\f"; continue }
                if (c == "\n") { out = out "\\n"; continue }
                if (c == "\r") { out = out "\\r"; continue }
                if (c == "\t") { out = out "\\t"; continue }
                if (c in ctrl) { out = out ctrl[c]; continue }
                out = out c
            }
            printf "%s", out
        }' <<< "$input"
}

# Convert standard base64 (with +/=) to URL-safe base64 (no padding).
to_base64url() {
    printf '%s' "$1" | tr '+/' '-_' | tr -d '='
}

# Encode raw bytes from stdin to URL-safe base64 (no padding).
base64url_encode() {
    base64 -w 0 2>/dev/null | tr '+/' '-_' | tr -d '=' || \
        openssl base64 -A | tr '+/' '-_' | tr -d '='
}
