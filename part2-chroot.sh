#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Linux Secure Install - Part 2 (Chroot Phase)
# ==============================================================================

clear
echo "================================================="
echo "   Arch Linux Secure Installation - Part 2"
echo "================================================="
echo

# ------------------------------------------------------------------------------
# COLLECT USER INFO
# ------------------------------------------------------------------------------

read -rp "Enter user name: " USERNAME
read -rp "Enter computer name: " HOSTNAME
read -rp "Enter counteries for geograpical location of downlaod mirrors: " COUNTRIES

# ------------------------------------------------------------------------------
# SYSTEM CONFIGURATION
# ------------------------------------------------------------------------------

echo "[*] Setting timezone..."
ln -sf /usr/share/zoneinfo/Europe/Amsterdam /etc/localtime
hwclock --systohc

echo "[*] Generating locale..."
sed -i '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

echo "[*] Setting hostname..."
echo "$HOSTNAME" > /etc/hostname

cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

echo "[*] Setting environment variables..."
cat <<EOF > /etc/environment
#TERMINAL=alacritty
EDITOR=nvim
VISUAL=nvim
#MOZ_ENABLE_WAYLAND=1
#QT_QPA_PLATFORM=wayland
#SDL_VIDEODRIVER=wayland
EOF

# ------------------------------------------------------------------------------
# PACMAN SETUP
# ------------------------------------------------------------------------------

echo "[*] Configuring pacman..."
sed -i \
  -e 's/^ParallelDownloads =.*/ParallelDownloads = 20/' \
  -e 's/^#Color/Color/' \
  -e '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' \
  /etc/pacman.conf

echo "[*] Selecting mirrors..."
reflector --country "$COUNTRIES" --age 10 --protocol https --sort rate \
  --save /etc/pacman.d/mirrorlist

echo "[*] Updating system..."
pacman -Syu --noconfirm

# ------------------------------------------------------------------------------
# USER AND ROOT SETUP
# ------------------------------------------------------------------------------

echo "[*] Setting root password..."
passwd

echo "[*] Configuring sudoers..."
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

cat <<'EOF' > /etc/sudoers.d/hardening
Defaults use_pty
EOF
chmod 440 /etc/sudoers.d/hardening

echo "[*] Creating user $USERNAME ..."
useradd -m -G wheel -s /usr/bin/zsh "$USERNAME"
passwd "$USERNAME"

# ------------------------------------------------------------------------------
# MKINITCPIO
# ------------------------------------------------------------------------------

GPU_VENDOR=$(lspci | grep -i 'vga\|3d\|display' | head -1)

if echo "$GPU_VENDOR" | grep -qi "amd"; then
    GPU_MODULE="amdgpu"
elif echo "$GPU_VENDOR" | grep -qi "nvidia"; then
    GPU_MODULE="nvidia"
else
    GPU_MODULE=""
fi

echo "[*] Configuring mkinitcpio..."
sed -i "s/^MODULES=.*/MODULES=($GPU_MODULE)/"                                                                                                         /etc/mkinitcpio.conf
sed -i 's/^BINARIES=.*/BINARIES=()/'                                                                                                                  /etc/mkinitcpio.conf
sed -i 's|^HOOKS=.*|HOOKS=(base systemd keyboard autodetect modconf kms microcode block sd-encrypt filesystems fsck)|'                                /etc/mkinitcpio.conf
sed -i 's|^#*COMPRESSION=.*|COMPRESSION="zstd"|'                                                                                                      /etc/mkinitcpio.conf
sed -i 's|^#*COMPRESSION_OPTIONS=.*|COMPRESSION_OPTIONS="-3"|'                                                                                        /etc/mkinitcpio.conf

echo "[*] Building kernel command line..."
# Detect root partition fresh
ROOT_PART=$(blkid -L archroot 2>/dev/null || lsblk -rno NAME,LABEL | awk '/archroot/ {print "/dev/"$1}')
LUKS_UUID=$(blkid -s UUID -o value "$(cryptsetup status cryptroot | awk '/device:/ {print $2}')")

mkdir -p /etc/kernel
cat <<EOF > /etc/kernel/cmdline
rd.luks.name=$LUKS_UUID=cryptroot rd.luks.options=tpm2-device=auto,tpm2-pcrs=0,7 root=/dev/mapper/cryptroot rootfstype=ext4 lsm=lockdown,yama,apparmor,bpf apparmor=1 lockdown=confidentiality
EOF

echo "[*] Creating UKI preset..."
mkdir -p /boot/EFI/Linux

cat <<'EOF' > /etc/mkinitcpio.d/linux.preset
PRESETS=('default')
ALL_kver="/boot/vmlinuz-linux"
default_uki="/boot/EFI/Linux/arch-linux.efi"
EOF

# ------------------------------------------------------------------------------
# AUTOSIGNING HOOK
# ------------------------------------------------------------------------------

echo "[*] Installing pacman signing hook..."
mkdir -p /etc/pacman.d/hooks
cp /install/configs/zz-sbctl-uki.hook    /etc/pacman.d/hooks/zz-sbctl-uki.hook

# ------------------------------------------------------------------------------
# SERVICES
# ------------------------------------------------------------------------------

echo "[*] Enabling services..."
systemctl enable apparmor
systemctl enable NetworkManager
systemctl enable nftables
systemctl enable fstrim.timer
systemctl enable reflector.timer
systemctl enable systemd-resolved
systemctl enable systemd-timesyncd

ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

echo "[*] Configuring NetworkManager..."
cp /install/configs/NetworkManager.conf  /etc/NetworkManager/NetworkManager.conf

mkdir -p /etc/NetworkManager/conf.d/
cat <<'EOF' > /etc/NetworkManager/conf.d/20-mac-randomize.conf
[connection]
wifi.cloned-mac-address=random
ethernet.cloned-mac-address=random
EOF

echo "[*] Masking unused network services..."
systemctl mask systemd-networkd
systemctl mask wpa_supplicant

echo "[*] Disabling unnecessary services..."
systemctl disable \
  machines.target \
  NetworkManager-dispatcher.service \
  NetworkManager-wait-online.service \
  remote-integritysetup.target \
  remote-veritysetup.target \
  systemd-mountfsd.socket \
  systemd-network-generator.service \
  systemd-networkd-wait-online.service \
  systemd-nsresourced.socket \
  systemd-pstore.service

# ------------------------------------------------------------------------------
# HARDENING
# ------------------------------------------------------------------------------

echo "[*] Writing firewall rules..."
/install/configs/nftables.conf           /etc/nftables.conf

echo "[*] Writing sysctl hardening..."
cp /install/configs/99-hardening.conf    /etc/sysctl.d/99-hardening.conf

echo "[*] Writing kernel module blacklist..."
cp /install/configs/blacklist.conf       /etc/modprobe.d/blacklist.conf

echo "[*] Building UKI..."
mkinitcpio -P

# ------------------------------------------------------------------------------
# FETCH AND CHAIN INTO PART 3
# ------------------------------------------------------------------------------

echo
echo "[*] Part 2 complete. Launching Part 3 (Secure Boot)..."
echo

bash /install/part3-secureboot.sh
