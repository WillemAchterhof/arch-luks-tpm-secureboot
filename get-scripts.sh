#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Linux Secure Install - get-scripts.sh
#  Downloads or copies all install scripts and configs to /mnt/install/
#  Called by part1-live.sh after /mnt is mounted
#  Requires SCRIPT_BASE to be exported by part1-live.sh
#
#  Verification:
#  - USB path:    files are trusted, no verification needed
#  - GitHub path: SHA256 checksum verified against checksums.sha256
#                 GPG signature verification prepared but not yet enabled
# ==============================================================================

if [[ -z "${SCRIPT_BASE:-}" ]]; then
    echo "[!] SCRIPT_BASE is not set. This script must be called from part1-live.sh"
    exit 1
fi

if [[ ! -d "/mnt/install" ]]; then
    echo "[!] /mnt/install does not exist. Is /mnt mounted?"
    exit 1
fi

# ------------------------------------------------------------------------------
# CREATE DIRECTORY STRUCTURE
# ------------------------------------------------------------------------------

echo "[*] Creating directory structure..."

mkdir -p /mnt/install/configs/system
mkdir -p /mnt/install/configs/shell
mkdir -p /mnt/install/configs/editor
mkdir -p /mnt/install/configs/themes/waybar
mkdir -p /mnt/install/configs/themes/rofi
mkdir -p /mnt/install/configs/themes/alacritty
mkdir -p /mnt/install/configs/themes/hyprland

# ==============================================================================
# USB PATH - Trusted source, copy directly
# ==============================================================================

if [[ "$SCRIPT_BASE" == /* ]]; then
    echo "[*] Copying from USB (trusted source)..."

    cp -r "$SCRIPT_BASE"/install/part*.sh              /mnt/install/
    cp -r "$SCRIPT_BASE"/configs/system/.              /mnt/install/configs/system/
    cp -r "$SCRIPT_BASE"/configs/shell/.               /mnt/install/configs/shell/
    cp -r "$SCRIPT_BASE"/configs/editor/.              /mnt/install/configs/editor/
    cp -r "$SCRIPT_BASE"/configs/themes/waybar/.       /mnt/install/configs/themes/waybar/
    cp -r "$SCRIPT_BASE"/configs/themes/rofi/.         /mnt/install/configs/themes/rofi/
    cp -r "$SCRIPT_BASE"/configs/themes/alacritty/.    /mnt/install/configs/themes/alacritty/
    cp -r "$SCRIPT_BASE"/configs/themes/hyprland/.     /mnt/install/configs/themes/hyprland/

    chmod +x /mnt/install/part*.sh
    echo "[*] Files copied from USB."
    exit 0
fi

# ==============================================================================
# GITHUB PATH - Untrusted source, verify before use
# ==============================================================================

echo "[*] Downloading from GitHub..."

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ------------------------------------------------------------------------------
# DOWNLOAD CHECKSUMS FIRST
# ------------------------------------------------------------------------------

echo "[*] Fetching checksums..."
curl -fsSL "$SCRIPT_BASE/checksums.sha256" -o "$TMPDIR/checksums.sha256"

# ------------------------------------------------------------------------------
# GPG VERIFICATION (prepared - not yet active)
# To enable: uncomment and add your public key to the keyring
# ------------------------------------------------------------------------------

# echo "[*] Fetching GPG signature..."
# curl -fsSL "$SCRIPT_BASE/checksums.sha256.sig" -o "$TMPDIR/checksums.sha256.sig"
#
# echo "[*] Importing GPG public key..."
# gpg --keyserver keyserver.ubuntu.com --recv-keys <YOUR_KEY_ID>
#
# echo "[*] Verifying GPG signature on checksums..."
# gpg --verify "$TMPDIR/checksums.sha256.sig" "$TMPDIR/checksums.sha256" || {
#     echo "[!] GPG signature verification FAILED. Aborting."
#     exit 1
# }
# echo "[*] GPG signature verified."

# ------------------------------------------------------------------------------
# DOWNLOAD ALL FILES
# ------------------------------------------------------------------------------

echo "[*] Downloading scripts..."

# Scripts
curl -fsSL "$SCRIPT_BASE/install/part2-chroot.sh"       -o "$TMPDIR/part2-chroot.sh"
curl -fsSL "$SCRIPT_BASE/install/part3-secureboot.sh"   -o "$TMPDIR/part3-secureboot.sh"
curl -fsSL "$SCRIPT_BASE/install/part4-post-reboot.sh"  -o "$TMPDIR/part4-post-reboot.sh"
curl -fsSL "$SCRIPT_BASE/install/part5-user-setup.sh"   -o "$TMPDIR/part5-user-setup.sh"
curl -fsSL "$SCRIPT_BASE/install/part6-software.sh"     -o "$TMPDIR/part6-software.sh"
curl -fsSL "$SCRIPT_BASE/install/part7-hyprland.sh"     -o "$TMPDIR/part7-hyprland.sh"

echo "[*] Downloading system configs..."

curl -fsSL "$SCRIPT_BASE/configs/system/99-hardening.conf"       -o "$TMPDIR/99-hardening.conf"
curl -fsSL "$SCRIPT_BASE/configs/system/blacklist.conf"           -o "$TMPDIR/blacklist.conf"
curl -fsSL "$SCRIPT_BASE/configs/system/nftables.conf"            -o "$TMPDIR/nftables.conf"
curl -fsSL "$SCRIPT_BASE/configs/system/NetworkManager.conf"      -o "$TMPDIR/NetworkManager.conf"
curl -fsSL "$SCRIPT_BASE/configs/system/zz-sbctl-uki.hook"        -o "$TMPDIR/zz-sbctl-uki.hook"

echo "[*] Downloading shell and editor configs..."

curl -fsSL "$SCRIPT_BASE/configs/shell/.zshrc"                    -o "$TMPDIR/.zshrc"
curl -fsSL "$SCRIPT_BASE/configs/editor/init.lua"                 -o "$TMPDIR/init.lua"

echo "[*] Downloading themes..."

curl -fsSL "$SCRIPT_BASE/configs/themes/waybar/config.jsonc"      -o "$TMPDIR/waybar-config.jsonc"
curl -fsSL "$SCRIPT_BASE/configs/themes/waybar/style.css"         -o "$TMPDIR/waybar-style.css"
curl -fsSL "$SCRIPT_BASE/configs/themes/rofi/config.rasi"         -o "$TMPDIR/rofi-config.rasi"
curl -fsSL "$SCRIPT_BASE/configs/themes/rofi/tokyonight.rasi"     -o "$TMPDIR/rofi-tokyonight.rasi"
curl -fsSL "$SCRIPT_BASE/configs/themes/alacritty/alacritty.toml" -o "$TMPDIR/alacritty.toml"
curl -fsSL "$SCRIPT_BASE/configs/themes/hyprland/hyprland.conf"   -o "$TMPDIR/hyprland.conf"

# ------------------------------------------------------------------------------
# SHA256 VERIFICATION
# ------------------------------------------------------------------------------

echo "[*] Verifying checksums..."

# Build a verification-friendly checksums file pointing to TMPDIR files
# The checksums.sha256 in the repo uses paths relative to repo root,
# so we remap them to the flat TMPDIR layout for verification.

VERIFY_OK=true

while IFS='  ' read -r expected_hash filepath; do
    # Extract just the filename from the repo path
    filename=$(basename "$filepath")

    # Handle waybar/rofi files which were downloaded with prefixed names
    case "$filepath" in
        configs/themes/waybar/config.jsonc)  filename="waybar-config.jsonc" ;;
        configs/themes/waybar/style.css)     filename="waybar-style.css" ;;
        configs/themes/rofi/config.rasi)     filename="rofi-config.rasi" ;;
        configs/themes/rofi/tokyonight.rasi) filename="rofi-tokyonight.rasi" ;;
    esac

    local_file="$TMPDIR/$filename"

    if [[ ! -f "$local_file" ]]; then
        echo "[!] Missing file: $filename (from $filepath)"
        VERIFY_OK=false
        continue
    fi

    actual_hash=$(sha256sum "$local_file" | awk '{print $1}')

    if [[ "$actual_hash" != "$expected_hash" ]]; then
        echo "[!] Checksum MISMATCH: $filename"
        echo "    Expected: $expected_hash"
        echo "    Got:      $actual_hash"
        VERIFY_OK=false
    else
        echo "    OK: $filename"
    fi

done < "$TMPDIR/checksums.sha256"

if [[ "$VERIFY_OK" != "true" ]]; then
    echo
    echo "[!] Checksum verification FAILED. Files may be tampered or corrupted."
    echo "[!] Aborting installation."
    exit 1
fi

echo "[*] All checksums verified."

# ------------------------------------------------------------------------------
# MOVE VERIFIED FILES TO /mnt/install
# ------------------------------------------------------------------------------

echo "[*] Installing verified files..."

# Scripts
cp "$TMPDIR/part2-chroot.sh"      /mnt/install/part2-chroot.sh
cp "$TMPDIR/part3-secureboot.sh"  /mnt/install/part3-secureboot.sh
cp "$TMPDIR/part4-post-reboot.sh" /mnt/install/part4-post-reboot.sh
cp "$TMPDIR/part5-user-setup.sh"  /mnt/install/part5-user-setup.sh
cp "$TMPDIR/part6-software.sh"    /mnt/install/part6-software.sh
cp "$TMPDIR/part7-hyprland.sh"    /mnt/install/part7-hyprland.sh

# System configs
cp "$TMPDIR/99-hardening.conf"    /mnt/install/configs/system/99-hardening.conf
cp "$TMPDIR/blacklist.conf"       /mnt/install/configs/system/blacklist.conf
cp "$TMPDIR/nftables.conf"        /mnt/install/configs/system/nftables.conf
cp "$TMPDIR/NetworkManager.conf"  /mnt/install/configs/system/NetworkManager.conf
cp "$TMPDIR/zz-sbctl-uki.hook"    /mnt/install/configs/system/zz-sbctl-uki.hook

# Shell and editor
cp "$TMPDIR/.zshrc"               /mnt/install/configs/shell/.zshrc
cp "$TMPDIR/init.lua"             /mnt/install/configs/editor/init.lua

# Themes
cp "$TMPDIR/waybar-config.jsonc"  /mnt/install/configs/themes/waybar/config.jsonc
cp "$TMPDIR/waybar-style.css"     /mnt/install/configs/themes/waybar/style.css
cp "$TMPDIR/rofi-config.rasi"     /mnt/install/configs/themes/rofi/config.rasi
cp "$TMPDIR/rofi-tokyonight.rasi" /mnt/install/configs/themes/rofi/tokyonight.rasi
cp "$TMPDIR/alacritty.toml"       /mnt/install/configs/themes/alacritty/alacritty.toml
cp "$TMPDIR/hyprland.conf"        /mnt/install/configs/themes/hyprland/hyprland.conf

chmod +x /mnt/install/part*.sh

echo "[*] All files installed and verified."