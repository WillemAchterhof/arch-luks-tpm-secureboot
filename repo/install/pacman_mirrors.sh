#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — pacman_mirrors.sh
#  Configures NTP, timezone, mirrors, and pacman parallel downloads
#  Uses profile defaults where set, interactive fallback otherwise
# ==============================================================================

# ==============================================================================
# NTP
# ==============================================================================

setup_ntp() {
    log "[*] Enabling NTP..."
    timedatectl set-ntp true
}

# ==============================================================================
# TIMEZONE
# ==============================================================================

setup_timezone() {
    if [[ -z "${TIMEZONE:-}" ]]; then
        echo
        echo "================================================="
        echo "   Timezone"
        echo "================================================="
        echo
        read -rp "  Enter timezone [Europe/Amsterdam]: " TIMEZONE
        TIMEZONE="${TIMEZONE:-Europe/Amsterdam}"
    fi

    timedatectl list-timezones | grep -qx "$TIMEZONE" \
        || fatal "Invalid timezone: $TIMEZONE"

    log "[*] Setting timezone: $TIMEZONE"
    timedatectl set-timezone "$TIMEZONE"
}

# ==============================================================================
# MIRRORS
# ==============================================================================

setup_mirrors() {
    if [[ -z "${MIRROR_COUNTRIES:-}" ]]; then
        echo
        echo "================================================="
        echo "   Mirror Countries"
        echo "================================================="
        echo
        echo "  Enter comma-separated countries for reflector."
        echo "  Example: Netherlands,Germany,France"
        echo
        read -rp "  Countries [Netherlands,Germany]: " MIRROR_COUNTRIES
        MIRROR_COUNTRIES="${MIRROR_COUNTRIES:-Netherlands,Germany}"
    fi

    log "[*] Running reflector for: $MIRROR_COUNTRIES"

    reflector \
        --country "$MIRROR_COUNTRIES" \
        --age 10 \
        --protocol https \
        --sort rate \
        --save /etc/pacman.d/mirrorlist \
        || fatal "reflector failed — check internet connection and country names."

    log "[*] Mirrorlist updated."
}

# ==============================================================================
# PACMAN LIVE ISO CONFIG
# ==============================================================================

setup_pacman_config() {
    log "[*] Configuring pacman on live ISO..."

    sed -i \
        -e 's/^#Color/Color/' \
        -e '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' \
        /etc/pacman.conf

    log "[*] Syncing package databases..."
    pacman -Sy --noconfirm \
        || fatal "pacman -Sy failed — check mirrors."

    log "[*] pacman configured and databases synced."
}

# ==============================================================================
# PACMAN PARALLEL DOWNLOADS
# ==============================================================================

setup_pacman_downloads() {
    local iso_parallel="${PACMAN_PARALLEL_ISO:-50}"
    local chroot_parallel="${PACMAN_PARALLEL_CHROOT:-20}"

    [[ "$iso_parallel" =~ ^[0-9]+$ ]] \
        || fatal "PACMAN_PARALLEL_ISO must be numeric: $iso_parallel"

    [[ "$chroot_parallel" =~ ^[0-9]+$ ]] \
        || fatal "PACMAN_PARALLEL_CHROOT must be numeric: $chroot_parallel"

    # Live ISO — used for pacstrap
    log "[*] Setting ParallelDownloads=$iso_parallel on live ISO..."
    sed -i "s/^#\?ParallelDownloads.*/ParallelDownloads = $iso_parallel/" \
        /etc/pacman.conf

    # Chroot value stored for system.sh to apply after pacstrap
    export PACMAN_PARALLEL_CHROOT="$chroot_parallel"
    log "[*] PACMAN_PARALLEL_CHROOT=$chroot_parallel (applied by system.sh after pacstrap)"
}

# ==============================================================================
# MAIN
# ==============================================================================

setup_ntp
setup_timezone
setup_mirrors
setup_pacman_config
setup_pacman_downloads

log "[*] pacman_mirrors.sh complete."
