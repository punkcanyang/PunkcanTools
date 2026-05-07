#!/bin/bash

# Percent-encode one URI component without relying on python3 or external tools.
# This is intended for generated ASCII credentials and query values.

uri_encode_component() {
    local input="$1"
    local encoded=""
    local char
    local hex
    local i

    LC_ALL=C
    for ((i = 0; i < ${#input}; i++)); do
        char="${input:i:1}"
        case "$char" in
            [a-zA-Z0-9.~_-])
                encoded+="$char"
                ;;
            *)
                printf -v hex '%%%02X' "'$char"
                encoded+="$hex"
                ;;
        esac
    done

    printf '%s' "$encoded"
}
