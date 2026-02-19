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
# PREPARATION
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
        echo "No WiFi adapter detected."
        exit 1
    fi

    iwctl station "$ADAPTER" scan
    iwctl station "$ADAPTER" get-networks

    read -rp "Enter SSID: "  SSID
    read -rsp "Enter WiFi Password: " WiFi_Password && echo
    iwctl --passphrase "$WiFi_Password" station "$ADAPTER" connect "$SSID"
fi

ping -c 3 archlinux.org || { echo "Network failed."; exit 1; }
echo "Connection established"

# ------------------------------------------------------------------------------
# DISK SELECTION
# ------------------------------------------------------------------------------

lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
read -rp "Enter target disk (example: /dev/nvme0n1): " DISK

if [[ ! -b "$DISK" ]]; then
    echo "Invalid disk."
    exit 1
fi

read -rp "THIS WILL WIPE $DISK. Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || exit 1

# ------------------------------------------------------------------------------
# DISK PREPARATION
# ------------------------------------------------------------------------------

echo "[*] Wiping disk..."
wipefs --all --force "$DISK"
sgdisk --zap-all "$DISK"
partprobe "$DISK"

echo "[*] Creating partitions..."
sgdisk --new=1:0:+1024MiB --typecode=1:EF00 --change-name=1:"EFI System Partition" "$DISK"
sgdisk --new=2:0:0       --typecode=2:8300 --change-name=2:"Encrypted Root"       "$DISK"
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
# FILESYSTEMS
# ------------------------------------------------------------------------------

echo "[*] Creating filesystems..."
mkfs.fat -F32 -n ESP "$EFI_PART"
mkfs.ext4 -L archroot /dev/mapper/cryptroot

echo "[*] Mounting..."
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# ------------------------------------------------------------------------------
# PACMAN CONFIG
# ------------------------------------------------------------------------------

echo "[*] Configuring pacman..."
sed -i 's/^ParallelDownloads =.*/ParallelDownloads = 50/' /etc/pacman.conf

echo "[*] Selecting mirrors..."
reflector --country Netherlands,Germany --age 10 --protocol https --sort rate \
  --save /etc/pacman.d/mirrorlist


# ------------------------------------------------------------------------------
# Retrieve Chipset
# ------------------------------------------------------------------------------

CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
    UCODE="intel-ucode"
else
    UCODE="amd-ucode"
fi


# ------------------------------------------------------------------------------
# PACSTRAP
# ------------------------------------------------------------------------------

echo "[*] Installing base system..."

pacstrap -K /mnt \
  base base-devel \
  linux linux-headers linux-firmware \
  $UCODE \
  cryptsetup mkinitcpio \
  sbctl sbsigntools efibootmgr \
  tpm2-tools \
  apparmor nftables \
  networkmanager iwd \
  sudo \
  zsh zsh-completions \
  man-db \
  git \
  neovim \
  iproute2 iputils \
  reflector \
  libpwquality \
  polkit \
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
# STORE LUKS PASSWORD TEMPORARILY
# ------------------------------------------------------------------------------

echo "$LUKS_PASS" > /mnt/root/luks-pass.tmp
chmod 600 /mnt/root/luks-pass.tmp

clear
echo "================================================="
echo "   IMPORTANT - SAVE THIS LUKS PASSWORD"
echo "================================================="
echo
echo "You need this for first boot: $LUKS_PASS" 
echo
echo "================================================="
echo
read -rp "Type YES after saving it: " CONFIRM2
[[ "$CONFIRM2" == "YES" ]] || exit 1

# Clear variable from memory
unset LUKS_PASS

echo
echo "[*] Part 1 complete."
echo "[*] Entering chroot..."
echo

echo "[*] Fetching install scripts..."
curl -fsSL "https://raw.githubusercontent.com/WillemAchterhof/arch-luks-tpm-secureboot/main/part2-chroot.sh" \
  -o /mnt/root/part2-chroot.sh
chmod +x /mnt/root/part2-chroot.sh

arch-chroot /mnt /root/part2-chroot.sh

