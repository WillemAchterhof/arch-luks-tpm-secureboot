#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — secure_boot.sh
#  Detects Secure Boot state, prompts for enrollment mode
#  Writes SB_MODE to $SB_CHOICE_FILE
# ==============================================================================

: "${STATE_FOLDER:?STATE_FOLDER not set}"
: "${SB_ROOT:?SB_ROOT not set}"
: "${SB_CHOICE_FILE:?SB_CHOICE_FILE not set}"

INSTALLATION_ABORTED=false

# ==============================================================================
# CLEANUP
# ==============================================================================

cleanup() {
    if [[ "${INSTALLATION_ABORTED:-false}" == "true" ]]; then
        rm -f "$SB_CHOICE_FILE"
    fi
}
trap cleanup EXIT INT TERM

# ==============================================================================
# DETECT SECURE BOOT STATE
# ==============================================================================

detect_secureboot() {
    local SB_FILE="" SM_FILE="" value
    SB_ENABLED=false
    SB_SETUP_MODE=false

    for f in /sys/firmware/efi/efivars/SecureBoot-*; do
        [[ -e "$f" ]] && SB_FILE="$f" && break
    done

    if [[ -n "$SB_FILE" ]]; then
        value=$(tail -c +5 "$SB_FILE" | hexdump -v -e '1/1 "%d"' | tr -d '\n[:space:]')
        [[ "$value" == "1" ]] && SB_ENABLED=true
    fi

    for f in /sys/firmware/efi/efivars/SetupMode-*; do
        [[ -e "$f" ]] && SM_FILE="$f" && break
    done

    if [[ -n "$SM_FILE" ]]; then
        value=$(tail -c +5 "$SM_FILE" | hexdump -v -e '1/1 "%d"' | tr -d '\n[:space:]')
        [[ "$value" == "1" ]] && SB_SETUP_MODE=true
    fi

    log "Secure Boot:  $([[ "$SB_ENABLED" == true ]] && echo "enabled" || echo "disabled")"
    log "Setup Mode:   $([[ "$SB_SETUP_MODE" == true ]] && echo "yes ✓" || echo "no")"
}

# ==============================================================================
# WRITE CHOICE
# ==============================================================================

write_choice() {
    local mode="$1"
    printf 'SB_MODE=%s\n' "$mode" > "$SB_CHOICE_FILE"
    chmod 600 "$SB_CHOICE_FILE"
    log "[*] Secure Boot mode saved: $mode"
    export SB_MODE="$mode"
}

# ==============================================================================
# PRESENT OPTIONS
# ==============================================================================

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

# ==============================================================================
# SELECTION LOOP
# ==============================================================================

select_secureboot_mode() {
    local SB_CHOICE REBOOT_CHOICE

    while true; do
        read -rp "  Select [1]: " SB_CHOICE
        SB_CHOICE="${SB_CHOICE:-1}"
        echo

        case "$SB_CHOICE" in
            1)
                write_choice "microsoft"
                break
                ;;
            2)
                if [[ "$SB_SETUP_MODE" == true ]]; then
                    write_choice "custom"
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
                            write_choice "custom"
                            log "[*] Rebooting to UEFI firmware..."
                            sleep 2
                            systemctl reboot --firmware-setup
                            exit 0
                            ;;
                        2)
                            write_choice "microsoft"
                            break 2
                            ;;
                        q|Q)
                            INSTALLATION_ABORTED=true
                            fatal "Installation aborted."
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
                fatal "Installation aborted."
                ;;
            *)
                log "[!] Invalid option."
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# FINAL CONFIRMATION
# ==============================================================================

final_confirmation() {
    [[ -f "$SB_CHOICE_FILE" ]] \
        || fatal "Secure Boot choice file missing after selection."

    source "$SB_CHOICE_FILE"

    [[ -n "${SB_MODE:-}" ]] \
        || fatal "SB_MODE not set in choice file."

    [[ "$SB_MODE" == "microsoft" || "$SB_MODE" == "custom" ]] \
        || fatal "Invalid SB_MODE value: $SB_MODE"

    log "================================================="
    log "   Secure Boot choice confirmed"
    log "================================================="

    if [[ "$SB_MODE" == "custom" ]]; then
        log "  Mode:    Custom keys"
        log "  Action:  sbctl will generate and enroll PK/KEK/DB"
    else
        log "  Mode:    Microsoft certificates"
        log "  Action:  UKI signed using existing firmware keys"
    fi

    log ""
}

# ==============================================================================
# MAIN
# ==============================================================================

detect_secureboot
present_options
select_secureboot_mode
final_confirmation