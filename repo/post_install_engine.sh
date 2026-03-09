#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Secure Installer — Post-Install Engine
# ==============================================================================
#  Runs on first boot after pre-boot install.
#  Handles: TPM enrollment, desktop setup.
# ==============================================================================

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------

PROFILE_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)   PROFILE_FILE="$2"; shift 2 ;;
        # Legacy args accepted but ignored — paths derived from USB_ROOT
        --state-dir) shift 2 ;;
        --log-dir)   shift 2 ;;
        *) echo "[FATAL] Unknown argument: $1"; exit 1 ;;
    esac
done

# ------------------------------------------------------------------------------
# Bootstrap lib from repo
# ------------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$REPO_ROOT/install/lib/bootstrap.sh"

# REPO_ROOT = ~/installer/repo/repo
# USB_ROOT  = ~/installer (three levels up)
# file_paths.sh builds OUTPUT_FOLDER = ~/installer/output ✓
export USB_ROOT="$(cd "$REPO_ROOT/../../.." && pwd)"
export OUTPUT_FOLDER="$USB_ROOT/output"
export LOG_FOLDER="$OUTPUT_FOLDER/log"
export STATE_FOLDER="$OUTPUT_FOLDER/state"
export PROFILE_FOLDER="$OUTPUT_FOLDER/profile"

# Create dirs now that paths are correct
mkdir -p "$LOG_FOLDER" "$STATE_FOLDER" "$PROFILE_FOLDER"

# Hardcode state to postboot — this engine only ever runs post-boot.
# Avoids load_state path resolution issues entirely.
STATE="postboot"

INSTALL_MODE="${INSTALL_MODE:-}"
INSTALL_PROFILE="${INSTALL_PROFILE:-}"

# Active profile path for save/resume
ACTIVE_PROFILE="$STATE_FOLDER/active.sh"
[[ -f "$ACTIVE_PROFILE" ]] && source "$ACTIVE_PROFILE"

# ==============================================================================
# ENVIRONMENT CHECK
# ==============================================================================

if [[ -d /run/archiso ]]; then
    fatal "post_install_engine.sh must not run in the live ISO environment."
fi

log "[*] Post-install engine started. State: $STATE"
log "[*] USB_ROOT: $USB_ROOT"
log "[*] STATE_FOLDER: $STATE_FOLDER"
log "[*] LOG_FOLDER: $LOG_FOLDER"

# ==============================================================================
# PROFILE LOADING
# ==============================================================================

load_profile() {
    if [[ -n "$PROFILE_FILE" && -f "$PROFILE_FILE" ]]; then
        log "[*] Loading post profile: $PROFILE_FILE"
        source "$PROFILE_FILE"
        INSTALL_MODE="profile"
        INSTALL_PROFILE="post_default"

        clear
        echo "================================================="
        echo "        Arch Secure — Post-Boot Setup"
        echo "================================================="
        echo
        echo "  Profile loaded — running fully automatic."
        echo
        printf "  Username:    %s\n" "${USERNAME:-<unset>}"
        printf "  Shell:       %s\n" "${USER_SHELL:-<unset>}"
        printf "  Desktop:     %s\n" "${DESKTOP_ENV:-<unset>}"
        printf "  Packages:    %s\n" "${EXTRA_PACKAGES:-<none>}"
        printf "  TPM PCRs:    %s\n" "${TPM_PCRS:-0+7+11}"
        echo
        echo "  Starting in 5 seconds... (Ctrl+C to abort)"
        sleep 5
    else
        select_mode
    fi
}

save_profile() {
    declare -p \
        USERNAME \
        USER_SHELL \
        DESKTOP_ENV \
        EXTRA_PACKAGES \
        TPM_PCRS \
        INSTALL_MODE \
        INSTALL_PROFILE \
        > "$ACTIVE_PROFILE" 2>/dev/null || true
    log "[*] Profile saved."
}

# ==============================================================================
# INTERACTIVE MODE SELECTION
# ==============================================================================

select_mode() {
    while true; do
        clear
        echo "================================================="
        echo "        Arch Secure — Post-Boot Setup"
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
# STATE MACHINE
# ==============================================================================

run_postinstall() {

    case "$STATE" in

        postboot)
            load_profile
            save_profile

            log "[*] Running TPM enrollment..."
            batch "$INSTALL_ROOT/tpm.sh"

            log "[*] Running desktop setup..."
            batch "$INSTALL_ROOT/desktop.sh"

            STATE="done"
            save_state
            ;;

        done)
            # Remove postboot autostart from .bash_profile
            bash_profile="/home/${USERNAME:-}/.bash_profile"
            if [[ -n "${USERNAME:-}" && -f "$bash_profile" ]]; then
                sed -i '/# ARCH_POSTBOOT_START/,/# ARCH_POSTBOOT_END/d' "$bash_profile"
                log "[*] Postboot autostart removed from .bash_profile"
            fi

            # Remove arch_secure_post.sh from home
            post_script="/home/${USERNAME:-}/arch_secure_post.sh"
            [[ -f "$post_script" ]] && rm -f "$post_script"

            # Remove post_default.conf from home
            post_conf="/home/${USERNAME:-}/post_default.conf"
            [[ -f "$post_conf" ]] && rm -f "$post_conf"

            # Remove ~/installer/
            installer_dir="/home/${USERNAME:-}/installer"
            [[ -d "$installer_dir" ]] && rm -rf "$installer_dir"

            clear
            echo "================================================="
            echo "          Installation Fully Complete"
            echo "================================================="
            log "=== Installation fully complete ==="
            ;;

        *)
            fatal "Unexpected state in post_install_engine: $STATE"
            ;;
    esac
}

# ==============================================================================
# MAIN LOOP
# ==============================================================================

while [[ "$STATE" != "done" ]]; do
    run_postinstall
done