#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Linux Secure Install - install.sh
#  Run from Arch ISO
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
export REPO_ROOT

GITHUB_RAW="https://raw.githubusercontent.com/WillemAchterhof/arch-luks-tpm-secureboot/main"
export GITHUB_RAW

clear
echo "================================================="
echo "   Arch Linux Secure Installation"
echo "================================================="
echo

# ==============================================================================
# HELPER — Check Internet Connectivity
# ==============================================================================

has_internet() {
    curl -s --head --fail --max-time 3 https://archlinux.org >/dev/null
}

# ==============================================================================
# HELPER — Fetch File with Retry
# ==============================================================================

fetch_file() {
    local url="$1"
    local dest="$2"
    local filename
    filename=$(basename "$dest")

    for attempt in 1 2 3; do
        if curl -fsSL "$url" -o "$dest"; then
            return 0
        fi
        echo "  [!] Failed to fetch $filename (attempt $attempt)."
        [[ $attempt -lt 3 ]] && echo "      Retrying in 3 seconds..." && sleep 3
    done

    echo
    echo "[!] Could not fetch $filename after 3 attempts."
    echo "    Check your connection and re-run install.sh"
    exit 2
}

# --------------------------------------------------------------------------
# Ensure internet connection before fetching
# --------------------------------------------------------------------------

if has_internet; then
    echo "[*] Internet connection detected."
else
    echo "[!] No internet connection detected."
    echo

    if [[ -f "$REPO_ROOT/install-checks/network-setup.sh" ]]; then
        echo "[*] Launching network setup..."
        bash "$REPO_ROOT/install-checks/network-setup.sh"

        echo "[*] Re-checking internet..."
        if ! has_internet; then
            echo "[!] Still no internet connection. Aborting."
            exit 1
        fi
    else
        echo "[!] network-setup.sh not found."
        echo
        echo "  Connect manually using iwctl, then re-run install.sh:"
        echo
        echo "     iwctl"
        echo "     > device list"
        echo "     > station <device> scan"
        echo "     > station <device> get-networks"
        echo "     > station <device> connect <SSID>"
        echo "     > exit"
        echo
        echo "     Then: bash install.sh"
        exit 1
    fi
fi

# ==============================================================================
# REQUIRED CHECK FILES
# ==============================================================================

CHECK_FILES=(
    "install-checks/file-integrity-check.sh"
    "install-checks/secure-boot-check.sh"
    "install-checks/pacman-mirrors-check.sh"
)

# ==============================================================================
# Verify files exist locally
# ==============================================================================

echo "[*] Verifying required install-checks files..."

CHECKS_MISSING=false
for f in "${CHECK_FILES[@]}"; do
    if [[ ! -f "$REPO_ROOT/$f" ]]; then
        CHECKS_MISSING=true
    fi
done

if [[ "$CHECKS_MISSING" == true ]]; then
    echo "[!] Some required files are missing."

    # --------------------------------------------------------------------------
    # Fetch missing files from GitHub
    # --------------------------------------------------------------------------

    echo
    echo "[*] Fetching install-checks from GitHub..."
    mkdir -p "$REPO_ROOT/install-checks"

    for f in "${CHECK_FILES[@]}"; do
    if [[ ! -f "$REPO_ROOT/$f" ]]; then
        filename=$(basename "$f")
        echo "    Fetching $filename..."
        fetch_file "$GITHUB_RAW/$f" "$REPO_ROOT/$f"
    else
        echo "    Already present: $(basename "$f")"
    fi
    done

    chmod +x "$REPO_ROOT"/install-checks/*.sh
    echo "[*] install-checks ready."
    echo
else
    echo "[*] All required files present."
    echo
fi

# ==============================================================================
# Run Checks
# ==============================================================================

echo "[*] Running system checks..."
echo

bash "$REPO_ROOT/install-checks/file-integrity-check.sh"
bash "$REPO_ROOT/install-checks/secure-boot-check.sh"
bash "$REPO_ROOT/install-checks/pacman-mirrors-check.sh"

# ==============================================================================
# COMPLETE
# ==============================================================================

echo
echo "================================================="
echo "   System checks complete — ready to configure"
echo "================================================="
echo

source "$REPO_ROOT/config/menu.sh" main_menu