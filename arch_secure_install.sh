#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Secure Installer — Single-Script Bootstrap
# ==============================================================================
#  Goals:
#    • Use repo/ if present + valid
#    • Else restore from repo.bundle + minisign signature
#    • Else download pinned commit from GitHub (pinned commit only)
#    • Verify pinned commit ALWAYS (bundle or GitHub)
#    • Atomic install via rsync → .new → rotate
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
PINNED_COMMIT="abcd1234ef567890abcdef1234567890abcdef12"  # TODO: replace with real SHA

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ROOT="$SCRIPT_DIR/repo"

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
    [[ "$PINNED_COMMIT" =~ ^[0-9a-f]{40}$ ]] \
        || fatal "PINNED_COMMIT is not a valid 40-char SHA-1 hash."
}

# ------------------------------------------------------------------------------
# Repo Verification
# ------------------------------------------------------------------------------

verify_repo_structure() {
    local ok=true
    local files=(
        "$INSTALL_ROOT/install_engine.sh"
        "$INSTALL_ROOT/install/lib/bootstrap.sh"
        "$INSTALL_ROOT/install/lib/common.sh"
        "$INSTALL_ROOT/install/lib/file_paths.sh"
    )
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || { echo "  missing: $f"; ok=false; }
    done
    [[ "$ok" == true ]]
}

verify_repo_checksums() {
    [[ -f "$INSTALL_ROOT/checksums.sha256" ]] || return 0
    (cd "$INSTALL_ROOT" && sha256sum -c checksums.sha256 --quiet)
}

verify_repo_commit() {
    [[ -d "$INSTALL_ROOT/.git" ]] || return 1

    local repo_commit
    repo_commit="$(git -C "$INSTALL_ROOT" rev-parse HEAD 2>/dev/null)" || return 1

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
# Atomic Staging + Rotation
# ------------------------------------------------------------------------------

stage_and_rotate_repo() {
    local TMP_NEW="${INSTALL_ROOT}.new"
    local TMP_OLD="${INSTALL_ROOT}.old"

    rm -rf "$TMP_NEW"

    rsync -a --delete "$TEMP_DIR/" "$TMP_NEW/" \
        || fatal "rsync failed during staging."

    [[ -f "$TMP_NEW/install_engine.sh" ]] \
        || fatal "install_engine.sh missing after copy."

    [[ -d "$INSTALL_ROOT" ]] && mv "$INSTALL_ROOT" "$TMP_OLD"
    mv "$TMP_NEW" "$INSTALL_ROOT"

    rm -rf "$TMP_OLD"
}

# ------------------------------------------------------------------------------
# Install From Bundle (Minisign Verified)
# ------------------------------------------------------------------------------

install_from_bundle() {
    msg "Restoring repo from minisign-verified bundle"

    need_cmd minisign
    need_cmd git

    [[ -f "$BUNDLE_FILE" ]] || fatal "repo.bundle missing."
    [[ -f "$BUNDLE_SIG"  ]] || fatal "repo.bundle.minisig missing."
    [[ -f "$MINISIGN_PUBKEY_FILE" ]] || fatal "minisign.pub missing."

    minisign -Vm "$BUNDLE_FILE" \
             -x "$BUNDLE_SIG" \
             -p "$MINISIGN_PUBKEY_FILE" \
             || fatal "Minisign verification FAILED."

    TEMP_DIR="$(mktemp -d)"

    git clone "$BUNDLE_FILE" "$TEMP_DIR" \
        || fatal "Bundle clone failed."

    local cl_commit
    cl_commit="$(git -C "$TEMP_DIR" rev-parse HEAD)"

    [[ "$cl_commit" == "$PINNED_COMMIT" ]] || fatal "Bundle commit mismatch:
expected: $PINNED_COMMIT
got:      $cl_commit"

    stage_and_rotate_repo
}

# ------------------------------------------------------------------------------
# Download From GitHub (Pinned Commit Only)
# ------------------------------------------------------------------------------

download_repo() {
    msg "Fetching repo from GitHub…"

    need_cmd git
    internet_ok || fatal "No internet available for GitHub fetch."

    TEMP_DIR="$(mktemp -d)"

    git clone --no-checkout "$REPO_URL" "$TEMP_DIR" \
        || fatal "git clone failed."

    git -C "$TEMP_DIR" fetch --depth 1 origin "$PINNED_COMMIT" \
        || fatal "Pinned commit not found in remote."

    git -C "$TEMP_DIR" checkout "$PINNED_COMMIT" \
        || fatal "Could not checkout pinned commit."

    git -C "$TEMP_DIR" reset --hard \
        || fatal "Failed to populate working tree."

    stage_and_rotate_repo
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

if [[ -d "$INSTALL_ROOT" ]]; then
    msg "Existing repo found — verifying…"

    if verify_repo && verify_repo_commit; then
        msg "Repo OK."
    else
        msg "Repo corrupted — attempting repair…"

        if [[ -f "$BUNDLE_FILE" && -f "$BUNDLE_SIG" ]]; then
            install_from_bundle
        else
            msg "Bundle missing — falling back to GitHub"
            download_repo
        fi

        verify_repo        || fatal "Repo invalid after repair."
        verify_repo_commit || fatal "Commit mismatch after repair."
    fi

else
    msg "Repo missing — restoring…"

    if [[ -f "$BUNDLE_FILE" && -f "$BUNDLE_SIG" ]]; then
        install_from_bundle
    else
        msg "Bundle missing — requiring internet for GitHub fetch…"
        download_repo
    fi

    verify_repo        || fatal "Repo invalid after restore."
    verify_repo_commit || fatal "Commit mismatch after restore."
fi

# ------------------------------------------------------------------------------
# Hand Off
# ------------------------------------------------------------------------------

find "$INSTALL_ROOT" -name "*.sh" -exec chmod 750 {} \;

msg "Bootstrap complete — launching installer…"
exec "$INSTALL_ROOT/install_engine.sh"