#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Linux Secure Install - secure-boot.sh
# ==============================================================================

SECUREBOOT_CHOICE_FILE="/tmp/secureboot-choice"
LOG_FILE="/tmp/secureboot.log"
INSTALLATION_ABORTED=false
VERBOSE=true

: "${REPO_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO_ROOT/install/lib/common.sh"

# CLEANUP / EXIT HANDLER -----------------------------------------------

cleanup() {
    log "[*] Cleaning up before exit..."
    if [[ "${INSTALLATION_ABORTED:-false}" == "true" ]]; then
        rm -f "$SECUREBOOT_CHOICE_FILE"
    fi
}
trap cleanup EXIT INT TERM

# DETECT SECURE BOOT STATE ---------------------------------------------

detect_secureboot() {
    local SB_FILE="" SM_FILE="" value
    SB_ENABLED=false
    SB_SETUP_MODE=false

    for f in /sys/firmware/efi/efivars/SecureBoot-*; do
        [[ -e "$f" ]] && SB_FILE="$f" && break
    done

    if [[ -n "$SB_FILE" ]]; then
        value=$(tail -c +5 "$SB_FILE" | hexdump -v -e '1/1 "%d"' | tr -d '\n')
        [[ "$value" == "1" ]] && SB_ENABLED=true
    fi

    for f in /sys/firmware/efi/efivars/SetupMode-*; do
        [[ -e "$f" ]] && SM_FILE="$f" && break
    done

    if [[ -n "$SM_FILE" ]]; then
        value=$(tail -c +5 "$SM_FILE" | hexdump -v -e '1/1 "%d"' | tr -d '\n')
        [[ "$value" == "1" ]] && SB_SETUP_MODE=true
    fi

    log "Secure Boot:  $([[ "$SB_ENABLED" == true ]] && echo "enabled" || echo "disabled")"
    log "Setup Mode:   $([[ "$SB_SETUP_MODE" == true ]] && echo "yes ✓" || echo "no")"
}

# PRESENT OPTIONS ------------------------------------------------------

present_options() {
    echo
    echo "================================================="
    echo "   Secure Boot Setup"
    echo "================================================="
    echo
    echo "  This installer enforces:"
    echo "    - LUKS2 full disk encryption"
    echo "    - TPM2 auto-unlock bound to Secure Boot state"
    echo "    - Unified Kernel Image (UKI) signing"
    echo
    echo "  Choose how Secure Boot keys are enrolled:"
    echo
    echo "  [1] Microsoft certificates  (easier)"
    echo "      Uses existing firmware Microsoft keys"
    echo "      Secure Boot stays enabled — no reboot needed"
    echo
    echo "  [2] Custom keys  (recommended)"
    echo "      Generates your own PK/KEK/DB"
    echo "      Only your signed kernels will boot"
    echo "      Requires UEFI Setup Mode"

    if [[ "$SB_SETUP_MODE" == false ]]; then
        echo
        echo "      ⚠  Firmware is NOT in Setup Mode"
        echo "         You must clear existing Secure Boot keys"
    fi

    echo
    echo "  [q] Abort installation"
    echo
}

# SELECTION LOOP -------------------------------------------------------

select_secureboot_mode() {
    while true; do
        read -rp "  Select [1]: " SB_CHOICE
        SB_CHOICE="${SB_CHOICE:-1}"
        echo

        case "$SB_CHOICE" in
            1)
                log "[*] Selected: Microsoft certificates"
                echo "SECUREBOOT_MODE=microsoft" > "$SECUREBOOT_CHOICE_FILE"
                chmod 600 "$SECUREBOOT_CHOICE_FILE"
                break
                ;;
            2)
                if [[ "$SB_SETUP_MODE" == true ]]; then
                    log "[*] Selected: Custom keys (Setup Mode confirmed)"
                    echo "SECUREBOOT_MODE=custom" > "$SECUREBOOT_CHOICE_FILE"
                    chmod 600 "$SECUREBOOT_CHOICE_FILE"
                    break
                else
                    clear
                    echo
                    echo "================================================="
                    echo "   Custom Keys — UEFI Setup Mode Required"
                    echo "================================================="
                    echo
                    echo "  To enroll custom keys:"
                    echo "    1. Enter UEFI firmware settings"
                    echo "    2. Delete all Secure Boot keys"
                    echo "       (or 'Reset to Setup Mode')"
                    echo "    3. Save and reboot back into Arch ISO"
                    echo
                    echo "  [1] Reboot to UEFI firmware now"
                    echo "  [2] Use Microsoft certificates instead"
                    echo "  [q] Abort installation"
                    echo

                    read -rp "  Select [1]: " REBOOT_CHOICE
                    REBOOT_CHOICE="${REBOOT_CHOICE:-1}"

                    case "$REBOOT_CHOICE" in
                        1)
                            log "[*] Saving custom preference and rebooting to firmware..."
                            echo "SECUREBOOT_MODE=custom" > "$SECUREBOOT_CHOICE_FILE"
                            chmod 600 "$SECUREBOOT_CHOICE_FILE"
                            sleep 2
                            systemctl reboot --firmware-setup
                            ;;
                        2)
                            log "[*] Switching to Microsoft certificates"
                            echo "SECUREBOOT_MODE=microsoft" > "$SECUREBOOT_CHOICE_FILE"
                            chmod 600 "$SECUREBOOT_CHOICE_FILE"
                            break 2
                            ;;
                        q|Q)
                            INSTALLATION_ABORTED=true
                            log "[!] Installation aborted."
                            exit 1
                            ;;
                        *)
                            log "[!] Invalid option."
                            sleep 1
                            ;;
                    esac
                fi
                ;;
            q|Q)
                INSTALLATION_ABORTED=true
                log "[!] Installation aborted."
                exit 1
                ;;
            *)
                log "[!] Invalid option."
                sleep 1
                ;;
        esac
    done
}

# FINAL CONFIRMATION ---------------------------------------------------

final_confirmation() {
    if [[ ! -f "$SECUREBOOT_CHOICE_FILE" ]]; then
        log "[!] Secure Boot choice file missing."
        exit 1
    fi

    SECUREBOOT_MODE=$(awk -F= '/^SECUREBOOT_MODE=/ {print $2}' "$SECUREBOOT_CHOICE_FILE")

    log ""
    log "================================================="
    log "   Secure Boot choice confirmed"
    log "================================================="
    log ""

    if [[ "$SECUREBOOT_MODE" == "custom" ]]; then
        log "Mode:    Custom keys"
        log "Action:  sbctl will generate and enroll PK/KEK/DB"
    else
        log "Mode:    Microsoft certificates"
        log "Action:  UKI signed using existing firmware keys"
    fi

    log ""
}

# MAIN -----------------------------------------------------------------

ensure_uefi
detect_secureboot
present_options
select_secureboot_mode
final_confirmation