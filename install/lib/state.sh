#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="/tmp/arch-installer.state"

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        STATE=$(<"$STATE_FILE")
    else
        STATE="precheck"
    fi
}

save_state() {
    echo "$STATE" > "$STATE_FILE"
}
