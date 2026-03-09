#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Secure Installer — Post-Boot Bootstrap
# ==============================================================================
#  Mirrors arch_secure_install.sh structure.
#  Goals:
#    • Auto-connect WiFi from saved credentials
#    • Fallback to terminal with nmcli instructions
#    • Clone repo from GitHub into ~/installer/repo/
#    • Hand off to post_install_engine.sh
# ==============================================================================

# ------------------------------------------------------------------------------
# Check for root
# ------------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    printf "\n[FATAL] Must be run as root.\n"
    printf "        sudo bash arch_secure_post.sh\n\n"
    exit 1
fi

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

REPO_URL="https://github.com/WillemAchterhof/arch-luks-tpm-secureboot.git"
PINNED_COMMIT="skip"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$SCRIPT_DIR/installer"
REPO_DIR="$INSTALLER_DIR/repo"
# State path must match what file_paths.sh builds from USB_ROOT=~/installer:
#   OUTPUT_FOLDER = ~/installer/output
#   STATE_FOLDER  = ~/installer/output/state
STATE_DIR="$INSTALLER_DIR/output/state"
STATE_FILE="$STATE_DIR/install.state"
WIFI_CREDS="$SCRIPT_DIR/.wifi_creds"
POST_PROFILE="$SCRIPT_DIR/post_default.conf"
LOG_FILE="$INSTALLER_DIR/postboot_bootstrap.log"

TEMP_DIR=""

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------

cleanup_temp() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup_temp EXIT

# ------------------------------------------------------------------------------
# Utilities
# ------------------------------------------------------------------------------

msg() {
    printf "\n[*] %s\n\n" "$1"
    [[ -f "$LOG_FILE" ]] && printf "[*] %s\n" "$1" >> "$LOG_FILE" || true
}
fatal() {
    printf "\n[FATAL] %s\n\n" "$1"
    [[ -f "$LOG_FILE" ]] && printf "[FATAL] %s\n" "$1" >> "$LOG_FILE" || true
    exit 1
}

ensure_git() {
    if ! command -v git &>/dev/null; then
        msg "git not found — installing..."
        pacman -Sy --noconfirm git \
            || fatal "Failed to install git."
    fi
}

# ------------------------------------------------------------------------------
# Setup — must happen before any msg() calls
# ------------------------------------------------------------------------------

mkdir -p "$INSTALLER_DIR" "$STATE_DIR" "$INSTALLER_DIR/output/logs"
touch "$LOG_FILE"

msg "Arch Secure Post-Boot Bootstrap"
msg "Log: $LOG_FILE"

# ------------------------------------------------------------------------------
# WiFi — auto connect from saved creds, fallback to terminal
# ------------------------------------------------------------------------------

connect_wifi() {
    if [[ ! -f "$WIFI_CREDS" ]]; then
        msg "No saved WiFi credentials found — skipping auto-connect."
        return
    fi

    local ssid passphrase
    ssid=$(      grep '^SSID='       "$WIFI_CREDS" | cut -d= -f2-)
    passphrase=$(grep '^PASSPHRASE=' "$WIFI_CREDS" | cut -d= -f2-)

    if [[ -z "$ssid" ]]; then
        msg "WiFi creds file exists but SSID is empty — skipping."
        shred -u "$WIFI_CREDS" 2>/dev/null || rm -f "$WIFI_CREDS"
        return
    fi

    msg "Auto-connecting to WiFi: $ssid"

    # Wait for NetworkManager to be ready
    local retries=10
    while ! nmcli general status &>/dev/null && (( retries-- > 0 )); do
        sleep 1
    done

    if [[ -n "$passphrase" ]]; then
        nmcli device wifi connect "$ssid" password "$passphrase" \
            && msg "WiFi connected: $ssid" \
            || msg "[!] Auto-connect failed for: $ssid"
    else
        nmcli device wifi connect "$ssid" \
            && msg "WiFi connected: $ssid" \
            || msg "[!] Auto-connect failed for: $ssid"
    fi

    # Shred creds immediately after use
    shred -u "$WIFI_CREDS" 2>/dev/null || rm -f "$WIFI_CREDS"
    msg "WiFi credentials removed."
}

connect_wifi

# ------------------------------------------------------------------------------
# Internet check — fallback to terminal with instructions
# ------------------------------------------------------------------------------

internet_ok() {
    curl -s --fail --max-time 5 https://archlinux.org/mirrorlist/ -o /dev/null \
        || ping -c1 -W2 1.1.1.1 >/dev/null 2>&1
}

if ! internet_ok; then
    cat << 'EOF'

================================================
  No internet detected.
================================================

  Connect WiFi with nmcli:

    nmcli device wifi list
    nmcli device wifi connect "SSID" password "PASSWORD"

  Or for a hidden network:

    nmcli device wifi connect "SSID" password "PASSWORD" hidden yes

  Once connected, type: exit

================================================
EOF
    bash --login || true

    internet_ok || fatal "Still no internet — re-run when connected."
fi

msg "Internet OK."

# ------------------------------------------------------------------------------
# Clone repo — mirrors arch_secure_install.sh rotate_repo pattern
# Clones into TEMP_DIR, then copies into INSTALLER_DIR/repo/
# so structure mirrors the USB: INSTALLER_DIR acts as USB_ROOT
# ------------------------------------------------------------------------------

ensure_git

rotate_repo() {
    [[ -d "$INSTALLER_DIR/repo.old" ]] && rm -rf "$INSTALLER_DIR/repo.old"
    [[ -d "$REPO_DIR" ]] && mv "$REPO_DIR" "$INSTALLER_DIR/repo.old"

    cp -a "$TEMP_DIR/repo/." "$REPO_DIR/" \
        || fatal "cp failed during repo install."

    [[ -f "$REPO_DIR/post_install_engine.sh" ]] \
        || fatal "post_install_engine.sh missing after install."

    rm -rf "$INSTALLER_DIR/repo.old"
    msg "Repo installed."
}

download_repo() {
    msg "Fetching repo from GitHub..."

    TEMP_DIR="$(mktemp -d)"
    git clone "$REPO_URL" "$TEMP_DIR" \
        || fatal "git clone failed."

    rotate_repo
}

if [[ -d "$REPO_DIR" && -f "$REPO_DIR/post_install_engine.sh" ]]; then
    msg "Repo already present — OK."
else
    msg "Repo missing or invalid — cloning..."
    download_repo
fi

[[ -f "$REPO_DIR/post_install_engine.sh" ]] \
    || fatal "post_install_engine.sh missing from repo."

# ------------------------------------------------------------------------------
# Write postboot state
# ------------------------------------------------------------------------------

if [[ ! -f "$STATE_FILE" ]]; then
    printf 'postboot\n' > "$STATE_FILE"
    msg "State set to: postboot"
else
    msg "State file already exists: $(cat "$STATE_FILE")"
fi

# ------------------------------------------------------------------------------
# Fix permissions
# ------------------------------------------------------------------------------

find "$REPO_DIR" -name "*.sh" -exec chmod 750 {} \;

# ------------------------------------------------------------------------------
# Hand off to post_install_engine.sh
# ------------------------------------------------------------------------------

HANDOFF_ARGS=()

if [[ -f "$POST_PROFILE" ]]; then
    msg "Post profile found — running in automatic mode."
    HANDOFF_ARGS+=(--profile "$POST_PROFILE")
else
    msg "No post profile found — running in interactive mode."
fi

msg "Bootstrap complete — launching post-install engine..."
exec bash "$REPO_DIR/post_install_engine.sh" "${HANDOFF_ARGS[@]}"
