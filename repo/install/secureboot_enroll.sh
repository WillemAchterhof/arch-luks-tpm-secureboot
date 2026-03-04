#!/usr/bin/env bash
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

    # Verify UKI directory exists
    [[ -d "$MNT/boot/EFI/Linux" ]] \
        || fatal "UKI directory missing: $MNT/boot/EFI/Linux — run bootloader.sh first."

    log "[*] Pre-flight checks OK."
}

# ==============================================================================
# VERIFY SETUP MODE
# ==============================================================================

verify_setup_mode() {
    log "[*] Checking firmware Setup Mode..."

    local setup_mode_var="/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"

    [[ -f "$setup_mode_var" ]] \
        || fatal "Cannot read Setup Mode EFI variable — is system booted in UEFI mode?"

    local val
    val=$(od -An -t u1 "$setup_mode_var" | awk '{print $NF}')

    if [[ "$val" != "1" ]]; then
        fatal "Firmware is NOT in Setup Mode.
Enter UEFI firmware, clear Secure Boot keys, and rerun."
    fi

    log "[*] Setup Mode confirmed."
}

# ==============================================================================
# REGISTER UKI WITH SBCTL
# ==============================================================================

register_uki() {
    log "[*] Registering UKI with sbctl..."

    # Register the UKI path so sbctl sign-all knows what to sign
    arch-chroot "$MNT" /usr/bin/sbctl add-file "$UKI_PATH" \
        || fatal "Failed to register UKI with sbctl."

    log "[*] UKI registered: $UKI_PATH"
}

# ==============================================================================
# BUILD AND SIGN UKI
# ==============================================================================

build_and_sign_uki() {
    log "[*] Building UKI with mkinitcpio..."
    arch-chroot "$MNT" mkinitcpio -P \
        || fatal "mkinitcpio failed."

    # Verify UKI was actually created
    [[ -f "$MNT$UKI_PATH" ]] \
        || fatal "UKI not found after mkinitcpio: $MNT$UKI_PATH"

    log "[*] Signing UKI with sbctl..."
    arch-chroot "$MNT" /usr/bin/sbctl sign-all \
        || fatal "sbctl sign-all failed."

    log "[*] UKI built and signed."
}

# ==============================================================================
# CUSTOM KEYS — CREATE AND ENROLL
# ==============================================================================

enroll_custom_keys() {
    log "[*] Creating Secure Boot keys..."
    arch-chroot "$MNT" /usr/bin/sbctl create-keys \
        || fatal "sbctl create-keys failed."

    register_uki

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
    echo "  Type Q to abort:"
    echo

    local confirm
    read -rp "> " confirm
    [[ "$confirm" == "Q" || "$confirm" == "q" ]] \
        && fatal "Secure Boot enrollment aborted by user."
    [[ "$confirm" == "ENROLL" ]] \
        || fatal "Secure Boot enrollment aborted."

    log "[*] Enrolling keys into firmware..."
    arch-chroot "$MNT" /usr/bin/sbctl enroll-keys --yes-this-might-brick-my-machine \
        || fatal "sbctl enroll-keys failed."

    log "[*] Custom keys enrolled."

    build_and_sign_uki
}

# ==============================================================================
# MICROSOFT MODE — REGISTER AND SIGN UKI ONLY
# ==============================================================================

sign_microsoft_mode() {
    log "[*] Microsoft mode — registering and signing UKI..."
    register_uki
    build_and_sign_uki
    log "[!] NOTE: Firmware must trust the signing key — PK/KEK/DB not modified."
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
        verify_signatures
        ;;
    *)
        fatal "Unknown SB_MODE: $SB_MODE"
        ;;
esac

log "[*] secureboot_enroll.sh complete."
