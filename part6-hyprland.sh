#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Linux Secure Install - Part 5 (Hyprland Desktop Setup)
#  Run this AFTER Part 4, inside your fully booted system
# ==============================================================================

clear
echo "================================================="
echo "   Arch Linux Secure Installation - Part 5"
echo "   Hyprland Desktop Environment Setup"
echo "================================================="
echo

# ------------------------------------------------------------------------------
# BASIC CHECKS
# ------------------------------------------------------------------------------

if [[ "$(id -u)" -ne 0 ]]; then
    echo "[!] Run this script as root (sudo)."
    exit 1
fi

read -rp "Enter your username: " USERNAME

if ! id "$USERNAME" &>/dev/null; then
    echo "[!] User '$USERNAME' does not exist."
    exit 1
fi

# ------------------------------------------------------------------------------
# UPDATE
# ------------------------------------------------------------------------------

echo "[*] Updating system..."
pacman -Syu --noconfirm

# ------------------------------------------------------------------------------
# INSTALL YAY (AUR HELPER)
# ------------------------------------------------------------------------------

echo "[*] Installing yay (AUR helper)..."

pacman -S --needed --noconfirm base-devel git

sudo -u "$USERNAME" bash -c '
    if [[ ! -d "$HOME/yay" ]]; then
        git clone https://aur.archlinux.org/yay.git "$HOME/yay"
    fi
    cd "$HOME/yay"
    makepkg -si --noconfirm
'

# ------------------------------------------------------------------------------
# HYPRLAND CORE
# ------------------------------------------------------------------------------

echo "[*] Installing Hyprland core packages..."

pacman -S --noconfirm \
    hyprland hyprpaper hypridle hyprlock \
    waybar mako cliphist \
    grim slurp swappy \
    thunar thunar-archive-plugin \
    polkit-kde-agent \
    xdg-desktop-portal xdg-desktop-portal-hyprland \
    wofi \
    ttf-font-awesome papirus-icon-theme

sudo -u "$USERNAME" yay -S --noconfirm rofi-wayland

# ------------------------------------------------------------------------------
# AUDIO & BLUETOOTH
# ------------------------------------------------------------------------------

echo "[*] Installing audio + bluetooth..."

pacman -S --noconfirm \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
    bluez bluez-utils

systemctl enable --now bluetooth

# ------------------------------------------------------------------------------
# GPU / VIDEO STACK
# ------------------------------------------------------------------------------

echo "[*] Detecting and installing GPU drivers..."

GPU_VENDOR=$(lspci | grep -i 'vga\|3d\|display' | head -1)

if echo "$GPU_VENDOR" | grep -qi "amd"; then
    pacman -S --noconfirm \
        mesa vulkan-radeon libva-mesa-driver \
        lib32-mesa lib32-vulkan-radeon lib32-libva-mesa-driver

elif echo "$GPU_VENDOR" | grep -qi "nvidia"; then
    pacman -S --noconfirm \
        nvidia-dkms nvidia-utils lib32-nvidia-utils \
        nvidia-settings
    echo
    echo "  [!] NVIDIA detected - add nvidia-drm.modeset=1 to your kernel cmdline!"
    echo "      Edit /etc/kernel/cmdline and rebuild the UKI with: mkinitcpio -P"
    echo
    read -rp "Press ENTER to continue..." _

elif echo "$GPU_VENDOR" | grep -qi "intel"; then
    pacman -S --noconfirm \
        mesa vulkan-intel libva-intel-driver \
        lib32-mesa lib32-vulkan-intel
else
    echo "[!] GPU vendor not detected, skipping GPU drivers."
fi

# ------------------------------------------------------------------------------
# FONTS
# ------------------------------------------------------------------------------

echo "[*] Installing fonts..."

pacman -S --noconfirm \
    ttf-dejavu ttf-liberation \
    noto-fonts noto-fonts-cjk noto-fonts-emoji \
    ttf-nerd-fonts-symbols

# ------------------------------------------------------------------------------
# GAMING STACK
# ------------------------------------------------------------------------------

echo "[*] Installing gaming tools..."

pacman -S --noconfirm steam gamemode mangohud

sudo -u "$USERNAME" yay -S --noconfirm protonup-qt

# ------------------------------------------------------------------------------
# PROGRAMMING STACK
# ------------------------------------------------------------------------------

echo "[*] Installing programming tools..."

pacman -S --noconfirm dotnet-sdk

sudo -u "$USERNAME" yay -S --noconfirm powershell-bin visual-studio-code-bin

# ------------------------------------------------------------------------------
# MEDIA TOOLS
# ------------------------------------------------------------------------------

echo "[*] Installing media tools..."

pacman -S --noconfirm mpv yt-dlp

# ------------------------------------------------------------------------------
# VIRTUALIZATION
# ------------------------------------------------------------------------------

echo "[*] Installing virtualization tools..."

pacman -S --noconfirm qemu-full libvirt virt-manager

systemctl enable --now libvirtd

usermod -aG libvirt "$USERNAME"

# ------------------------------------------------------------------------------
# UTILITIES
# ------------------------------------------------------------------------------

echo "[*] Installing utilities..."

pacman -S --noconfirm \
    alacritty btop fastfetch keepassxc \
    xdg-user-dirs xdg-utils

sudo -u "$USERNAME" xdg-user-dirs-update || true

# ------------------------------------------------------------------------------
# UNCOMMENT WAYLAND ENVIRONMENT VARIABLES
# ------------------------------------------------------------------------------

echo "[*] Enabling Wayland environment variables..."

sed -i 's/^#TERMINAL=alacritty/TERMINAL=alacritty/' /etc/environment
sed -i 's/^#MOZ_ENABLE_WAYLAND=1/MOZ_ENABLE_WAYLAND=1/' /etc/environment
sed -i 's/^#QT_QPA_PLATFORM=wayland/QT_QPA_PLATFORM=wayland/' /etc/environment
sed -i 's/^#SDL_VIDEODRIVER=wayland/SDL_VIDEODRIVER=wayland/' /etc/environment

# ------------------------------------------------------------------------------
# COPY USER CONFIGS (Hyprland)
# ------------------------------------------------------------------------------

echo "[*] Copying Hyprland config..."

sudo -u "$USERNAME" mkdir -p "/home/$USERNAME/.config/hypr"
sudo -u "$USERNAME" cp /install/configs/hyprland.conf "/home/$USERNAME/.config/hypr/hyprland.conf"

# ------------------------------------------------------------------------------
# DONE
# ------------------------------------------------------------------------------

echo
echo "================================================="
echo "   Part 5 Complete — Hyprland Installed"
echo "================================================="
echo
echo "  Next step:"
echo "  Run Part 6 for user environment setup:"
echo "  sudo bash /install/part6-user-setup.sh"
echo
echo "================================================="
