#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Linux Secure Install - Part 3 (Secure Boot)
# ==============================================================================

clear
echo "================================================="
echo "   Arch Linux Secure Installation - Part 3"
echo "   Secure Boot Setup"
echo "================================================="
echo

# ------------------------------------------------------------------------------
# DETECT DISK
# ------------------------------------------------------------------------------

EFI_DISK=$(blkid -s UUID -o device /dev/disk/by-label/ESP 2>/dev/null || \
           lsblk -rno NAME,PARTLABEL | awk '/EFI/ {print "/dev/"$1}' | head -1)

DISK=$(lsblk -no PKNAME "$EFI_DISK" | head -1)
DISK="/dev/$DISK"

echo "[*] Detected disk: $DISK"
echo "[*] Detected EFI partition: $EFI_DISK"

# ------------------------------------------------------------------------------
# SBCTL STATUS
# ------------------------------------------------------------------------------

echo "[*] Checking Secure Boot status..."
sbctl status

echo
read -rp "Is Secure Boot in Setup Mode? (y/N): " SB_READY
if [[ "${SB_READY,,}" != "y" ]]; then
    echo "[!] Please enter UEFI firmware and enable Setup Mode, then re-run this script."
    exit 1
fi

# ------------------------------------------------------------------------------
# CREATE KEYS
# ------------------------------------------------------------------------------

echo "[*] Creating Secure Boot keys..."
sbctl create-keys

# ------------------------------------------------------------------------------
# BUILD UKI
# ------------------------------------------------------------------------------

echo "[*] Building Unified Kernel Image..."
mkinitcpio -P

# ------------------------------------------------------------------------------
# CLEAR BOOT ENTRIES
# ------------------------------------------------------------------------------

echo "[*] Clearing existing boot entries..."
efibootmgr | awk '/Boot[0-9A-F]{4}\*?/ {print $1}' | \
    grep -oP '[0-9A-F]{4}' | \
    while read -r entry; do
        echo "    Removing boot entry: $entry"
        efibootmgr -b "$entry" -B
    done

# ------------------------------------------------------------------------------
# CREATE BOOT ENTRY
# ------------------------------------------------------------------------------

echo "[*] Creating Arch Linux boot entry..."
efibootmgr --create \
  --disk "$DISK" \
  --part 1 \
  --label "Arch Linux" \
  --loader '\EFI\Linux\arch-linux.efi' \
  --unicode

echo "[*] Current boot entries:"
efibootmgr

# Set first entry as boot order (will be 0000 after clearing all previous)
NEW_ENTRY=$(efibootmgr | awk '/Arch Linux/ {print $1}' | grep -oP '[0-9A-F]{4}' | head -1)
echo "[*] Setting boot order to: $NEW_ENTRY"
efibootmgr -o "$NEW_ENTRY"

# ------------------------------------------------------------------------------
# ENROLL KEYS
# ------------------------------------------------------------------------------

clear
echo "================================================="
echo "   WARNING - SECURE BOOT KEY ENROLLMENT"
echo "================================================="
echo
echo "  This will enroll custom Secure Boot keys."
echo "  If your firmware does not support custom keys"
echo "  or has restrictions, this may prevent booting."
echo
echo "  Prerequisites:"
echo "  - Secure Boot must be in Setup Mode"
echo "  - You must have access to UEFI firmware to recover"
echo
echo "================================================="
echo
read -rp "Type YES to enroll keys: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }

echo "[*] Enrolling Secure Boot keys..."
sbctl enroll-keys --yes-this-might-brick-my-machine

# ------------------------------------------------------------------------------
# Signing UKI
# ------------------------------------------------------------------------------

echo
echo "[*] Encrypting Boot Files..."
mkinitcpio -P

# ------------------------------------------------------------------------------
# VERIFY SIGNATURES
# ------------------------------------------------------------------------------

echo "[*] Verifying signed files..."
sbctl verify

echo
echo "[*] Verifying final state..."
sbctl status

# ------------------------------------------------------------------------------
# COMPLETE
# ------------------------------------------------------------------------------

echo
echo "================================================="
echo "   Part 3 Complete"
echo "================================================="
echo
echo "  Next steps:"
echo "  1. Exit chroot: exit"
echo "  2. Unmount: umount -R /mnt"
echo "  3. Remove USB and reboot"
echo "  4. Enter your firmware and enable Secure Boot."
echo "  5. Enter LUKS password at boot (This was displayed, at the Disk Management Phase!!!!)"
echo "  6. After first boot run: bash /install/part4-post-reboot.sh"
echo
echo "================================================="
echo
