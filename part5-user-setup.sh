#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Linux Secure Install - Part 6 (User Environment Setup)
#  Run this AFTER Part 5, as root (sudo)
#  Sets up shell, editor configs, USBGuard, Plymouth, extra tools
# ==============================================================================

clear
echo "================================================="
echo "   Arch Linux Secure Installation - Part 6"
echo "   User Environment & Security Setup"
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

HOME_DIR="/home/$USERNAME"

# ------------------------------------------------------------------------------
# EXTRA PACKAGES
# ------------------------------------------------------------------------------

echo "[*] Installing extra packages..."

pacman -S --noconfirm \
    zsh-autosuggestions \
    binutils \
    inotify-tools \
    usbguard \
    plymouth

# ------------------------------------------------------------------------------
# WIREPLUMBER USER SERVICE
# ------------------------------------------------------------------------------

echo "[*] Enabling WirePlumber for $USERNAME..."
sudo -u "$USERNAME" systemctl --user enable --now wireplumber || true

# ------------------------------------------------------------------------------
# ZSH CONFIGURATION
# ------------------------------------------------------------------------------

echo "[*] Setting up Zsh for $USERNAME..."

# Copy zsh config from /install/configs if it exists, otherwise create a base one
if [[ -f /install/configs/.zshrc ]]; then
    cp /install/configs/.zshrc "$HOME_DIR/.zshrc"
    chown "$USERNAME:$USERNAME" "$HOME_DIR/.zshrc"
    echo "[*] Copied .zshrc from install configs."
else
    echo "[*] No .zshrc found in install configs, writing base config..."
    cat > "$HOME_DIR/.zshrc" << 'EOF'
# ==============================================================================
# Zsh Configuration - Tokyo Night
# ==============================================================================

# History
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY

# Autosuggestions
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# Aliases
alias ls='ls --color=auto'
alias ll='ls -lah'
alias la='ls -A'
alias grep='grep --color=auto'
alias vim='nvim'
alias vi='nvim'

# Prompt (simple, replace with starship or p10k later)
autoload -Uz promptinit
promptinit
prompt walters
EOF
    chown "$USERNAME:$USERNAME" "$HOME_DIR/.zshrc"
fi

# ------------------------------------------------------------------------------
# NEOVIM CONFIGURATION
# ------------------------------------------------------------------------------

echo "[*] Setting up Neovim for $USERNAME..."

sudo -u "$USERNAME" mkdir -p "$HOME_DIR/.config/nvim"

if [[ -f /install/configs/init.lua ]]; then
    cp /install/configs/init.lua "$HOME_DIR/.config/nvim/init.lua"
    chown "$USERNAME:$USERNAME" "$HOME_DIR/.config/nvim/init.lua"
    echo "[*] Copied init.lua from install configs."
else
    echo "[*] No init.lua found in install configs, writing base config..."
    cat > "$HOME_DIR/.config/nvim/init.lua" << 'EOF'
-- ==============================================================================
-- Neovim Base Config - Tokyo Night
-- ==============================================================================

-- Basic settings
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.termguicolors = true
vim.opt.clipboard = "unnamedplus"
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 100
vim.opt.mouse = "a"

-- Leader key
vim.g.mapleader = " "

-- Basic keymaps
vim.keymap.set("n", "<leader>e", vim.cmd.Ex)
vim.keymap.set("n", "<C-s>", "<cmd>w<cr>")
vim.keymap.set("n", "<C-q>", "<cmd>q<cr>")
EOF
    chown -R "$USERNAME:$USERNAME" "$HOME_DIR/.config/nvim"
fi

# ------------------------------------------------------------------------------
# USBGUARD SETUP
# ------------------------------------------------------------------------------

echo
echo "================================================="
echo "   USBGuard Setup"
echo "================================================="
echo
echo "  USBGuard will whitelist currently connected USB"
echo "  devices and block all others."
echo
echo "  Make sure ALL USB devices you want to allow are"
echo "  plugged in RIGHT NOW (keyboard, mouse, etc.)"
echo
read -rp "Press ENTER when all your USB devices are connected..." _

echo "[*] Generating USBGuard policy from connected devices..."
usbguard generate-policy > /etc/usbguard/rules.conf

echo "[*] Enabling USBGuard service..."
systemctl enable --now usbguard

echo
echo "[*] Currently allowed USB devices:"
usbguard list-devices --allowed

echo
echo "================================================="
echo "   USBGuard Device Management"
echo "================================================="
echo
echo "  Useful commands for managing USB devices later:"
echo
echo "  List all devices:"
echo "    usbguard list-devices"
echo
echo "  Allow a device permanently (no password needed again):"
echo "    usbguard allow-device -p <id>"
echo
echo "  Block a device:"
echo "    usbguard block-device <id>"
echo
read -rp "Press ENTER to continue..." _

# ------------------------------------------------------------------------------
# PLYMOUTH THEME
# ------------------------------------------------------------------------------

echo "[*] Configuring Plymouth..."

# Add plymouth to mkinitcpio hooks
sed -i 's|^HOOKS=.*|HOOKS=(base systemd keyboard autodetect modconf kms microcode block sd-encrypt plymouth filesystems fsck)|' /etc/mkinitcpio.conf

# Set a theme - bgrt uses OEM logo, fallback to spinner
if plymouth-set-default-theme bgrt 2>/dev/null; then
    echo "[*] Plymouth theme set to bgrt (OEM logo)."
else
    plymouth-set-default-theme spinner
    echo "[*] Plymouth theme set to spinner."
fi

echo "[*] Rebuilding UKI with Plymouth..."
mkinitcpio -P

# ------------------------------------------------------------------------------
# DONE
# ------------------------------------------------------------------------------

echo
echo "================================================="
echo "   Part 6 Complete"
echo "================================================="
echo
echo "  What was set up:"
echo "  - Zsh with autosuggestions"
echo "  - Neovim base config"
echo "  - USBGuard with current devices whitelisted"
echo "  - Plymouth boot splash"
echo
echo "  Reboot to confirm Plymouth boot splash works."
echo
echo "================================================="
