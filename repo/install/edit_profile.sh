#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — edit_profile.sh
#  Interactive profile editor — show all fields, edit by number
#  Pre-filled with default.conf values
# ==============================================================================

# ------------------------------------------------------------------------------
# Load defaults if not already set
# ------------------------------------------------------------------------------

source "$PROFILES_DIR/default.conf"

# ------------------------------------------------------------------------------
# Display
# ------------------------------------------------------------------------------

render_editor() {
    clear
    echo "================================================="
    echo "            Profile Editor"
    echo "================================================="
    echo
    printf "  [1]  Hostname         : %s\n" "${INSTALL_HOSTNAME:-<unset>}"
    printf "  [2]  Username         : %s\n" "${USERNAME:-<unset>}"
    printf "  [3]  Shell            : %s\n" "${USER_SHELL:-<unset>}"
    printf "  [4]  Timezone         : %s\n" "${TIMEZONE:-<unset>}"
    printf "  [5]  Target Disk      : %s\n" "${TARGET_DISK:-<unset>}"
    printf "  [6]  Wipe Mode        : %s\n" "${DISK_WIPE_MODE:-<unset>}"
    printf "  [7]  Root Filesystem  : %s\n" "${ROOT_FS:-<unset>}"
    printf "  [8]  EFI Size         : %s\n" "${EFI_SIZE:-<unset>}"
    printf "  [9]  Secure Boot Mode : %s\n" "${SB_MODE:-<unset>}"
    printf "  [10] Mirror Countries : %s\n" "${MIRROR_COUNTRIES:-<unset>}"
    printf "  [11] Parallel DLs     : %s\n" "${PACMAN_PARALLEL_CHROOT:-<unset>}"
    printf "  [12] Desktop          : %s\n" "${DESKTOP_ENV:-<unset>}"
    printf "  [13] Extra Packages   : %s\n" "${EXTRA_PACKAGES:-<none>}"
    echo
    echo "-----------------------------------------------"
    echo "  Enter field number to edit"
    echo "  Press ENTER when done"
    echo "  Press Q to abort"
    echo
}

# ------------------------------------------------------------------------------
# Field editors
# ------------------------------------------------------------------------------

edit_field() {
    local field="$1"

    case "$field" in
        1)
            read -rp "  Hostname [$INSTALL_HOSTNAME]: " val
            [[ -n "${val:-}" ]] && INSTALL_HOSTNAME="$val"
            ;;
        2)
            read -rp "  Username [$USERNAME]: " val
            [[ -n "${val:-}" ]] && USERNAME="$val"
            ;;
        3)
            echo "  Options: bash zsh fish dash"
            read -rp "  Shell [$USER_SHELL]: " val
            [[ -n "${val:-}" ]] && USER_SHELL="$val"
            ;;
        4)
            read -rp "  Timezone [$TIMEZONE]: " val
            if [[ -n "${val:-}" ]]; then
                if timedatectl list-timezones | grep -qx "$val"; then
                    TIMEZONE="$val"
                else
                    echo "  [!] Invalid timezone: $val"
                    sleep 1
                fi
            fi
            ;;
        5)
            echo "  Available disks:"
            lsblk -d -o NAME,SIZE,MODEL | grep -v "^loop"
            read -rp "  Target disk [$TARGET_DISK]: " val
            if [[ -n "${val:-}" ]]; then
                # Ensure /dev/ prefix
                [[ "$val" == /dev/* ]] || val="/dev/$val"
                TARGET_DISK="$val"
            fi
            ;;
        6)
            echo "  Options: quick zeros random"
            read -rp "  Wipe mode [$DISK_WIPE_MODE]: " val
            if [[ -n "${val:-}" ]]; then
                case "$val" in
                    quick|zeros|random) DISK_WIPE_MODE="$val" ;;
                    *) echo "  [!] Invalid: $val"; sleep 1 ;;
                esac
            fi
            ;;
        7)
            echo "  Options: ext4 btrfs"
            read -rp "  Root filesystem [$ROOT_FS]: " val
            if [[ -n "${val:-}" ]]; then
                case "$val" in
                    ext4|btrfs) ROOT_FS="$val" ;;
                    *) echo "  [!] Invalid: $val"; sleep 1 ;;
                esac
            fi
            ;;
        8)
            echo "  Options: 512MiB 1GiB"
            read -rp "  EFI size [$EFI_SIZE]: " val
            if [[ -n "${val:-}" ]]; then
                case "$val" in
                    512MiB|1GiB) EFI_SIZE="$val" ;;
                    *) echo "  [!] Invalid: $val"; sleep 1 ;;
                esac
            fi
            ;;
        9)
            echo "  Options: custom microsoft"
            read -rp "  Secure Boot mode [$SB_MODE]: " val
            if [[ -n "${val:-}" ]]; then
                case "$val" in
                    custom|microsoft) SB_MODE="$val" ;;
                    *) echo "  [!] Invalid: $val"; sleep 1 ;;
                esac
            fi
            ;;
        10)
            read -rp "  Mirror countries [$MIRROR_COUNTRIES]: " val
            [[ -n "${val:-}" ]] && MIRROR_COUNTRIES="$val"
            ;;
        11)
            read -rp "  Parallel downloads [$PACMAN_PARALLEL_CHROOT]: " val
            if [[ -n "${val:-}" ]]; then
                if [[ "$val" =~ ^[0-9]+$ ]]; then
                    PACMAN_PARALLEL_CHROOT="$val"
                else
                    echo "  [!] Must be numeric"
                    sleep 1
                fi
            fi
            ;;
        12)
            echo "  Options: kde, hyprland, jakoolit, none"
            read -rp "  Desktop [$DESKTOP_ENV]: " val
            if [[ -n "${val:-}" ]]; then
                case "$val" in
                    kde|hyprland|jakoolit|none) DESKTOP_ENV="$val" ;;
                    *) echo "  [!] Invalid: $val"; sleep 1 ;;
                esac
            fi
            ;;
        13)
            echo "  Space-separated package names"
            read -rp "  Extra packages [${EXTRA_PACKAGES:-none}]: " val
            [[ -n "${val:-}" ]] && EXTRA_PACKAGES="$val"
            ;;
        *)
            echo "  [!] Invalid field number"
            sleep 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Export final values
# ------------------------------------------------------------------------------

export_profile() {
    # Normalize EXTRA_PACKAGES to single space-separated line
    EXTRA_PACKAGES=$(echo "$EXTRA_PACKAGES" | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')

    export INSTALL_HOSTNAME
    export USERNAME
    export USER_SHELL
    export TIMEZONE
    export TARGET_DISK
    export DISK_WIPE_MODE
    export ROOT_FS
    export EFI_SIZE
    export SB_MODE
    export MIRROR_COUNTRIES
    export PACMAN_PARALLEL_CHROOT
    export DESKTOP_ENV
    export EXTRA_PACKAGES

    log "[*] Profile saved."
}

# ------------------------------------------------------------------------------
# Main loop
# ------------------------------------------------------------------------------

while true; do
    render_editor
    read -rp "  Choice: " choice

    case "${choice:-}" in
        "")
            export_profile
            break
            ;;
        Q|q)
            fatal "Installation aborted by user."
            ;;
        [0-9]*)
            edit_field "$choice"
            ;;
        *)
            echo "  [!] Invalid input"
            sleep 1
            ;;
    esac
done
