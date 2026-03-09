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

INSTALLER_DIR="$SCRIPT_DIR/installer"
REPO_DIR="$INSTALLER_DIR/repo"

OUTPUT_DIR="$INSTALLER_DIR/output"
STATE_DIR="$OUTPUT_DIR/state"
LOG_DIR="$OUTPUT_DIR/log"
PROFILE_DIR="$OUTPUT_DIR/profiles"

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

# ------------------------------------------------------------------------------
# Prepare folder structure
# ------------------------------------------------------------------------------

mkdir -p \
    "$REPO_DIR" \
    "$STATE_DIR" \
    "$LOG_DIR" \
    "$PROFILE_DIR"

touch "$LOG_FILE"

msg "Arch Secure Installer — Post Boot"

# ------------------------------------------------------------------------------
# Ensure git exists
# ------------------------------------------------------------------------------

ensure_git() {

    if ! command -v git &>/dev/null; then
        msg "Installing git..."
        pacman -Sy --noconfirm git \
            || fatal "Failed to install git."
    fi

}

# ------------------------------------------------------------------------------
# Internet test
# ------------------------------------------------------------------------------

internet_ok() {

    curl -s --fail --max-time 5 https://archlinux.org -o /dev/null \
        || ping -c1 -W2 1.1.1.1 >/dev/null 2>&1

}

# ------------------------------------------------------------------------------
# WiFi auto connect
# ------------------------------------------------------------------------------

connect_wifi() {

    [[ -f "$WIFI_CREDS" ]] || return

    ssid=$(grep '^SSID=' "$WIFI_CREDS" | cut -d= -f2-)
    pass=$(grep '^PASSPHRASE=' "$WIFI_CREDS" | cut -d= -f2-)

    [[ -n "$ssid" ]] || return

    msg "Connecting WiFi: $ssid"

    if [[ -n "$pass" ]]; then
        nmcli device wifi connect "$ssid" password "$pass" \
            || msg "WiFi auto connect failed."
    else
        nmcli device wifi connect "$ssid" \
            || msg "WiFi auto connect failed."
    fi

    shred -u "$WIFI_CREDS" 2>/dev/null || rm -f "$WIFI_CREDS"

}

connect_wifi

# ------------------------------------------------------------------------------
# Internet fallback
# ------------------------------------------------------------------------------

if ! internet_ok; then

cat <<EOF

No internet detected.

Connect WiFi manually:

  nmcli device wifi list
  nmcli device wifi connect "SSID" password "PASSWORD"

Type 'exit' when finished.

EOF

bash --login || true

internet_ok || fatal "Internet still unavailable."

fi

msg "Internet OK"

# ------------------------------------------------------------------------------
# Clone repo
# ------------------------------------------------------------------------------

ensure_git

clone_repo() {

    msg "Cloning installer repository..."

    TEMP_DIR="$(mktemp -d)"

    git clone "$REPO_URL" "$TEMP_DIR" \
        || fatal "git clone failed."

    [[ -d "$TEMP_DIR/repo" ]] \
        || fatal "Repository layout unexpected (Repo/ missing)."

    rm -rf "$REPO_DIR"
    mkdir -p "$REPO_DIR"

    cp -a "$TEMP_DIR/repo/." "$REPO_DIR/" \
        || fatal "Failed installing repo."

    [[ -f "$REPO_DIR/post_install_engine.sh" ]] \
        || fatal "post_install_engine.sh missing."

    msg "Repository installed."

}

if [[ ! -f "$REPO_DIR/post_install_engine.sh" ]]; then
    clone_repo
else
    msg "Repository already present."
fi

# ------------------------------------------------------------------------------
# Write installer state
# ------------------------------------------------------------------------------

if [[ ! -f "$STATE_FILE" ]]; then
    printf "postboot\n" > "$STATE_FILE"
    msg "State initialized: postboot"
fi

# ------------------------------------------------------------------------------
# Fix permissions
# ------------------------------------------------------------------------------

find "$REPO_DIR" -name "*.sh" -exec chmod 750 {} \;

# ------------------------------------------------------------------------------
# Launch post install engine
# ------------------------------------------------------------------------------

ARGS=()

if [[ -f "$POST_PROFILE" ]]; then
    msg "Profile detected — automatic mode."
    ARGS+=(--profile "$POST_PROFILE")
else
    msg "Interactive mode."
fi

msg "Launching post install engine..."

exec bash "$REPO_DIR/post_install_engine.sh" "${ARGS[@]}"