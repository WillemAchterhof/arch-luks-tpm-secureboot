#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Secure Installer — Post-Boot Bootstrap
# ==============================================================================
#  Mirrors arch_secure_install.sh structure.
#  Goals:
#    • Auto-connect WiFi from saved credentials
#    • Fallback to terminal with nmcli instructions
#    • Clone repo from GitHub
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

msg()   { printf "\n[*] %s\n\n" "$1" | tee -a "$LOG_FILE"; }
fatal() { printf "\n[FATAL] %s\n\n" "$1" | tee -a "$LOG_FILE"; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fatal "Required command '$1' not found."
}

ensure_git() {
    if ! command -v git &>/dev/null; then
        msg "git not found — installing..."
        pacman -Sy --noconfirm git \
            || fatal "Failed to install git."
    fi
}

# ------------------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------------------

mkdir -p "$INSTALLER_DIR" "$STATE_DIR"
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

    # Re-check after terminal session
    internet_ok || fatal "Still no internet after terminal session — re-run when connected."
fi

msg "Internet OK."

# ------------------------------------------------------------------------------
# Repo verification
# ------------------------------------------------------------------------------

verify_repo_structure() {
    local manifest="$REPO_DIR/install/lib/required_files.conf"
    [[ -f "$manifest" ]] || { echo "  missing: install/lib/required_files.conf"; return 1; }

    local ok=true
    while IFS= read -r file; do
        [[ -z "$file" || "$file" == \#* ]] && continue
        [[ -f "$REPO_DIR/$file" ]] \
            || { echo "  missing: $file"; ok=false; }
    done < "$manifest"

    [[ "$ok" == true ]]
}

verify_repo_commit() {
    [[ "$PINNED_COMMIT" == "skip" ]] && return 0
    [[ -d "$REPO_DIR/.git" ]] || return 1

    local repo_commit
    repo_commit="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)" || return 1
    [[ "$repo_commit" == "$PINNED_COMMIT" ]]
}

# ------------------------------------------------------------------------------
# Clone / update repo
# ------------------------------------------------------------------------------

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
    ensure_git

    TEMP_DIR="$(mktemp -d)"

    if [[ "$PINNED_COMMIT" == "skip" ]]; then
        git clone "$REPO_URL" "$TEMP_DIR/repo" \
            || fatal "git clone failed."
    else
        git clone --no-checkout "$REPO_URL" "$TEMP_DIR/repo" \
            || fatal "git clone failed."
        git -C "$TEMP_DIR/repo" fetch --depth 1 origin "$PINNED_COMMIT" \
            || fatal "Pinned commit not found in remote."
        git -C "$TEMP_DIR/repo" checkout "$PINNED_COMMIT" \
            || fatal "Could not checkout pinned commit."
    fi

    rotate_repo
}

if [[ -d "$REPO_DIR" ]]; then
    msg "Existing repo found — verifying..."
    if verify_repo_structure && verify_repo_commit; then
        msg "Repo OK."
    else
        msg "Repo invalid — reinstalling..."
        download_repo
        verify_repo_structure || fatal "Repo invalid after reinstall."
    fi
else
    msg "Repo missing — cloning..."
    download_repo
    verify_repo_structure || fatal "Repo invalid after install."
fi

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

HANDOFF_ARGS=(
    --state-dir "$STATE_DIR"
    --log-dir   "$INSTALLER_DIR/output/logs"
)

if [[ -f "$POST_PROFILE" ]]; then
    msg "Post profile found — running in automatic mode."
    HANDOFF_ARGS+=(--profile "$POST_PROFILE")
else
    msg "No post profile found — running in interactive mode."
fi

msg "Bootstrap complete — launching post-install engine..."
exec bash "$REPO_DIR/post_install_engine.sh" "${HANDOFF_ARGS[@]}"