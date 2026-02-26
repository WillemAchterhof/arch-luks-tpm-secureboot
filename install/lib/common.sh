#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  common.sh — Shared helper library for the Arch Secure Installer
# ==============================================================================

: "${VERBOSE:=true}"
: "${LOG_FILE:=/tmp/installer.log}"
: "${REPO_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# ==============================================================================
# LOGGING
# ==============================================================================

log() {
    [[ "$VERBOSE" == true ]] || return 0
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
        | tee -a "$LOG_FILE"
}

info()  { log "[INFO]  $*"; }
warn()  { log "[WARN]  $*"; }
error() { log "[ERROR] $*"; }

fatal() {
    error "$*"
    exit 1
}

# ==============================================================================
# ROOT CHECK
# ==============================================================================

ensure_root() {
    [[ $EUID -eq 0 ]] || fatal "This script must be run as root."
}

# ==============================================================================
# INTERNET CHECK
# ==============================================================================

has_internet() {
    curl -s --head --fail --max-time 3 https://archlinux.org >/dev/null 2>&1 \
        || ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1
}

wait_for_internet() {
    local attempts="${1:-5}"
    for ((i=1; i<=attempts; i++)); do
        has_internet && return 0
        sleep 2
    done
    return 1
}

# ==============================================================================
# RETRY WRAPPER
# ==============================================================================

retry() {
    local attempts="$1"; shift
    local delay=2

    for ((i=1; i<=attempts; i++)); do
        "$@" && return 0
        sleep "$delay"
        delay=$((delay * 2))
    done

    return 1
}

# ==============================================================================
# FETCH FILE (with retry)
# ==============================================================================

fetch_file() {
    local url="$1" dest="$2"
    info "Fetching: $url"
    retry 3 curl -fsSL --max-time 15 "$url" -o "$dest" \
        || fatal "Failed to fetch $url"
}

# ==============================================================================
# UEFI CHECK
# ==============================================================================

ensure_uefi() {
    [[ -d /sys/firmware/efi/efivars ]] \
        || fatal "System not booted in UEFI mode. Secure Boot requires UEFI."
}

# ==============================================================================
# ANSI STRIPPER
# ==============================================================================

strip_ansi() {
    sed -E 's/\x1b\[[0-9;]*m//g'
}

# ==============================================================================
# WIFI ADAPTER DETECTION
# ==============================================================================

get_wifi_adapter() {
    iwctl device list 2>/dev/null \
    | awk '
        BEGIN { ansi = "\033\[[0-9;]*m" }
        NR <= 4 { next }
        /^-+/ { next }
        {
            gsub(ansi, "")
            if ($2 == "station") { print $1; exit }
        }'
}

# ==============================================================================
# SAFE FILE WRITING
# ==============================================================================

write_file() {
    local dest="$1"
    shift
    mkdir -p "$(dirname "$dest")"
    printf "%s\n" "$@" > "$dest"
}

append_file() {
    local dest="$1"
    shift
    mkdir -p "$(dirname "$dest")"
    printf "%s\n" "$@" >> "$dest"
}

# ==============================================================================
# CONFIRMATION PROMPTS
# ==============================================================================

confirm() {
    local prompt="$1"
    read -rp "$prompt (y/N): " ans
    [[ "${ans,,}" == "y" ]]
}
