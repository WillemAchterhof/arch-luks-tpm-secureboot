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
    curl -s --head --fail --max-time 3 https://archlinux.org >/dev/null \
      || ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1
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
        echo "  [!] Failed to fetch ${filename} (attempt ${attempt})." >&2
        if [[ $attempt -lt 3 ]]; then
          echo "      Retrying in $(( 2 ** attempt )) seconds..." >&2
          sleep $(( 2 ** attempt ))
        fi
    done

    echo
    echo "[!] Could not fetch ${filename} after 3 attempts." >&2
    echo "    Check your connection and re-run install.sh" >&2
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

    if [[ -f "$REPO_ROOT/install/network-setup.sh" ]]; then
        echo "[*] Launching network setup..."
        bash "$REPO_ROOT/install/network-setup.sh"

        echo "[*] Re-checking internet..."
        if ! has_internet; then
            echo "[!] Still no internet connection. Aborting." >&2
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
    "install/file-integrity-check.sh"
    "install/secure-boot-check.sh"
    "install/pacman-mirrors-check.sh"
)

# ==============================================================================
# Verify files exist locally
# ==============================================================================

echo "[*] Verifying required install checks files..."

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
    echo "[*] Fetching install checks from GitHub..."
    mkdir -p "$REPO_ROOT/install"

    for f in "${CHECK_FILES[@]}"; do
      if [[ ! -f "$REPO_ROOT/$f" ]]; then
          filename=$(basename "$f")
          echo "    Fetching ${filename}..."
          fetch_file "$GITHUB_RAW/$f" "$REPO_ROOT/$f"
      else
          echo "    Already present: $(basename "$f")"
      fi
    done

    shopt -s nullglob
    chmod +x "$REPO_ROOT"/install/*.sh || true
    shopt -u nullglob

    echo "[*] install checks ready."
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

bash "$REPO_ROOT/install/file-integrity-check.sh"
bash "$REPO_ROOT/install/secure-boot-check.sh"
bash "$REPO_ROOT/install/pacman-mirrors-check.sh"

# ==============================================================================
# COMPLETE
# ==============================================================================

echo
echo "================================================="
echo "   System checks complete — ready to configure"
echo "================================================="
echo

# Load menu and invoke main_menu (adjust if menu.sh is an executable script)
if [[ -f "$REPO_ROOT/menu/menu.sh" ]]; then
  # shellcheck source=/dev/null
  source "$REPO_ROOT/menu/menu.sh"
  main_menu
else
  echo "[!] Menu file not found: $REPO_ROOT/menu/menu.sh" >&2
  exit 1
fi
