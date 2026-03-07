#!/usr/bin/env bas#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — secureboot_enroll.sh
#  Enroll Secure Boot keys (custom mode)
#  or sign UKI only (microsoft mode)
# ==============================================================================

: "${SB_MODE:?SB_MODE not set}"

MNT="/mnt"
UKI_PATH="/boot/EFI/Linux/arch-linux.efi"

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================

preflight_checks() {
    log "[*] Running Secure Boot pre-flight checks..."

    [[ -d /sys/firmware/efi ]] \
        || fatal "System not booted in UEFI mode."

    mountpoint -q "$MNT" \
        || fatal "$MNT is not mounted."

    [[ -x "$MNT/usr/bin/sbctl" ]] \
        || fatal "sbctl not installed in target system."

    [[ -x "$MNT/usr/bin/mkinitcpio" ]] \
        || fatal "mkinitcpio not installed in target system."

    [[ -d "$MNT/boot/EFI/Linux" ]] \
        || fatal "UKI directory missing: $MNT/boot/EFI/Linux — run bootloader.sh first."

    [[ -f "$MNT$UKI_PATH" ]] \
        || fatal "UKI not found: $MNT$UKI_PATH — run bootloader.sh first."

    log "[*] Pre-flight checks OK."
}

# ==============================================================================
# EFIVARFS — MOUNT/UNMOUNT INSIDE CHROOT
# ==============================================================================

# sbctl needs access to EFI variables to create keys and enroll them.
# efivarfs is not automatically mounted inside arch-chroot.

mount_efivarfs() {
    if ! mountpoint -q "$MNT/sys/firmware/efi/efivars"; then
        log "[*] Mounting efivarfs inside chroot..."

        # Create mountpoint if it doesn't exist — arch-chroot does not create it
        mkdir -p "$MNT/sys/firmware/efi/efivars" \
            || fatal "Failed to create efivarfs mountpoint."

        mount --bind /sys/firmware/efi/efivars \
            "$MNT/sys/firmware/efi/efivars" \
            || fatal "Failed to mount efivarfs inside chroot."
    fi
}

umount_efivarfs() {
    if mountpoint -q "$MNT/sys/firmware/efi/efivars"; then
        log "[*] Unmounting efivarfs from chroot..."
        umount "$MNT/sys/firmware/efi/efivars" || true
    fi
}

trap umount_efivarfs EXIT

# ==============================================================================
# VERIFY SETUP MODE
# ==============================================================================

verify_setup_mode() {
    log "[*] Checking firmware Setup Mode..."

    local setup_mode_var
    setup_mode_var="/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"

    [[ -f "$setup_mode_var" ]] \
        || fatal "Cannot read Setup Mode EFI variable."

    # EFI variables have a 4-byte attribute header — skip it with +5
    local val
    val=$(tail -c +5 "$setup_mode_var" \
        | hexdump -v -e '1/1 "%d"' | tr -d '\n[:space:]')

    [[ "$val" == "1" ]] \
        || fatal "Firmware is NOT in Setup Mode.
Enter UEFI firmware, clear Secure Boot keys, and rerun."

    log "[*] Setup Mode confirmed."
}

# ==============================================================================
# CUSTOM KEYS — CREATE, SIGN, ENROLL
# ==============================================================================

enroll_custom_keys() {
    mount_efivarfs

    log "[*] Creating Secure Boot keys..."
    arch-chroot "$MNT" /usr/bin/sbctl create-keys \
        || fatal "sbctl create-keys failed."

    log "[*] Signing UKI..."
    arch-chroot "$MNT" /usr/bin/sbctl sign "$UKI_PATH" \
        || fatal "sbctl sign failed."

    log "[*] Enrolling keys into firmware..."
    arch-chroot "$MNT" /usr/bin/sbctl enroll-keys --yes-this-might-brick-my-machine \
        || fatal "sbctl enroll-keys failed."

    log "[*] Custom keys enrolled."
}

# ==============================================================================
# MICROSOFT MODE — SIGN UKI ONLY
# ==============================================================================

sign_microsoft_mode() {
    mount_efivarfs

    log "[*] Microsoft mode — signing UKI with sbctl..."

    # Keys are created but NOT enrolled — firmware retains its Microsoft keys.
    # The UKI is signed so it can be verified by the existing firmware trust chain.
    arch-chroot "$MNT" /usr/bin/sbctl create-keys \
        || fatal "sbctl create-keys failed."

    arch-chroot "$MNT" /usr/bin/sbctl sign "$UKI_PATH" \
        || fatal "sbctl sign failed."

    log "[*] UKI signed."
    log "[!] NOTE: Firmware Microsoft keys retained — PK/KEK/DB not modified."
}

# ==============================================================================
# VERIFY SIGNATURES
# ==============================================================================

verify_signatures() {
    log "[*] Verifying signed files..."
    arch-chroot "$MNT" /usr/bin/sbctl verify \
        || fatal "Signature verification failed."

    log "[*] Secure Boot status:"
    arch-chroot "$MNT" /usr/bin/sbctl status
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
        ;;
    microsoft)
        sign_microsoft_mode
        # sbctl verify checks against enrolled sbctl keys only —
        # not meaningful in microsoft mode where firmware keys are retained.
        log "[*] Skipping sbctl verify — not applicable in microsoft mode."
        ;;
    *)
        fatal "Unknown SB_MODE: $SB_MODE"
        ;;
esac

log "[*] secureboot_enroll.sh complete."
