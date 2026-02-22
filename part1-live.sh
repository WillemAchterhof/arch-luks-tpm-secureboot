#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Linux Secure Install - Part 1 (Live ISO Phase)
# ==============================================================================

clear
echo "================================================="
echo "   Arch Linux Secure Installation - Part 1"
echo "================================================="
echo

# ------------------------------------------------------------------------------
# NETWORK SETUP
# ------------------------------------------------------------------------------

echo "[*] Enabling NTP..."
timedatectl set-ntp true

echo "[*] Setting timezone Europe/Amsterdam..."
timedatectl set-timezone Europe/Amsterdam

read -rp "Do you need WiFi? (y/N): " WiFi

if [[ "${WiFi,,}" == "y" ]]; then
    echo "[*] Starting WiFi..."

    ADAPTER=$(iwctl device list | awk '/station/ {print $2; exit}')

    if [[ -z "$ADAPTER" ]]; then
        echo "[!] No WiFi adapter detected."
        exit 1
    fi

    iwctl station "$ADAPTER" scan
    iwctl station "$ADAPTER" get-networks

    read -rp "Enter SSID: " SSID
    read -rsp "Enter WiFi Password: " WiFi_Password && echo
    iwctl --passphrase "$WiFi_Password" station "$ADAPTER" connect "$SSID"
    unset WiFi_Password
fi

echo "[*] Verifying network connectivity..."
ping -c 3 archlinux.org || { echo "[!] Network failed."; exit 1; }
echo "[*] Connection established."

# ------------------------------------------------------------------------------
# PACMAN & MIRRORS
# ------------------------------------------------------------------------------

echo "[*] Configuring pacman..."
sed -i \
  -e 's/^ParallelDownloads =.*/ParallelDownloads = 50/' \
  -e 's/^#Color/Color/' \
  /etc/pacman.conf

echo "[*] Selecting mirrors..."
reflector --country Netherlands,Germany --age 10 --protocol https --sort rate \
  --save /etc/pacman.d/mirrorlist

# ------------------------------------------------------------------------------
# DISK SELECTION
# ------------------------------------------------------------------------------

lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
read -rp "Enter target disk (example: /dev/nvme0n1): " DISK

if [[ ! -b "$DISK" ]]; then
    echo "[!] Invalid disk."
    exit 1
fi

read -rp "THIS WILL WIPE $DISK. Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || exit 1

# ------------------------------------------------------------------------------
# DISK WIPE AND PARTITION
# ------------------------------------------------------------------------------

echo "[*] Wiping disk..."
dd if=/dev/zero of="$DISK" bs=1M count=10 conv=fsync status=progress
wipefs --all --force "$DISK"
sgdisk --zap-all "$DISK"
partprobe "$DISK"

echo "[*] Creating partitions..."
sgdisk --new=1:0:+1024MiB --typecode=1:EF00 --change-name=1:"EFI System Partition" "$DISK"
sgdisk --new=2:0:0        --typecode=2:8300 --change-name=2:"Encrypted Root"        "$DISK"
partprobe "$DISK"

if [[ "$DISK" =~ nvme[0-9]n[0-9]$ || "$DISK" =~ mmcblk[0-9]$ ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

# ------------------------------------------------------------------------------
# LUKS ENCRYPTION
# ------------------------------------------------------------------------------

echo "[*] Generating high-entropy LUKS password..."
LUKS_PASS=$(dd if=/dev/urandom bs=1 count=256 2>/dev/null | tr -dc 'A-Za-z0-9!@#$%^&*()_+=' | head -c 32)

echo "[*] Formatting LUKS2 container..."
echo -n "$LUKS_PASS" | cryptsetup luksFormat "$ROOT_PART" \
  --type luks2 \
  --cipher aes-xts-plain64 \
  --key-size 512 \
  --hash sha512 \
  --pbkdf argon2id \
  --pbkdf-memory 262144 \
  --iter-time 2000 \
  -

echo "[*] Opening encrypted container..."
echo -n "$LUKS_PASS" | cryptsetup open "$ROOT_PART" cryptroot -

# ------------------------------------------------------------------------------
# CLEANUP TRAP
# ------------------------------------------------------------------------------

cleanup() {
    umount -R /mnt 2>/dev/null ||true
    cryptsetup close cryptroot 2>/dev/null || true
}
trap 'cleanup' ERR

# ------------------------------------------------------------------------------
# FILESYSTEMS AND MOUNT
# ------------------------------------------------------------------------------

echo "[*] Creating filesystems..."
mkfs.fat -F32 -n ESP "$EFI_PART"
mkfs.ext4 -L archroot /dev/mapper/cryptroot

echo "[*] Mounting..."
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# ------------------------------------------------------------------------------
# DISPLAY LUKS PASSWORD
# ------------------------------------------------------------------------------

clear
echo "================================================="
echo "   IMPORTANT - SAVE THIS LUKS PASSWORD"
echo "   Store it in your password manager NOW"
echo "================================================="
echo
echo "   $LUKS_PASS"
echo
echo "================================================="
echo
read -rp "Type YES after saving it: " CONFIRM2
[[ "$CONFIRM2" == "YES" ]] || exit 1
unset LUKS_PASS

# ------------------------------------------------------------------------------
# SCRIPT SOURCE DETECTION
# ------------------------------------------------------------------------------

    SCRIPT_BASE = "/run/media/arch/scripts"

# ------------------------------------------------------------------------------
# GET SCRIPTS - /mnt is now mounted, safe to copy
# ------------------------------------------------------------------------------

echo
echo "[*] Fetching install scripts and configs..."
echo

SCRIPT_BASE="/run/media/arch/scripts"

if [[ ! -d "$SCRIPT_BASE" ]]; then
    echo "[!] Trusted script directory not found at $SCRIPT_BASE"
    echo "[!] Ensure your USB is mounted before running this script."
    exit 1
fi

# ------------------------------------------------------------------------------
# CREATE DIRECTORY STRUCTURE
# ------------------------------------------------------------------------------

echo "[*] Creating directory structure..."

mkdir -p /mnt/install/configs/system
mkdir -p /mnt/install/configs/shell
mkdir -p /mnt/install/configs/editor
mkdir -p /mnt/install/configs/themes/waybar
mkdir -p /mnt/install/configs/themes/rofi
mkdir -p /mnt/install/configs/themes/alacritty
mkdir -p /mnt/install/configs/themes/hyprland

# ------------------------------------------------------------------------------
# COPY
# ------------------------------------------------------------------------------

cp -r  "$SCRIPT_BASE"/install/part*.sh              /mnt/install/
cp -r  "$SCRIPT_BASE"/configs/system/.              /mnt/install/configs/system/
cp -r  "$SCRIPT_BASE"/configs/shell/.               /mnt/install/configs/shell/
cp -r  "$SCRIPT_BASE"/configs/editor/.              /mnt/install/configs/editor/
cp -r  "$SCRIPT_BASE"/configs/themes/waybar/.       /mnt/install/configs/themes/waybar/
cp -r  "$SCRIPT_BASE"/configs/themes/rofi/.         /mnt/install/configs/themes/rofi/
cp -r  "$SCRIPT_BASE"/configs/themes/alacritty/.    /mnt/install/configs/themes/alacritty/
cp -r  "$SCRIPT_BASE"/configs/themes/hyprland/.     /mnt/install/configs/themes/hyprland/

# ------------------------------------------------------------------------------
# CPU DETECTION
# ------------------------------------------------------------------------------

CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
    UCODE="intel-ucode"
else
    UCODE="amd-ucode"
fi

echo "[*] Detected CPU: $CPU_VENDOR — installing $UCODE"

# ------------------------------------------------------------------------------
# PACSTRAP
# ------------------------------------------------------------------------------

echo "[*] Installing base system..."

pacstrap -K /mnt \
  base base-devel \
  linux linux-headers linux-firmware \
  "$UCODE" \
  cryptsetup mkinitcpio \
  sbctl sbsigntools efibootmgr \
  tpm2-tools \
  apparmor nftables \
  networkmanager iwd \
  sudo \
  man-db \
  git \
  binutils \
  inotify-tools \
  iproute2 iputils \
  reflector \
  libpwquality \
  polkit \
  usbguard \
  tar gzip unzip p7zip

# ------------------------------------------------------------------------------
# FSTAB
# ------------------------------------------------------------------------------

echo "[*] Generating fstab..."

ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot)
EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")

cat > /mnt/etc/fstab <<EOF
UUID=$ROOT_UUID  /      ext4  rw,noatime  0 1
UUID=$EFI_UUID   /boot  vfat  rw,noatime,fmask=0077,dmask=0077  0 2
EOF

# ------------------------------------------------------------------------------
# CHAIN INTO PART 2
# ------------------------------------------------------------------------------

echo
echo "[*] Part 1 complete. Entering chroot..."
echo

arch-chroot /mnt /install/part2-chroot.sh