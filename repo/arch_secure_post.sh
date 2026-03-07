#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Secure Installer — Post-Boot Bootstrap
# ==============================================================================
#  Runs on first boot from ~/.bash_profile autostart.
#  Goals:
#    • Reconnect WiFi using saved credentials
#    • Clone repo from GitHub
#    • Set up ~/installer/ state folder with STATE=postboot
#    • Hand off to post_install_engine.sh
# ==============================================================================

REPO_URL="https://github.com/WillemAchterhof/arch-luks-tpm-secureboot.git"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$SCRIPT_DIR/installer"
REPO_DIR="$INSTALLER_DIR/repo"
STATE_DIR="$INSTALLER_DIR/output/state"
STATE_FILE="$STATE_DIR/install.state"
WIFI_CREDS="$SCRIPT_DIR/.wifi_creds"
POST_PROFILE="$SCRIPT_DIR/post_default.conf"
LOG_FILE="$INSTALLER_DIR/postboot_bootstrap.log"

# ------------------------------------------------------------------------------
# Utilities
# ------------------------------------------------------------------------------

msg()   { printf "\n[*] %s\n\n" "$1" | tee -a "$LOG_FILE"; }
fatal() { printf "\n[FATAL] %s\n\n" "$1" | tee -a "$LOG_FILE"; exit 1; }

# ------------------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------------------

mkdir -p "$INSTALLER_DIR" "$STATE_DIR"
touch "$LOG_FILE"

msg "Arch Secure Post-Boot Bootstrap"
msg "Log: $LOG_FILE"

# ------------------------------------------------------------------------------
# WiFi
# ------------------------------------------------------------------------------

connect_wifi() {
    if [[ ! -f "$WIFI_CREDS" ]]; then
        msg "No saved WiFi credentials found — skipping WiFi setup."
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

    msg "Connecting to WiFi: $ssid"

    # Wait for NetworkManager to be ready
    local retries=10
    while ! nmcli general status &>/dev/null && (( retries-- > 0 )); do
        sleep 1
    done

    if [[ -n "$passphrase" ]]; then
        nmcli device wifi connect "$ssid" password "$passphrase" \
            && msg "WiFi connected: $ssid" \
            || msg "[!] WiFi connect failed — continuing without WiFi."
    else
        nmcli device wifi connect "$ssid" \
            && msg "WiFi connected: $ssid" \
            || msg "[!] WiFi connect failed — continuing without WiFi."
    fi

    # Shred creds now that we've used them
    shred -u "$WIFI_CREDS" 2>/dev/null || rm -f "$WIFI_CREDS"
    msg "WiFi credentials removed."
}

connect_wifi

# ------------------------------------------------------------------------------
# Internet check
# ------------------------------------------------------------------------------

msg "Checking internet connectivity..."

retries=12
until curl -s --fail --max-time 5 https://archlinux.org/mirrorlist/ -o /dev/null \
      || ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; do
    (( retries-- )) || fatal "No internet after retries — connect manually and re-run."
    msg "Waiting for internet... ($retries retries left)"
    sleep 5
done

msg "Internet OK."

# ------------------------------------------------------------------------------
# Clone repo
# ------------------------------------------------------------------------------

ensure_git() {
    if ! command -v git &>/dev/null; then
        msg "git not found — installing..."
        sudo pacman -Sy --noconfirm git \
            || fatal "Failed to install git."
    fi
}

ensure_git

if [[ -d "$REPO_DIR" ]]; then
    msg "Repo already present — pulling latest..."
    git -C "$REPO_DIR" pull --ff-only \
        || msg "[!] git pull failed — using existing repo."
else
    msg "Cloning repo from GitHub..."
    git clone "$REPO_URL" "$REPO_DIR" \
        || fatal "git clone failed."
fi

[[ -f "$REPO_DIR/post_install_engine.sh" ]] \
    || fatal "post_install_engine.sh missing from cloned repo."

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
# Hand off
# ------------------------------------------------------------------------------

HANDOFF_ARGS=(
    --state-dir "$STATE_DIR"
    --log-dir   "$INSTALLER_DIR/output/logs"
)

# If post_default.conf exists next to this script, pass it as profile
if [[ -f "$POST_PROFILE" ]]; then
    msg "Post profile found — running in automatic mode."
    HANDOFF_ARGS+=(--profile "$POST_PROFILE")
else
    msg "No post profile found — running in interactive mode."
fi

msg "Bootstrap complete — launching post-install engine..."
exec bash "$REPO_DIR/post_install_engine.sh" "${HANDOFF_ARGS[@]}"