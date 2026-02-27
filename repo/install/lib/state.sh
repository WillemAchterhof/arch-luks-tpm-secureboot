#!/usr/bin/env bash
set -euo pipefail

: "${STATE_FOLDER:?STATE_FOLDER not set}"

_STATE_FILE="$STATE_FOLDER/install.state"

# Allowed states (whitelist)
_VALID_STATES=(
    init
    secureboot
    diskdetect
    profile
    summary
    confirm
    execute
    done
)

_is_valid_state() {
    local s="$1"
    for v in "${_VALID_STATES[@]}"; do
        [[ "$v" == "$s" ]] && return 0
    done
    return 1
}

load_state() {
    if [[ -f "$_STATE_FILE" ]]; then
        STATE="$(<"$_STATE_FILE")"

        if ! _is_valid_state "$STATE"; then
            fatal "Invalid state detected: $STATE"
        fi
    else
        STATE="init"
    fi
}

save_state() {
    _is_valid_state "$STATE" || fatal "Refusing to save invalid state: $STATE"

    local tmp="$_STATE_FILE.tmp"

    printf '%s\n' "$STATE" > "$tmp"
    mv "$tmp" "$_STATE_FILE"
}