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
# ENABLE REPOS & UPDATE
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

# ------------------------------------------------------------------------------
# OPTIONAL: Rofi-Wayland (AUR)
# ------------------------------------------------------------------------------

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

echo "[*] Installing AMD GPU + Vulkan stack..."

pacman -S --noconfirm \
    mesa vulkan-radeon libva-mesa-driver \
    lib32-mesa lib32-vulkan-radeon lib32-libva-mesa-driver

# ------------------------------------------------------------------------------
# FONTS
# ------------------------------------------------------------------------------

echo "[*] Installing fonts..."

pacman -S --noconfirm \
    ttf-dejavu ttf-liberation \
    noto-fonts noto-fonts-cjk noto-fonts-emoji

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

pacman -S --noconfirm dotnet-sdk code

sudo -u "$USERNAME" yay -S --noconfirm powershell-bin

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

# ------------------------------------------------------------------------------
# UTILITIES
# ------------------------------------------------------------------------------

echo "[*] Installing utilities..."

pacman -S --noconfirm \
    alacritty btop fastfetch keepassxc \
    xdg-user-dirs xdg-utils

sudo -u "$USERNAME" xdg-user-dirs-update

# ------------------------------------------------------------------------------
# COPY USER CONFIG (Hyprland)
# ------------------------------------------------------------------------------

echo "[*] Creating Hyprland config directory..."

sudo -u "$USERNAME" mkdir -p "/home/$USERNAME/.config/hypr"

echo "[*] Copying your existing hyprland.conf..."

sudo -u "$USERNAME" cp /install/hyprland.conf "/home/$USERNAME/.config/hypr/hyprland.conf"

hyprctl reload

# ------------------------------------------------------------------------------
# DONE
# ------------------------------------------------------------------------------

echo
echo "================================================="
echo "   Part 5 Complete — Hyprland Installed"
echo "================================================="
echo
echo "You can now log out and select Hyprland in your login manager,"
echo "or run it directly from TTY with:"
echo
echo "   exec Hyprland"
echo
echo "Enjoy your new desktop!"
echo "================================================="
