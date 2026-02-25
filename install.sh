#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Linux Secure Install - install.sh
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT" || exit
export REPO_ROOT

GITHUB_RAW="https://raw.githubusercontent.com/WillemAchterhof/arch-luks-tpm-secureboot/main"
export GITHUB_RAW

LOG_FILE="/tmp/install.log"
VERBOSE=true

# shellcheck source=/dev/null
source "$REPO_ROOT/install/lib/common.sh"

clear
echo "================================================="
echo "   Arch Linux Secure Installation"
echo "================================================="
echo

# NETWORK CHECK / SETUP ------------------------------------------------

if has_internet; then
    log "[*] Internet connection detected."
else
    log "[!] No internet connection detected."

    if [[ -f "$REPO_ROOT/install/network-setup.sh" ]]; then
        log "[*] Launching network setup..."
        bash "$REPO_ROOT/install/network-setup.sh"

        if ! has_internet; then
            log "[!] Still no internet connection. Aborting."
            exit 1
        fi
    else
        log "[!] network-setup.sh not found."
        log "    Connect manually using iwctl, then re-run install.sh:"
        log ""
        log "    iwctl"
        log "    > device list"
        log "    > station <device> scan"
        log "    > station <device> get-networks"
        log "    > station <device> connect <SSID>"
        log "    > exit"
        log ""
        log "    Then: bash install.sh"
        exit 1
    fi
fi

# REQUIRED CHECK FILES -------------------------------------------------

CHECK_FILES=(
    # "install/file-integrity-check.sh"
    "install/secure-boot.sh"
    "install/pacman-mirrors.sh"
)

log "[*] Verifying required install check files..."

for f in "${CHECK_FILES[@]}"; do
    if [[ ! -f "$REPO_ROOT/$f" ]]; then
        log "[*] Fetching missing file: $(basename "$f")"
        mkdir -p "$(dirname "$REPO_ROOT/$f")"
        fetch_file "$GITHUB_RAW/$f" "$REPO_ROOT/$f"
    else
        log "    Already present: $(basename "$f")"
    fi
done

shopt -s nullglob
chmod +x "$REPO_ROOT"/install/*.sh || true
shopt -u nullglob

log "[*] All required install checks ready."

# RUN CHECKS -----------------------------------------------------------

log "[*] Running system checks..."
echo

if ! bash "$REPO_ROOT/install/secure-boot.sh"; then
    log "[!] Secure Boot check failed."
    exit 1
fi

if ! bash "$REPO_ROOT/install/pacman-mirrors.sh"; then
    log "[!] Pacman mirrors check failed."
    exit 1
fi

log "[*] System checks complete — ready to configure."

# LOAD MENU ------------------------------------------------------------

if [[ -f "$REPO_ROOT/menu.sh" ]]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/menu.sh"
    main_menu
else
    log "[!] Menu file not found: $REPO_ROOT/menu.sh"
    exit 1
fi