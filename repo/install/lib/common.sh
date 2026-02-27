#!/usr/bin/env bash
set -euo pipefail

confirm() {
    local prompt="$1"
    local ans=""
    read -r -p "$prompt (y/N): " ans || true
    [[ "${ans,,}" == "y" ]]
}

ensure_root() {
    [[ $EUID -eq 0 ]] || fatal "Must be run as root."
}

internet_ok() {
    curl -s --fail --connect-timeout 5 https://archlinux.org/ -o /dev/null
}