#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Secure Installer — Engine
# ==============================================================================
#  Responsibilities:
#    • Drive the installation state machine
#    • Interactively gather settings
#    • Confirm destructive actions
#    • Execute installation phases in correct order
#    • Resume after reboot (e.g. Secure Boot setup-mode)
#
#  NOTE:
#    arch_secure_install.sh guarantees:
#      - repo integrity
#      - signature verification
#      - pinned-commit correctness
#      - all install scripts present
#      - internet connectivity
# ==============================================================================

export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$REPO_ROOT/install/lib/bootstrap.sh"

# All folders come from file_paths.sh (loaded by bootstrap)
mkdir -p "$LOG_FOLDER" "$STATE_FOLDER" "$SB_ROOT" "$PROFILE_FOLDER"

ensure_uefi
load_state

log "=== Arch Secure Installer Engine Starting ==="


# ==============================================================================
# UI HELPERS
# ==============================================================================

confirm_exact() {
    local expected="$1" input
    read -rp "> " input
    [[ "$input" == "$expected" ]]
}

render_profile_summary() {
    clear
    echo "================================================="
    echo "        Loaded Profile: ${INSTALL_PROFILE:-<none>}"
    echo "================================================="
    echo
    printf "  [1] Disk:           %s\n" "${TARGET_DISK:-<unset>}"
    printf "  [2] Hostname:       %s\n" "${HOSTNAME:-<unset>}"
    printf "  [3] Username:       %s\n" "${USERNAME:-<unset>}"
    printf "  [4] Shell:          %s\n" "${USER_SHELL:-<unset>}"
    printf "  [5] SecureBoot:     %s\n" "${SB_MODE:-<unset>}"
    printf "  [6] TPM:            %s\n" "${TPM_MODE:-<unset>}"
    printf "  [7] Encryption:     %s\n" "${ENCRYPTION_MODE:-<unset>}"
    printf "  [8] Desktop:        %s\n" "${DESKTOP_ENV:-<unset>}"
    printf "  [9] File Manager:   %s\n" "${FILE_MANAGER:-<unset>}"
    printf "  [0] Extra Packages: %s\n" "${EXTRA_PACKAGES:-<none>}"
    echo
    echo "-----------------------------------------------"
    echo "  Press ENTER to continue"
    echo "  Press E to edit settings"
    echo "  Press Q to abort"
    echo
}


# ==============================================================================
# MODE SELECTION (non-recursive)
# ==============================================================================

select_mode() {
    while true; do
        clear
        echo "================================================="
        echo "            Arch Secure Installer"
        echo "================================================="
        echo
        echo "  Select mode:"
        echo "    1) Full Interactive Setup"
        echo "    2) Load Default Profile (Willem)"
        echo "    3) Abort"
        echo
        read -rp "  Choice: " choice

        case "${choice:-}" in
            1)
                INSTALL_MODE="interactive"
                INSTALL_PROFILE="interactive"
                return
                ;;
            2)
                INSTALL_MODE="profile"
                source "$PROFILES_DIR/default.conf"
                INSTALL_PROFILE="willem"
                return
                ;;
            3)
                fatal "User aborted."
                ;;
            *)
                log "[!] Invalid selection — try again."
                ;;
        esac
    done
}


# ==============================================================================
# CONFIRMATIONS
# ==============================================================================

confirm_disk_destruction() {
    clear
    echo "================================================="
    echo "                   WARNING"
    echo "================================================="
    echo
    echo "  ALL DATA on:"
    echo
    echo "      ${TARGET_DISK}"
    echo
    echo "  WILL BE PERMANENTLY ERASED."
    echo
    echo "  Type the exact device to continue:"
    echo

    confirm_exact "$TARGET_DISK" || fatal "Disk confirmation failed."
}

confirm_secureboot_enroll() {
    [[ "${SB_MODE:-}" != "custom" ]] && return 0

    clear
    echo "================================================="
    echo "            SECURE BOOT — CUSTOM MODE"
    echo "================================================="
    echo
    echo "  This will:"
    echo "    - Delete all PK/KEK/DB keys"
    echo "    - Remove Microsoft keys"
    echo "    - Require UEFI Setup Mode"
    echo
    echo "  Ty#!/usr/bin/env bash
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
exec "$INSTALL_ROOT/install_engine.sh"pe ENROLL to continue:"
    echo

    confirm_exact "ENROLL" || fatal "Secure Boot enrollment aborted."
}


# ==============================================================================
# STATE MACHINE
# ==============================================================================

run_installation() {

    case "$STATE" in

        init)
            select_mode
            STATE="secureboot"
            save_state
            ;;

        secureboot)
            batch "$INSTALL_ROOT/secure_boot.sh"

            [[ -f "$SB_CHOICE_FILE" ]] || fatal "Secure Boot choice file missing"
            source "$SB_CHOICE_FILE"

            [[ -n "${SB_MODE:-}" ]] || fatal "SB_MODE not set"
            export SB_MODE

            STATE="diskdetect"
            save_state
            ;;

        diskdetect)
            batch "$DISK_FOLDER/get_disks.sh"

            [[ -n "${TARGET_DISK:-}" ]] || fatal "TARGET_DISK missing from get_disks.sh"
            export TARGET_DISK

            STATE="profile"
            save_state
            ;;

        profile)
            if [[ "$INSTALL_MODE" == "profile" ]]; then
                log "[*] Loaded profile: $INSTALL_PROFILE"
            else
                batch "$INSTALL_ROOT/edit_profile.sh"
            fi

            STATE="summary"
            save_state
            ;;

        summary)
            render_profile_summary
            read -r input || true

            case "${input:-}" in
                E|e)
                    batch "$INSTALL_ROOT/edit_profile.sh"
                    ;;
                Q|q)
                    fatal "User aborted."
                    ;;
                *)
                    STATE="confirm"
                    save_state
                    ;;
            esac
            ;;

        confirm)
            confirm_disk_destruction
            confirm_secureboot_enroll
            STATE="execute"
            save_state
            ;;

        execute)
            batch "$INSTALL_ROOT/precheck.sh"
            batch "$INSTALL_ROOT/pacman_mirrors.sh"
            batch "$DISK_FOLDER/disk_setup.sh"
            batch "$INSTALL_ROOT/system.sh"
            batch "$INSTALL_ROOT/boot_loader.sh"
            batch "$INSTALL_ROOT/secureboot_enroll.sh"

            STATE="done"
            save_state
            ;;

        done)
            clear
            echo "================================================="
            echo "              Installation Complete!"
            echo "================================================="
            log "=== Installation complete ==="
            ;;

        *)
            fatal "Unknown state: $STATE"
            ;;
    esac
}


# ==============================================================================
# MAIN LOOP (state-driven, not infinite)
# ==============================================================================

while [[ "$STATE" != "done" ]]; do
    run_installation
done