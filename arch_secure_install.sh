#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Secure Installer — Single-Script Bootstrap
# ==============================================================================
#  Goals:
#    • Use repo/ if present + valid
#    • Else restore from repo.bundle + minisign signature
#    • Else download from GitHub
#    • Rotate: rename repo/ → repo.old/, install fresh repo/
#    • Launch install_engine.sh from repo/
# ==============================================================================

# ------------------------------------------------------------------------------
# Check for root
# ------------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    printf "\n[FATAL] Must be run as root.\n"
    printf "        sudo bash arch_secure_install.sh\n\n"
    exit 1
fi

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

REPO_URL="https://github.com/WillemAchterhof/arch-luks-tpm-secureboot.git"
PINNED_COMMIT="skip"  # TODO: replace with real 40-char SHA when ready

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/repo"

BUNDLE_FILE="$SCRIPT_DIR/repo.bundle"
BUNDLE_SIG="$SCRIPT_DIR/repo.bundle.minisig"
MINISIGN_PUBKEY_FILE="$SCRIPT_DIR/minisign.pub"

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

msg()   { printf "\n[*] %s\n\n" "$1"; }
fatal() { printf "\n[FATAL] %s\n\n" "$1"; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fatal "Required command '$1' not found."
}

internet_ok() {
    curl -s --fail --max-time 5 https://archlinux.org/mirrorlist/ -o /dev/null \
        || curl -s --fail --max-time 5 https://google.com -o /dev/null \
        || ping -c1 -W2 1.1.1.1 >/dev/null 2>&1
}

validate_pinned_commit() {
    [[ "$PINNED_COMMIT" == "skip" ]] && return 0
    [[ "$PINNED_COMMIT" =~ ^[0-9a-f]{40}$ ]] \
        || fatal "PINNED_COMMIT is not a valid 40-char SHA-1 hash."
}

ensure_git() {
    if ! command -v git &>/dev/null; then
        msg "git not found — installing..."
        pacman -Sy --noconfirm git \
            || fatal "Failed to install git."
    fi
}

# ------------------------------------------------------------------------------
# Repo Verification
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

verify_repo_checksums() {
    [[ -f "$REPO_DIR/checksums.sha256" ]] || return 0
    (cd "$REPO_DIR" && sha256sum -c checksums.sha256 --quiet)
}

verify_repo_commit() {
    [[ "$PINNED_COMMIT" == "skip" ]] && return 0
    [[ -d "$REPO_DIR/.git" ]] || return 1

    local repo_commit
    repo_commit="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)" || return 1

    [[ "$repo_commit" == "$PINNED_COMMIT" ]] || {
        echo "  Repo commit mismatch:"
        echo "    expected: $PINNED_COMMIT"
        echo "    got:      $repo_commit"
        return 1
    }

    return 0
}

verify_repo() {
    verify_repo_structure || return 1
    verify_repo_checksums || return 1
    return 0
}

# ------------------------------------------------------------------------------
# Rotation: repo/ → repo.old/, fresh clone → repo/
# ------------------------------------------------------------------------------

rotate_repo() {
    # Remove previous backup if exists
    [[ -d "$SCRIPT_DIR/repo.old" ]] && rm -rf "$SCRIPT_DIR/repo.old"

    # Rename current repo to repo.old
    [[ -d "$REPO_DIR" ]] && mv "$REPO_DIR" "$SCRIPT_DIR/repo.old"

    # Copy fresh clone into repo/
    # Using cp -a instead of rsync — rsync is not available on the Arch ISO
    cp -a "$TEMP_DIR/repo/." "$REPO_DIR/" \
        || fatal "cp failed during repo install."

    # Verify install_engine.sh landed correctly
    [[ -f "$REPO_DIR/install_engine.sh" ]] \
        || fatal "install_engine.sh missing after install."

    # Remove backup — all good
    rm -rf "$SCRIPT_DIR/repo.old"

    msg "Repo installed."
}

# ------------------------------------------------------------------------------
# Install From Bundle (Minisign Verified)
# ------------------------------------------------------------------------------

install_from_bundle() {
    msg "Restoring repo from minisign-verified bundle"

    need_cmd minisign
    ensure_git

    [[ -f "$BUNDLE_FILE" ]] || fatal "repo.bundle missing."
    [[ -f "$BUNDLE_SIG"  ]] || fatal "repo.bundle.minisig missing."
    [[ -f "$MINISIGN_PUBKEY_FILE" ]] || fatal "minisign.pub missing."

    minisign -Vm "$BUNDLE_FILE" \
             -x "$BUNDLE_SIG" \
             -p "$MINISIGN_PUBKEY_FILE" \
             || fatal "Minisign verification FAILED."

    TEMP_DIR="$(mktemp -d)"

    git clone "$BUNDLE_FILE" "$TEMP_DIR/repo" \
        || fatal "Bundle clone failed."

    if [[ "$PINNED_COMMIT" != "skip" ]]; then
        local cl_commit
        cl_commit="$(git -C "$TEMP_DIR/repo" rev-parse HEAD)"
        [[ "$cl_commit" == "$PINNED_COMMIT" ]] \
            || fatal "Bundle commit mismatch:
expected: $PINNED_COMMIT
got:      $cl_commit"
    fi

    rotate_repo
}

# ------------------------------------------------------------------------------
# Download From GitHub
# ------------------------------------------------------------------------------

download_repo() {
    msg "Fetching repo from GitHub..."

    ensure_git
    internet_ok || fatal "No internet available for GitHub fetch."

    TEMP_DIR="$(mktemp -d)"

    if [[ "$PINNED_COMMIT" == "skip" ]]; then
        git clone "$REPO_URL" "$TEMP_DIR" \
            || fatal "git clone failed."
    else
        git clone --no-checkout "$REPO_URL" "$TEMP_DIR" \
            || fatal "git clone failed."

        git -C "$TEMP_DIR" fetch --depth 1 origin "$PINNED_COMMIT" \
            || fatal "Pinned commit not found in remote."

        git -C "$TEMP_DIR" checkout "$PINNED_COMMIT" \
            || fatal "Could not checkout pinned commit."
    fi

    rotate_repo
}

# ------------------------------------------------------------------------------
# Restore Output Folder (postboot resume)
# ------------------------------------------------------------------------------

# On first boot after install, the USB is not mounted.
# The installer was copied to ~/installer/ before reboot.
# If we're running from ~/installer/, restore the output/ folder
# so STATE_FOLDER and PROFILE_FOLDER resolve correctly.

restore_output_if_needed() {
    local saved_output="$SCRIPT_DIR/output"
    local repo_output="$REPO_DIR/output"

    # Only restore if output/ is next to this script but not next to repo/
    # This handles the postboot case where everything lives in ~/installer/
    if [[ -d "$saved_output" && ! -d "$repo_output" ]]; then
        msg "Restoring output/ from installer directory..."
        cp -a "$saved_output" "$repo_output"
        msg "output/ restored."
    fi
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------

msg "Arch Secure Installer — Bootstrap"
validate_pinned_commit

if ! internet_ok; then
    cat <<EOF

[FATAL] No internet detected.

A working internet connection is required to download Arch packages (pacstrap)
and complete the installation.

Use iwctl to connect your Wi-Fi:

    iwctl device list
    iwctl station <adapter> scan
    iwctl station <adapter> get-networks
    iwctl station <adapter> connect <SSID>

Then re-run: bash arch_secure_install.sh

EOF
    exit 1
fi

if [[ -d "$REPO_DIR" ]]; then
    msg "Existing repo found — verifying..."

    if verify_repo && verify_repo_commit; then
        msg "Repo OK."
    else
        msg "Repo invalid — reinstalling..."

        if [[ -f "$BUNDLE_FILE" && -f "$BUNDLE_SIG" ]]; then
            install_from_bundle
        else
            msg "No bundle — fetching from GitHub..."
            download_repo
        fi

        verify_repo        || fatal "Repo invalid after reinstall."
        verify_repo_commit || fatal "Commit mismatch after reinstall."
    fi

else
    msg "Repo missing — installing..."

    if [[ -f "$BUNDLE_FILE" && -f "$BUNDLE_SIG" ]]; then
        install_from_bundle
    else
        msg "No bundle — fetching from GitHub..."
        download_repo
    fi

    verify_repo        || fatal "Repo invalid after install."
    verify_repo_commit || fatal "Commit mismatch after install."
fi

# Restore output/ next to repo/ if needed (postboot resume from ~/installer/)
restore_output_if_needed

# ------------------------------------------------------------------------------
# Hand Off
# ------------------------------------------------------------------------------

find "$REPO_DIR" -name "*.sh" -exec chmod 750 {} \;

msg "Bootstrap complete — launching installer..."
exec "$REPO_DIR/install_engine.sh"