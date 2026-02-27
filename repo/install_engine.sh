#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Secure Installer — Engine (Final Refined Version)
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
export INSTALL_FOLDER="$REPO_ROOT/install"
export LIB_DIR="$INSTALL_FOLDER/lib"

# Load framework (log, fatal, batch, state, ensure_uefi)
source "$LIB_DIR/bootstrap.sh"

# OUTPUT_FOLDER, STATE_FILE, LOG_FILE come from file_paths.sh (inside bootstrap)
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
        read -rp "  C-----------------------------------"
    echo "  Press ENTER to continue"
    echo "  Press E to edit settings"
    echo "  Press Q to abort"
    echo
}hoice: " choice

        case "${choice:-}" in
            1)
                INSTALL_MODE="interactive"
                INSTALL_PROFILE="interactive"
                return
                ;;

            2)
                INSTALL_MODE="profile"
                source "$INSTALL_FOLDER/profiles/default.conf"
                INSTALL_PROFILE="willem"
                return
                ;;

            3)
                fatal "User aborted."
                ;;-----------------------------------"
    echo "  Press ENTER to continue"
    echo "  Press E to edit settings"
    echo "  Press Q to abort"
    echo
}

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
    echo "============-----------------------------------"
    echo "  Press ENTER to continue"
    echo "  Press E to edit settings"
    echo "  Press Q to abort"
    echo
}====================================="
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
    echo "============-----------------------------------"
    echo "  Press ENTER to continue"
    echo "  Press E to edit settings"
    echo "  Press Q to abort"
    echo
}====================================="
    echo
    echo "  This will:"
    echo "    - Delete all PK/KEK/DB keys"
    echo "    - Remove Microsoft keys"
    echo "    - Require UEFI Setup Mode"
    echo
    echo "  Type ENROLL to continue:"
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
            batch "$INSTALL_FOLDER/secure_boot.sh"

            # Load variable from secure_boot.sh output
            [[ -f "$SB_CHOICE_FILE" ]] || fatal "Secure Boot choice file missing"
            source "$SB_CHOICE_FILE"
            
            [[ -n "${SB_MODE:-}" ]] || fatal "SB_MODE not set"
            export SB_MODE

            STATE="diskdetect"
            save_state
            ;;

        diskdetect)
            batch "$INSTALL_FOLDER/disk/get_disks.sh"

            [[ -n "${TARGET_DISK:-}" ]] || fatal "TARGET_DISK missing from get_disks.sh"
            export TARGET_DISK

            STATE="profile"
            save_state
            ;;

        profile)
            if [[ "$INSTALL_MODE" == "profile" ]]; then
                log "[*] Loaded profile: $INSTALL_PROFILE"
            else
                batch "$INSTALL_FOLDER/edit_profile.sh"
            fi

            STATE="summary"
            save_state
            ;;

        summary)
            render_profile_summary
            read -r input || true

            case "${input:-}" in
                E|e)
                    batch "$INSTALL_FOLDER/edit_profile.sh"
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
            batch "$INSTALL_FOLDER/precheck.sh"
            batch "$INSTALL_FOLDER/pacman_mirrors.sh"
            batch "$INSTALL_FOLDER/disk/setup.sh"
            batch "$INSTALL_FOLDER/system.sh"

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
# MAIN LOOP (state‑driven, not infinite)
# ==============================================================================

while [[ "$STATE" != "done" ]]; do
    run_installation
done