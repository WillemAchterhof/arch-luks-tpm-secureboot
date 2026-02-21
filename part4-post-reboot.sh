#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Linux Secure Install - Part 4 (Post-Reboot Phase)
#  Run this AFTER first boot, with Secure Boot ENABLED in firmware
# ==============================================================================

clear
echo "================================================="
echo "   Arch Linux Secure Installation - Part 4"
echo "   Post-Reboot Hardening & TPM2 Enrollment"
echo "================================================="
echo

# ------------------------------------------------------------------------------
# SAFETY CHECKS
# ------------------------------------------------------------------------------

if [[ "$(id -u)" -ne 0 ]]; then
    echo "[!] This script must be run as root."
    echo "    Example: sudo bash $0"
    exit 1
fi

read -rp "Enter your main username (the one you log in with): " USERNAME

if ! id "$USERNAME" &>/dev/null; then
    echo "[!] User '$USERNAME' does not exist."
    exit 1
fi

echo
echo "[*] Make sure:"
echo "    - Secure Boot is ENABLED in firmware"
echo "    - System boots via the signed UKI"
echo
read -rp "Is Secure Boot enabled and the system booted correctly? (y/N): " SB_OK
if [[ "${SB_OK,,}" != "y" ]]; then
    echo "[!] Please enable Secure Boot in firmware and reboot before running this script."
    exit 1
fi

# ------------------------------------------------------------------------------
# TPM2 ENROLLMENT FOR LUKS
# ------------------------------------------------------------------------------

echo
echo "[*] Detecting LUKS root device for TPM2 enrollment..."

ROOT_DEV=$(cryptsetup status cryptroot 2>/dev/null | awk '/device:/ {print $2}')

if [[ -z "${ROOT_DEV:-}" ]]; then
    echo "[!] Could not detect cryptroot device via cryptsetup."
    echo "    Make sure your root LUKS mapping is named 'cryptroot'."
    exit 1
fi

echo "[*] Detected LUKS device: $ROOT_DEV"
echo
echo "    This will enroll a TPM2 key for this LUKS volume."
echo "    You will be asked for your existing LUKS passphrase once,"
echo "    and then for a new TPM PIN (used as an extra factor)."
echo
read -rp "Proceed with systemd-cryptenroll on $ROOT_DEV ? (y/N): " ENROLL_OK
if [[ "${ENROLL_OK,,}" != "y" ]]; then
    echo "[*] Skipping TPM2 enrollment."
else
    systemd-cryptenroll \
        --tpm2-device=auto \
        --tpm2-pcrs=0,7 \
        --tpm2-with-pin=yes \
        "$ROOT_DEV"
    echo "[*] TPM2 enrollment complete."
fi

# ------------------------------------------------------------------------------
# ROOT ACCOUNT HARDENING
# ------------------------------------------------------------------------------

echo
echo "[*] Locking root account (disabling direct root login)..."
passwd -l root
echo "[*] Root account locked."

# ------------------------------------------------------------------------------
# STATUS CHECKS (OPTIONAL BUT NICE)
# ------------------------------------------------------------------------------

echo
echo "[*] Quick status checks (optional):"
echo

if command -v aa-status &>/dev/null; then
    echo "  - AppArmor status:"
    aa-status || true
    echo
else
    echo "  - AppArmor: aa-status not found (package apparmor-utils may be missing)."
    echo
fi

echo "  - nftables ruleset:"
nft list ruleset || true
echo

echo "================================================="
echo "   Part 4 Complete"
echo "================================================="
echo
echo "  Suggested next steps:"
echo "  - Reboot once more to confirm:"
echo "      * TPM2 unlock works (with PIN if configured)"
echo "      * Secure Boot remains enabled"
echo "  - Start using the system normally."
echo
echo "================================================="
