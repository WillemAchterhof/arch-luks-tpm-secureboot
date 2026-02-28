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
#    • Resume after reboot (first boot / postboot)
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
# ENVIRONMENT DETECTION
# ==============================================================================

detect_environment() {
    if [[ -d /run/archiso ]]; then
        INSTALL_ENV="LIVE"
    else
        INSTALL_ENV="INSTALLED"
    fi
    log "[*] Environment detected: $INSTALL_ENV"
}

detect_environment

# Automatic transition after reboot
if [[ "$STATE" == "preboot_done" && "$INSTALL_ENV" == "INSTALLED" ]]; then
    log "[*] Detected first boot after pre-install — transitioning to postboot."
    STATE="postboot"
    save_state
fi


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
# MODE SELECTION
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
            [[ "$INSTALL_ENV" == "LIVE" ]] \
                || fatal "execute state only allowed in LIVE environment"

            batch "$INSTALL_ROOT/precheck.sh"
            batch "$INSTALL_ROOT/pacman_mirrors.sh"
            batch "$DISK_FOLDER/disk_setup.sh"
            batch "$INSTALL_ROOT/system.sh"
            batch "$INSTALL_ROOT/bootloader.sh"
            batch "$INSTALL_ROOT/secureboot_enroll.sh"

            STATE="preboot_done"
            save_state

            clear
            echo "================================================="
            echo "        Pre-Boot Installation Complete"
            echo "================================================="
            echo
            echo "  You may now reboot into your new system."
            echo
            echo "  After reboot, run:"
            echo "      arch_secure_install.sh"
            echo
            exit 0
            ;;

        preboot_done)
            # Waiting for reboot
            log "[*] Waiting for reboot to continue post-boot setup."
            exit 0
            ;;

        postboot)
            [[ "$INSTALL_ENV" == "INSTALLED" ]] \
                || fatal "postboot state only allowed after reboot into installed system"

            batch "$INSTALL_ROOT/tpm.sh"
            batch "$INSTALL_ROOT/desktop.sh"

            STATE="done"
            save_state
            ;;

        done)
            clear
            echo "================================================="
            echo "          Installation Fully Complete"
            echo "================================================="
            log "=== Installation fully complete ==="
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
