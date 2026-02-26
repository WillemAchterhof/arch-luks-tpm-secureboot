#!/usr/bin/env bash
set -euo pipefail

confirm() {
    local prompt="$1"
    read -rp "$prompt (y/N): " ans
    [[ "${ans,,}" == "y" ]]
}

ensure_root() {
    [[ $EUID -eq 0 ]] || { log "[ERROR] Must be run as root."; exit 1; }
}

has_internet() {
    curl -s --head --fail --max-time 3 https://archlinux.org >/dev/null \
        || ping -c1 -W1 1.1.1.1 >/dev/null 2>&1
}
