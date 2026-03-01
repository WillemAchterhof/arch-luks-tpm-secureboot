#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — secureboot_enroll.sh
#  Enroll Secure Boot keys (custom mode)
#  or build/sign UKI only (microsoft mode)
# ==============================================================================

: "${SB_MODE:?SB_MODE not set}"

MNT="/mnt"

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================

preflight_checks() {
    log "[*] Running Secure Boot pre-flight checks..."

    [[ -d /sys/firmware/efi ]] \
        || fatal "System not booted in UEFI mode."

    mountpoint -q "$MNT" \
        || fatal "$MNT is not mounted."

    arch-chroot "$MNT" command -v sbctl >/dev/null 2>&1 \
        || fatal "sbctl not installed in target system."

    arch-chroot "$MNT" command -v mkinitcpio >/dev/null 2>&1 \
        || fatal "mkinitcpio not installed in target system."

    log "[*] Pre-flight checks OK."
}

# ==============================================================================
# VERIFY SETUP MODE
# ==============================================================================

verify_setup_mode() {
    log "[*] Checking firmware Setup Mode..."

    local status
    status="$(arch-chroot "$MNT" sbctl status 2>/dev/null || true)"
    echo "$status"

    if ! echo "$status" | grep -qiE "Setup Mode:\s*(enabled|true|yes)"; then
        fatal "Firmware is NOT in Setup Mode.
Enter UEFI firmware, clear Secure Boot keys, and rerun."
    fi

    log "[*] Setup Mode confirmed."
}

# ==============================================================================
# VERIFY SECURE BOOT ENABLED POST-ENROLLMENT
# ==============================================================================

verify_secureboot_enabled() {
    log "[*] Verifying Secure Boot is enabled after enrollment..."

    local status
    status="$(arch-chroot "$MNT" sbctl status 2>/dev/null || true)"

    if ! echo "$status" | grep -qiE "Secure Boot:\s*(enabled|true|yes)"; then
        fatal "Secure Boot is NOT enabled after enrollment.
Enter UEFI firmware, enable Secure Boot, and rerun."
    fi

    log "[*] Secure Boot is enabled."
}

# ==============================================================================
# CUSTOM KEYS — CREATE AND ENROLL
# ==============================================================================

enroll_custom_keys() {
    log "[*] Creating Secure Boot keys..."
    arch-chroot "$MNT" sbctl create-keys

    log "[*] Building and signing UKI..."
    arch-chroot "$MNT" mkinitcpio -P

    clear
    echo "================================================="
    echo "   WARNING — SECURE BOOT KEY ENROLLMENT"
    echo "================================================="
    echo
    echo "  This will:"
    echo "    - Enroll custom PK/KEK/DB keys"
    echo "    - Remove Microsoft keys"
    echo "    - Allow ONLY your signed kernels to boot"
    echo
    echo "  Type ENROLL to continue:"
    echo

    local confirm
    read -rp "> " confirm
    [[ "$confirm" == "ENROLL" ]] \
        || fatal "Secure Boot enrollment aborted."

    log "[*] Enrolling keys into firmware..."
    arch-chroot "$MNT" sbctl enroll-keys --yes-this-might-brick-my-machine

    log "[*] Custom keys enrolled."
}

# ==============================================================================
# MICROSOFT MODE — SIGN UKI ONLY
# ==============================================================================

sign_microsoft_mode() {
    log "[*] Microsoft mode — building and signing UKI..."
    arch-chroot "$MNT" mkinitcpio -P
    log "[*] UKI built."
    log "[!] NOTE: Firmware must trust the signing key — PK/KEK/DB not modified."
}

# ==============================================================================
# VERIFY SIGNATURES
# ==============================================================================

verify_signatures() {
    log "[*] Verifying signed files..."
    arch-chroot "$MNT" sbctl verify \
        || fatal "Signature verification failed."

    log "[*] Secure Boot status:"
    arch-chroot "$MNT" sbctl status
}

# ==============================================================================
# MAIN
# ==============================================================================

preflight_checks

log "[*] Secure Boot mode: $SB_MODE"

case "$SB_MODE" in
    custom)
        verify_setup_mode
        enroll_custom_keys
        verify_signatures
        verify_secureboot_enabled
        ;;
    microsoft)
        sign_microsoft_mode
        verify_signatures
        ;;
    *)
        fatal "Unknown SB_MODE: $SB_MODE"
        ;;
esac

log "[*] secureboot_enroll.sh complete."