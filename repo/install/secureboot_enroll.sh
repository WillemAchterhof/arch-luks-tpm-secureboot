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
 ="/boot/EFI/Linux/arch-linux.efi"

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================

preflight_checks() {
    log "[*] Running Secure Boot pre-flight checks..."

    [[ -d /sys/firmware/efi ]] || fatal "System not booted in UEFI mode."

    mountpoint -q "$MNT" || fatal "$MNT is not mounted."

    [[ -x "$MNT/usr/bin/sbctl" ]] || fatal "sbctl not installed in target system."

    [[ -x "$MNT/usr/bin/mkinitcpio" ]] || fatal "mkinitcpio not installed in target system."

    [[ -d "$MNT/boot/EFI/Linux" ]] || fatal "UKI directory missing: $MNT/boot/EFI/Linux — run bootloader.sh first."

    log "[*] Pre-flight checks OK."
}

# ==============================================================================
# VERIFY SETUP MODE
# ==============================================================================

verify_setup_mode() {
    log "[*] Checking firmware Setup Mode..."

    local setup_mode_var="/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"

    [[ -f "$setup_mode_var" ]] \
        || fatal "Cannot read Setup Mode EFI variable."

    local val
    val=$(od -An -t u1 "$setup_mode_var" | awk '{print $NF}')

    if [[ "$val" != "1" ]]; then
        fatal "Firmware is NOT in Setup Mode.
Enter UEFI firmware, clear Secure Boot keys, and rerun."
    fi

    log "[*] Setup Mode confirmed."
}

# ==============================================================================
# CUSTOM KEYS — CREATE, BUILD, ENROLL
# ==============================================================================

enroll_custom_keys() {
    log "[*] Creating Secure Boot keys..."
    arch-chroot /mnt sbctl create-keys || fatal "sbctl create-keys failed."

    log "[*] Building and signing UKI..."
    arch-chroot "$MNT" mkinitcpio -P || fatal "mkinitcpio failed."

    [[ -f "$MNT$UKI_PATH" ]] || fatal "UKI not found after mkinitcpio: $MNT$UKI_PATH"

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
    arch-chroot "$MNT" sbctl enroll-keys --yes-this-might-brick-my-machine \
        || fatal "sbctl enroll-keys failed."

    log "[*] Custom keys enrolled."
}

# ==============================================================================
# MICROSOFT MODE — BUILD AND SIGN UKI ONLY
# ==============================================================================

sign_microsoft_mode() {
    log "[*] Microsoft mode — building and signing UKI..."

    arch-chroot "$MNT" mkinitcpio -P || fatal "mkinitcpio failed."

    [[ -f "$MNT$UKI_PATH" ]] || fatal "UKI not found after mkinitcpio: $MNT$UKI_PATH"

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