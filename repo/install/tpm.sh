#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — precheck.sh
#  Pre-flight checks before any destructive action
#  Runs at the start of the execute phase
# ==============================================================================

CHECKS_PASSED=true

fail_check() {
    log "[!] FAIL: $*"
    CHECKS_PASSED=false
}

pass_check() {
    log "[+] OK:   $*"
}

# ==============================================================================
# INTERNET
# ==============================================================================

check_internet() {
    if curl -s --fail --connect-timeout 5 https://archlinux.org/ -o /dev/null; then
        pass_check "Internet connectivity"
    else
        fail_check "No internet — required for pacstrap"
    fi
}

# ==============================================================================
# REQUIRED COMMANDS
# ==============================================================================

check_commands() {
    local required=(
        sgdisk
        wipefs
        cryptsetup
        sbctl
        reflector
        pacstrap
        genfstab
        arch-chroot
        partprobe
        mkfs.fat
        mkfs.ext4
        blkid
        lsblk
        efibootmgr
        mkinitcpio
        timedatectl
        systemctl
        curl
        git
    )

    for cmd in "${required[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            pass_check "Command found: $cmd"
        else
            fail_check "Missing command: $cmd"
        fi
    done
}

# ==============================================================================
# TPM2
# ==============================================================================

check_tpm() {
    if [[ -d /sys/class/tpm/tpm0 ]]; then
        pass_check "TPM2 device present: /sys/class/tpm/tpm0"
    else
        fail_check "No TPM2 device detected — TPM auto-unlock will not be available"
    fi
}

# ==============================================================================
# PROFILE VALIDATION
# ==============================================================================

check_profile() {
    log "[*] Validating profile variables..."

    # HOSTNAME — no spaces, no special chars, max 63 chars
    if [[ -n "${HOSTNAME:-}" ]]; then
        if [[ "$HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$ ]]; then
            pass_check "HOSTNAME: $HOSTNAME"
        else
            fail_check "HOSTNAME invalid (letters, numbers, hyphens only, max 63 chars): $HOSTNAME"
        fi
    else
        fail_check "HOSTNAME is not set"
    fi

    # USERNAME — lowercase, no special chars, no spaces
    if [[ -n "${USERNAME:-}" ]]; then
        if [[ "$USERNAME" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
            pass_check "USERNAME: $USERNAME"
        else
            fail_check "USERNAME invalid (lowercase, start with letter, max 32 chars): $USERNAME"
        fi
    else
        fail_check "USERNAME is not set"
    fi

    # USER_SHELL — must be a known shell name or path
    if [[ -n "${USER_SHELL:-}" ]]; then
        local shell_pkg
        shell_pkg="$(basename "$USER_SHELL")"
        if [[ "$shell_pkg" =~ ^(bash|zsh|fish|dash)$ ]]; then
            pass_check "USER_SHELL: $USER_SHELL"
        else
            fail_check "USER_SHELL unrecognised: $USER_SHELL (expected bash, zsh, fish, or dash)"
        fi
    else
        fail_check "USER_SHELL is not set"
    fi

    # TIMEZONE — must exist in timedatectl list
    if [[ -n "${TIMEZONE:-}" ]]; then
        if timedatectl list-timezones | grep -qx "$TIMEZONE"; then
            pass_check "TIMEZONE: $TIMEZONE"
        else
            fail_check "TIMEZONE invalid: $TIMEZONE"
        fi
    else
        fail_check "TIMEZONE is not set"
    fi

    # SB_MODE — must be microsoft or custom
    if [[ -n "${SB_MODE:-}" ]]; then
        if [[ "$SB_MODE" == "microsoft" || "$SB_MODE" == "custom" ]]; then
            pass_check "SB_MODE: $SB_MODE"
        else
            fail_check "SB_MODE invalid: $SB_MODE (expected microsoft or custom)"
        fi
    else
        fail_check "SB_MODE is not set"
    fi

    # TARGET_DISK — must be set and a valid block device
    if [[ -z "${TARGET_DISK:-}" ]]; then
        fail_check "TARGET_DISK is not set"
    else
        if [[ -b "$TARGET_DISK" ]]; then
            pass_check "TARGET_DISK exists: $TARGET_DISK"
        else
            fail_check "TARGET_DISK is not a valid block device: $TARGET_DISK"
        fi

        # Must be a whole disk, not a partition
        local dtype
        dtype=$(lsblk -d -no TYPE "$TARGET_DISK" 2>/dev/null) || true
        if [[ "$dtype" == "disk" ]]; then
            pass_check "TARGET_DISK is a whole disk: $TARGET_DISK"
        else
            fail_check "TARGET_DISK is not a whole disk (partition selected?): $TARGET_DISK"
        fi

        # Must not be the USB installer device
        local usb_dev
        [[ -n "${USB_ROOT:-}" ]] || fatal "USB_ROOT is not defined"
        usb_dev=$(df "$USB_ROOT" 2>/dev/null | awk 'NR==2 {print $1}') || true
        case "$usb_dev" in
            /dev/nvme[0-9]*n[0-9]*p[0-9]*) usb_dev="${usb_dev%p*}" ;;
            /dev/mmcblk[0-9]*p[0-9]*)      usb_dev="${usb_dev%p*}" ;;
            /dev/[a-z]*[0-9]*)             usb_dev="${usb_dev%%[0-9]*}" ;;
        esac

        if [[ "$TARGET_DISK" == "$usb_dev" ]]; then
            fail_check "TARGET_DISK matches USB installer device: $TARGET_DISK"
        else
            pass_check "TARGET_DISK is not the USB installer: $TARGET_DISK"
        fi

        # Must not be mounted (checks all partitions on the disk)
        if lsblk -nr -o MOUNTPOINT "$TARGET_DISK" | grep -q .; then
            fail_check "TARGET_DISK or its partitions are mounted: $TARGET_DISK"
        else
            pass_check "TARGET_DISK is not mounted: $TARGET_DISK"
        fi
    fi

    # PACMAN_PARALLEL_CHROOT — must be numeric
    if [[ -n "${PACMAN_PARALLEL_CHROOT:-}" ]]; then
        if [[ "$PACMAN_PARALLEL_CHROOT" =~ ^[0-9]+$ ]]; then
            pass_check "PACMAN_PARALLEL_CHROOT: $PACMAN_PARALLEL_CHROOT"
        else
            fail_check "PACMAN_PARALLEL_CHROOT must be numeric: $PACMAN_PARALLEL_CHROOT"
        fi
    fi

    # EXTRA_PACKAGES — no dangerous characters
    if [[ -n "${EXTRA_PACKAGES:-}" ]]; then
        if [[ "$EXTRA_PACKAGES" =~ [^a-zA-Z0-9_\ \-] ]]; then
            fail_check "EXTRA_PACKAGES contains invalid characters: $EXTRA_PACKAGES"
        else
            pass_check "EXTRA_PACKAGES: $EXTRA_PACKAGES"
        fi
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================

log "[*] Running pre-flight checks..."
echo
echo "================================================="
echo "   Pre-flight Checks"
echo "================================================="
echo

check_internet
check_commands
check_tpm
check_profile

echo

if [[ "$CHECKS_PASSED" == "false" ]]; then
    fatal "One or more pre-flight checks failed — aborting installation."
fi

log "[*] All pre-flight checks passed."
