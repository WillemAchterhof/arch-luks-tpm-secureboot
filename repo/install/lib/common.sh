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
    curl -s --fail --max-time 5 https://archlinux.org/mirrorlist/ -o /dev/null \
        || curl -s --fail --max-time 5 https://google.com -o /dev/null \
        || ping -c1 -W2 1.1.1.1 >/dev/null 2>&1
}
