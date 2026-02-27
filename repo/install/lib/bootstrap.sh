#!/usr/bin/env bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$LIB_DIR/file_paths.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/common.sh"

ensure_uefi() {
    [[ -d /sys/firmware/efi ]] || fatal "System not booted in UEFI mode."
}

batch() {
    local script="$1"
    [[ -f "$script" ]] || fatal "Missing phase: $script"
    log "[*] Running: $(basename "$script")"
    source "$script"
}