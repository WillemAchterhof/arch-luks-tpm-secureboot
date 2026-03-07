#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — tpm.sh
#  TPM2 enrollment for LUKS auto-unlock (Post-install, run inside system)
# ==============================================================================

LUKS_PART=""

# ==============================================================================
# VERIFY UEFI + SECURE BOOT
# ==============================================================================

verify_secureboot_active() {
    log "[*] Verifying UEFI and Secure Boot..."

    [[ -d /sys/firmware/efi ]] \
        || fatal "System not booted in UEFI mode."

    local sb_file value
    sb_file=""

    for f in /sys/firmware/efi/efivars/SecureBoot-*; do
        [[ -e "$f" ]] && sb_file="$f" && break
    done

    [[ -n "$sb_file" ]] \
        || fatal "Cannot read Secure Boot state (EFI vars inaccessible)."

    # EFI variables have a 4-byte attribute header — skip it with +5
    value=$(tail -c +5 "$sb_file" \
        | hexdump -v -e '1/1 "%d"' | tr -d '\n[:space:]')

    [[ "$value" == "1" ]] \
        || fatal "Secure Boot is NOT enabled. Enable it in firmware and reboot."

    log "[*] Secure Boot is active."
}

# ==============================================================================
# DETECT ROOT LUKS PARTITION
# ==============================================================================

detect_luks_device() {
    log "[*] Detecting root LUKS partition..."

    local root_source
    root_source=$(findmnt -no SOURCE /) \
        || fatal "Cannot determine root source."

    [[ "$root_source" == /dev/mapper/* ]] \
        || fatal "Root is not on a mapped LUKS device."

    # PKNAME gives the parent partition (e.g. sda2, nvme0n1p2) —
    # systemd-cryptenroll needs the LUKS partition, not the whole disk.
    LUKS_PART=$(lsblk -no PKNAME "$root_source" | head -n1)

    [[ -n "$LUKS_PART" ]] \
        || fatal "Failed resolving underlying LUKS partition."

    LUKS_PART="/dev/$LUKS_PART"

    [[ -b "$LUKS_PART" ]] \
        || fatal "Resolved LUKS partition is not a block device: $LUKS_PART"

    log "[*] LUKS partition detected: $LUKS_PART"
}

# ==============================================================================
# ENROLL TPM2
# ==============================================================================

enroll_tpm() {
    log "[*] Starting TPM2 enrollment..."

    echo
    echo "================================================="
    echo "              TPM2 ENROLLMENT"
    echo "================================================="
    echo
    echo "  Device : $LUKS_PART"
    echo "  PCRs   : 0 + 7 + 11"
    echo "  Mode   : TPM2 + PIN"
    echo
    echo "  You will be prompted for:"
    echo "    1. Existing LUKS passphrase"
    echo "    2. New TPM PIN (second factor at boot)"
    echo
    read -rp "  Press ENTER to continue or Ctrl+C to abort..."

    # Check for existing TPM2 token — skip if already enrolled
    if cryptsetup luksDump "$LUKS_PART" | grep -qi "systemd-tpm2"; then
        log "[*] TPM2 token already present — skipping enrollment."
        return
    fi

    systemd-cryptenroll \
        --tpm2-device=auto \
        --tpm2-pcrs=0+7+11 \
        --tpm2-with-pin=yes \
        "$LUKS_PART"

    log "[*] TPM2 enrollment complete."
}

# ==============================================================================
# VERIFY ENROLLMENT
# ==============================================================================

verify_enrollment() {
    log "[*] Verifying LUKS token..."

    cryptsetup luksDump "$LUKS_PART" | grep -qi "systemd-tpm2" \
        || fatal "TPM2 token not found in LUKS header."

    log "[*] TPM2 token successfully detected."
}

# ==============================================================================
# MAIN
# ==============================================================================

verify_secureboot_active
detect_luks_device
enroll_tpm
verify_enrollment

log "[*] TPM setup complete."
log "[*] On next reboot, LUKS will unlock via TPM2 + PIN."
log "[*] Your original LUKS passphrase remains valid as fallback."
