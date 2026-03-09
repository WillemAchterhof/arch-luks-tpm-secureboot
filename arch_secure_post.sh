#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Arch Secure Installer — Post-Boot Bootstrap
# ==============================================================================

# ------------------------------------------------------------------------------
# Root check
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Mirror USB structure exactly:
#   INSTALLER_DIR = USB_ROOT  (~/installer)
#   REPO_DIR      = USB_ROOT/repo
# post_install_engine.sh lives at REPO_DIR/post_install_engine.sh
# file_paths.sh builds: USB_ROOT=INSTALLER_DIR, OUTPUT=INSTALLER_DIR/output
INSTALLER_DIR="$SCRIPT_DIR/installer"
REPO_DIR="$INSTALLER_DIR/repo"

OUTPUT_DIR="$INSTALLER_DIR/output"
STATE_DIR="$OUTPUT_DIR/state"
LOG_DIR="$OUTPUT_DIR/log"
PROFILE_DIR="$OUTPUT_DIR/profile"

STATE_FILE="$STATE_DIR/install.state"
WIFI_CREDS="$SCRIPT_DIR/.wifi_creds"
POST_PROFILE="$SCRIPT_DIR/post_default.conf"
LOG_FILE="$INSTALLER_DIR/postboot_bootstrap.log"

TEMP_DIR=""

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------

cleanup_temp() {
    [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}
trap cleanup_temp EXIT

# ------------------------------------------------------------------------------
# Create dirs + log file before any msg() calls
# ------------------------------------------------------------------------------

mkdir -p "$INSTALLER_DIR" "$REPO_DIR" "$STATE_DIR" "$LOG_DIR" "$PROFILE_DIR"
touch "$LOG_FILE"

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------

msg() {
    printf "\n[*] %s\n\n" "$1"
    printf "[*] %s\n" "$1" >> "$LOG_FILE"
}

fatal() {
    printf "\n[FATAL] %s\n\n" "$1"
    printf "[FATAL] %s\n" "$1" >> "$LOG_FILE"
    exit 1
}

msg "Arch Secure Installer — Post Boot Bootstrap"
msg "INSTALLER_DIR : $INSTALLER_DIR"
msg "REPO_DIR      : $REPO_DIR"

# ------------------------------------------------------------------------------
# Ensure git
# ------------------------------------------------------------------------------

ensure_git() {
    command -v git &>/dev/null && return
    msg "Installing git..."
    pacman -Sy --noconfirm git || fatal "Failed to install git."
}

# ------------------------------------------------------------------------------
# Internet check
# ------------------------------------------------------------------------------

internet_ok() {
    curl -s --fail --max-time 5 https://archlinux.org -o /dev/null \
        || ping -c1 -W2 1.1.1.1 >/dev/null 2>&1
}

# ------------------------------------------------------------------------------
# WiFi auto connect
# ------------------------------------------------------------------------------

connect_wifi() {
    [[ -f "$WIFI_CREDS" ]] || { msg "No saved WiFi credentials."; return; }

    local ssid pass
    ssid=$(grep '^SSID='       "$WIFI_CREDS" | cut -d= -f2-)
    pass=$(grep '^PASSPHRASE=' "$WIFI_CREDS" | cut -d= -f2-)

    [[ -n "$ssid" ]] || { msg "WiFi credential file invalid."; rm -f "$WIFI_CREDS"; return; }

    msg "Connecting to WiFi: $ssid"

    local retries=10
    while ! nmcli general status &>/dev/null && (( retries-- > 0 )); do sleep 1; done

    if [[ -n "$pass" ]]; then
        nmcli device wifi connect "$ssid" password "$pass" \
            && msg "WiFi connected: $ssid" \
            || msg "WiFi auto-connect failed — will retry manually if needed."
    else
        nmcli device wifi connect "$ssid" \
            && msg "WiFi connected: $ssid" \
            || msg "WiFi auto-connect failed — will retry manually if needed."
    fi

    shred -u "$WIFI_CREDS" 2>/dev/null || rm -f "$WIFI_CREDS"
}

connect_wifi

# ------------------------------------------------------------------------------
# Internet fallback — interactive shell
# ------------------------------------------------------------------------------

if ! internet_ok; then
    printf "\n"
    printf "==========================================\n"
    printf " No internet detected\n"
    printf "==========================================\n"
    printf "\n"
    printf " Connect WiFi manually:\n"
    printf "\n"
    printf "   nmcli device wifi list\n"
    printf "   nmcli device wifi connect \"SSID\" password \"PASSWORD\"\n"
    printf "\n"
    printf " Type 'exit' when finished.\n"
    printf "\n"
    printf "==========================================\n"
    printf "\n"

    bash --login || true
    internet_ok || fatal "Internet still unavailable."
fi

msg "Internet OK."

# ------------------------------------------------------------------------------
# Clone repo into REPO_DIR
# Clones GitHub repo root directly into ~/installer/repo/
# Result: ~/installer/repo/post_install_engine.sh
#         ~/installer/repo/install/
# ------------------------------------------------------------------------------

ensure_git

clone_repo() { msg "Cloning installer repository..." TEMP_DIR="$(mktemp -d)" git clone "$REPO_URL" "$TEMP_DIR" \ || fatal "git clone failed." [[ -d "$TEMP_DIR/Repo" ]] \ || fatal "Repository layout unexpected (Repo/ missing)." rm -rf "$REPO_DIR" mkdir -p "$REPO_DIR" cp -a "$TEMP_DIR/Repo/." "$REPO_DIR/" \ || fatal "Failed installing repo." [[ -f "$REPO_DIR/post_install_engine.sh" ]] \ || fatal "post_install_engine.sh missing." msg "Repository installed." }

if [[ -f "$REPO_DIR/post_install_engine.sh" ]]; then
    msg "Repository already present at $REPO_DIR."
else
    clone_repo
fi

# ------------------------------------------------------------------------------
# Write state
# ------------------------------------------------------------------------------

if [[ ! -f "$STATE_FILE" ]]; then
    printf "postboot\n" > "$STATE_FILE"
    msg "State initialized: postboot"
else
    msg "State file exists: $(cat "$STATE_FILE")"
fi

# ------------------------------------------------------------------------------
# Fix permissions
# ------------------------------------------------------------------------------

find "$REPO_DIR" -name "*.sh" -exec chmod 750 {} \;

# ------------------------------------------------------------------------------
# Launch post_install_engine.sh
# ------------------------------------------------------------------------------

ARGS=()
[[ -f "$POST_PROFILE" ]] \
    && { msg "Profile found — automatic mode."; ARGS+=(--profile "$POST_PROFILE"); } \
    || msg "No profile — interactive mode."

msg "Launching: $REPO_DIR/post_install_engine.sh"

exec bash "$REPO_DIR/post_install_engine.sh" "${ARGS[@]}"