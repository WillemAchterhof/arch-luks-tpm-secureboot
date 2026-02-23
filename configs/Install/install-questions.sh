#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Linux Secure Install - install-questions.sh
#  Writes /tmp/install-settings.conf
#
#  Usage:
#    bash install-questions.sh          # interactive — prompts for each setting
#    bash install-questions.sh default  # silent    — accepts all defaults
# ==============================================================================

MODE="${1:-interactive}"

# ------------------------------------------------------------------------------
# DEFAULTS
# ------------------------------------------------------------------------------

DEFAULT_USERNAME="willem"
DEFAULT_HOSTNAME="WA-Arch"
DEFAULT_TIMEZONE="Europe/Amsterdam"
DEFAULT_MIRROR_COUNTRIES="Netherlands,Germany"
DEFAULT_SHELL="zsh"
DEFAULT_PROFILE="default"
DEFAULT_DE="hyprland"
DEFAULT_TERMINAL_EMU="alacritty"
DEFAULT_FILE_MANAGER="thunar"
DEFAULT_MEDIA_PLAYER="mpv"
DEFAULT_IMAGE_VIEWER="loupe"
DEFAULT_VIRTUALIZATION="qemu-full libvirt virt-manager"
DEFAULT_EXTRA_PACKAGES=""

# ------------------------------------------------------------------------------
# HELPER — prompt or accept default silently
# ------------------------------------------------------------------------------

ask() {
    local prompt="$1"
    local default="$2"
    local result

    if [[ "$MODE" == "default" ]]; then
        echo "$default"
    else
        read -rp "$prompt [$default]: " result
        echo "${result:-$default}"
    fi
}

ask_choice() {
    local prompt="$1"
    local default="$2"
    local result

    if [[ "$MODE" == "default" ]]; then
        echo "$default"
    else
        read -rp "$prompt: " result
        echo "${result:-$default}"
    fi
}

# ------------------------------------------------------------------------------
# COLLECT SETTINGS
# ------------------------------------------------------------------------------

if [[ "$MODE" == "interactive" ]]; then
    clear
    echo "================================================="
    echo "   Arch Linux Secure Installation"
    echo "   Custom Setup"
    echo "================================================="
    echo
    echo "  Press ENTER to accept the default shown in [brackets]."
    echo
fi

# System
USERNAME=$(ask "Username" "$DEFAULT_USERNAME")
HOSTNAME=$(ask "Hostname" "$DEFAULT_HOSTNAME")

TIMEZONE=$(ask "Timezone" "$DEFAULT_TIMEZONE")
if ! timedatectl list-timezones | grep -qx "$TIMEZONE"; then
    echo "[!] Invalid timezone: $TIMEZONE"
    exit 1
fi

MIRROR_COUNTRIES=$(ask "Mirror countries (comma separated)" "$DEFAULT_MIRROR_COUNTRIES")

if [[ "$MODE" == "interactive" ]]; then
    echo
    echo "  Shell options: zsh, bash"
fi
SHELL=$(ask "Shell" "$DEFAULT_SHELL")

# Profile
if [[ "$MODE" == "interactive" ]]; then
    echo
    echo "  Installation profile:"
    echo "  [1] Default — no prompts during install"
    echo "  [2] Interactive — ask per part"
    echo
    PROFILE_CHOICE=$(ask_choice "Select [1]" "1")
    case "$PROFILE_CHOICE" in
        2) PROFILE="interactive" ;;
        *) PROFILE="default" ;;
    esac
else
    PROFILE="$DEFAULT_PROFILE"
fi

# Desktop environment
if [[ "$MODE" == "interactive" ]]; then
    echo
    echo "  Desktop environment:"
    echo "  [1] Hyprland"
    echo "  [2] KDE Plasma  (not yet implemented)"
    echo "  [3] Skip"
    echo
    DE_CHOICE=$(ask_choice "Select [1]" "1")
    case "$DE_CHOICE" in
        2) DE="kde" ;;
        3) DE="skip" ;;
        *) DE="hyprland" ;;
    esac
else
    DE="$DEFAULT_DE"
fi

# Terminal
if [[ "$MODE" == "interactive" ]]; then
    echo
    echo "  Terminal emulator:"
    echo "  [1] Alacritty"
    echo "  [2] Kitty"
    echo "  [3] Foot"
    echo "  [4] Skip"
    echo
    TERM_CHOICE=$(ask_choice "Select [1]" "1")
    case "$TERM_CHOICE" in
        2) TERMINAL_EMU="kitty" ;;
        3) TERMINAL_EMU="foot" ;;
        4) TERMINAL_EMU="skip" ;;
        *) TERMINAL_EMU="alacritty" ;;
    esac
else
    TERMINAL_EMU="$DEFAULT_TERMINAL_EMU"
fi

# File manager
if [[ "$MODE" == "interactive" ]]; then
    echo
    echo "  File manager:"
    echo "  [1] Thunar"
    echo "  [2] Dolphin"
    echo "  [3] Nautilus"
    echo "  [4] Skip"
    echo
    FM_CHOICE=$(ask_choice "Select [1]" "1")
    case "$FM_CHOICE" in
        2) FILE_MANAGER="dolphin" ;;
        3) FILE_MANAGER="nautilus" ;;
        4) FILE_MANAGER="skip" ;;
        *) FILE_MANAGER="thunar" ;;
    esac
else
    FILE_MANAGER="$DEFAULT_FILE_MANAGER"
fi

# Media player
if [[ "$MODE" == "interactive" ]]; then
    echo
    echo "  Media player:"
    echo "  [1] mpv"
    echo "  [2] VLC"
    echo "  [3] Haruna"
    echo "  [4] Skip"
    echo
    MP_CHOICE=$(ask_choice "Select [1]" "1")
    case "$MP_CHOICE" in
        2) MEDIA_PLAYER="vlc" ;;
        3) MEDIA_PLAYER="haruna" ;;
        4) MEDIA_PLAYER="skip" ;;
        *) MEDIA_PLAYER="mpv" ;;
    esac
else
    MEDIA_PLAYER="$DEFAULT_MEDIA_PLAYER"
fi

# Image viewer
if [[ "$MODE" == "interactive" ]]; then
    echo
    echo "  Image viewer:"
    echo "  [1] Loupe"
    echo "  [2] imv"
    echo "  [3] eog"
    echo "  [4] Skip"
    echo
    IV_CHOICE=$(ask_choice "Select [1]" "1")
    case "$IV_CHOICE" in
        2) IMAGE_VIEWER="imv" ;;
        3) IMAGE_VIEWER="eog" ;;
        4) IMAGE_VIEWER="skip" ;;
        *) IMAGE_VIEWER="loupe" ;;
    esac
else
    IMAGE_VIEWER="$DEFAULT_IMAGE_VIEWER"
fi

# Virtualization
if [[ "$MODE" == "interactive" ]]; then
    echo
    echo "  Virtualization:"
    echo "  [1] KVM  (qemu-full libvirt virt-manager)"
    echo "  [2] VirtualBox"
    echo "  [3] Skip"
    echo
    VIRT_CHOICE=$(ask_choice "Select [1]" "1")
    case "$VIRT_CHOICE" in
        2) VIRTUALIZATION="virtualbox" ;;
        3) VIRTUALIZATION="skip" ;;
        *) VIRTUALIZATION="qemu-full libvirt virt-manager" ;;
    esac
else
    VIRTUALIZATION="$DEFAULT_VIRTUALIZATION"
fi

# Extra packages
if [[ "$MODE" == "interactive" ]]; then
    echo
    read -rp "Extra packages (space separated, leave blank to skip): " EXTRA_PACKAGES
    EXTRA_PACKAGES="${EXTRA_PACKAGES:-$DEFAULT_EXTRA_PACKAGES}"
else
    EXTRA_PACKAGES="$DEFAULT_EXTRA_PACKAGES"
fi

# ------------------------------------------------------------------------------
# CONFIRM (interactive only)
# ------------------------------------------------------------------------------

if [[ "$MODE" == "interactive" ]]; then
    clear
    echo "================================================="
    echo "   Installation Summary"
    echo "================================================="
    echo
    echo "  Username:        $USERNAME"
    echo "  Hostname:        $HOSTNAME"
    echo "  Timezone:        $TIMEZONE"
    echo "  Mirrors:         $MIRROR_COUNTRIES"
    echo "  Shell:           $SHELL"
    echo "  Profile:         $PROFILE"
    echo "  DE:              $DE"
    echo "  Terminal:        $TERMINAL_EMU"
    echo "  File manager:    $FILE_MANAGER"
    echo "  Media player:    $MEDIA_PLAYER"
    echo "  Image viewer:    $IMAGE_VIEWER"
    echo "  Virtualization:  $VIRTUALIZATION"
    echo "  Extra packages:  ${EXTRA_PACKAGES:-none}"
    echo
    read -rp "Confirm and continue? (Y/n): " CONFIRM
    if [[ "${CONFIRM,,}" == "n" ]]; then
        echo "[!] Aborted."
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# WRITE /tmp/install-settings.conf
# ------------------------------------------------------------------------------

cat > /tmp/install-settings.conf <<EOF
# ==============================================================================
#  Arch Linux Secure Install - Settings
#  Generated by install-questions.sh
# ==============================================================================

USERNAME="$USERNAME"
HOSTNAME="$HOSTNAME"
TIMEZONE="$TIMEZONE"
MIRROR_COUNTRIES="$MIRROR_COUNTRIES"
SHELL="$SHELL"
PROFILE="$PROFILE"
DE="$DE"
TERMINAL_EMU="$TERMINAL_EMU"
FILE_MANAGER="$FILE_MANAGER"
MEDIA_PLAYER="$MEDIA_PLAYER"
IMAGE_VIEWER="$IMAGE_VIEWER"
VIRTUALIZATION="$VIRTUALIZATION"
EXTRA_PACKAGES="$EXTRA_PACKAGES"
EOF

echo "[*] Settings saved to /tmp/install-settings.conf"