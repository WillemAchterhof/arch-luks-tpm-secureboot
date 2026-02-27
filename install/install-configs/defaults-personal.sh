#!/usr/bin/env bash

# ==============================================================================
#  Arch Linux Secure Install - defaults-personal.sh
#  Willem's personal defaults — HP AMD laptop
#  Sourced by install.sh when [1] Willem's defaults is selected
#  All values can be overridden in get-install-config/get-part*.sh
# ==============================================================================

# ------------------------------------------------------------------------------
# PART 1 — Live
# ------------------------------------------------------------------------------

MIRROR_COUNTRIES="Netherlands,Germany"

# Disk is never prefilled — always requires explicit selection in get-part1.sh
DISK=""

# ------------------------------------------------------------------------------
# PART 2 — Chroot
# ------------------------------------------------------------------------------

USERNAME="willem"
HOSTNAME="WA-Arch"
TIMEZONE="Europe/Amsterdam"
LOCALE="en_US.UTF-8 UTF-8"
LANGUAGE="en_US.UTF-8"
KEYMAP="us"

# Passwords are never prefilled — always prompted during install
# ROOT_PASSWORD=""
# USER_PASSWORD=""

# ------------------------------------------------------------------------------
# PART 3 — Secure Boot
# No configurable settings
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# PART 4 — Post Reboot
# No configurable settings
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# PART 5 — User Environment
# ------------------------------------------------------------------------------

PART5_ENABLED=1

INSTALL_EDITOR="nvim"
INSTALL_SHELL="zsh"
TERMINAL_EMU="alacritty"

# Set Environment varialbes.
cat <<EOF > /etc/environment
TERMINAL="$TERMINAL_EMU"
EDITOR="$INSTALL_EDITOR"
VISUAL="$INSTALL_EDITOR"
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
SDL_VIDEODRIVER=wayland
EOF

# ------------------------------------------------------------------------------
# PART 6 — Software
# ------------------------------------------------------------------------------

PART6_ENABLED=1

FILE_MANAGER="thunar"
MEDIA_PLAYER="mpv"
IMAGE_VIEWER="loupe"
VIRTUALIZATION="qemu-full libvirt virt-manager"
EXTRA_PACKAGES=""

# ------------------------------------------------------------------------------
# PART 7 — Desktop Environment
# ------------------------------------------------------------------------------

PART7_ENABLED=1

DE="hyprland"