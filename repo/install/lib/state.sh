#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$INSTALL_FOLDER/state"
STATE_FILE="$INSTALL_FOLDER/state/arch-installer.state"

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
