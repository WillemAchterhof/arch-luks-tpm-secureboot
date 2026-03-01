#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — tpm.sh
#  TPM2 enrollment for LUKS auto-unlock (Post-install, run inside system)
# ==============================================================================

log()   { echo -e "[*] $*"; }
fatal() { echo -e "[✖] $*" >&2; exit 1; }

# ==============================================================================
# VERIFY UEFI + SECURE BOOT
# ==============================================================================
j
verify_secureboot_active() {
    log "Verifying UEFI and Secure Boot..."

    [[ -d /sys/firmware/efi ]] \
        || fatal "System not booted in UEFI mode."

    local sb_file value
    sb_file=""

    for f in /sys/firmware/efi/efivars/SecureBoot-*; do
        [[ -e "$f" ]] && sb_file="$f" && break
    done

    [[ -n "$sb_file" ]] \
        || fatal "Cannot read Secure Boot state (EFI vars inaccessible)."

    value=$(tail -c +5 "$sb_file" | hexdump -v -e '1/1 "%d"' | tr -d '\n[:space:]')

    [[ "$value" == "1" ]] \
        || fatal "Secure Boot is NOT enabled. Enable it in firmware and reboot."

    log "Secure Boot is active."
}

# ==============================================================================
# DETECT ROOT LUKS DEVICE
# ==============================================================================

detect_luks_device() {
    log "Detecting root LUKS device..."

    local root_source
    root_source=$(findmnt -no SOURCE /) \
        || fatal "Cannot determine root source."

    [[ "$root_source" == /dev/mapper/* ]] \
        || fatal "Root is not on a mapped LUKS device."

    ROOT_DEV=$(lsblk -no PKNAME "$root_source" | head -n1)
    [[ -n "$ROOT_DEV" ]] \
        || fatal "Failed resolving underlying LUKS device."

    ROOT_DEV="/dev/$ROOT_DEV"

    log "LUKS device detected: $ROOT_DEV"
}

# ==============================================================================
# ENROLL TPM2
# ==============================================================================

enroll_tpm() {
    log "Starting TPM2 enrollment..."
    echo
    echo "================================================="
    echo "              TPM2 ENROLLMENT"
    echo "================================================="
    echo
    echo "Device : $ROOT_DEV"
    echo "PCRs   : 0 + 7 + 11"
    echo "Mode   : TPM2 + PIN"
    echo
    echo "You will be prompted for:"
    echo "  1. Existing LUKS passphrase"
    echo "  2. New TPM PIN (second factor at boot)"
    echo
    read -rp "Press ENTER to continue or Ctrl+C to abort..."

    if cryptsetup luksDump "$ROOT_DEV" | grep -qi "systemd-tpm1"; then
    	log "TPM1 token already present. Skipping enrollment."
    	return
    fi

    systemd-cryptenroll \
        --tpm2-device=auto \
        --tpm2-pcrs=0+7+11 \
        --tpm2-with-pin=yes \
        "$ROOT_DEV"

    log "TPM2 enrollment complete."
}

# ==============================================================================
# VERIFY ENROLLMENT
# ==============================================================================

verify_enrollment() {
    log "Verifying LUKS token..."

    cryptsetup luksDump "$ROOT_DEV" | grep -qi "systemd-tpm2" \
        || fatal "TPM2 token not found in LUKS header."

    log "TPM2 token successfully detected."
}

# ==============================================================================
# MAIN
# ==============================================================================

verify_secureboot_active
detect_luks_device
enroll_tpm
verify_enrollment

log "TPM setup complete."
log "On next reboot, LUKS will unlock via TPM2 + PIN."
log "Your original LUKS passphrase remains valid as fallback."
