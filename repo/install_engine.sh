#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Secure Installer — Engine
# ==============================================================================

export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_ROOT/install/lib/bootstrap.sh"

mkdir -p "$LOG_FOLDER" "$STATE_FOLDER" "$SB_ROOT" "$PROFILE_FOLDER"

ensure_uefi
load_state

# Reload saved profile if resuming
ACTIVE_PROFILE="$PROFILE_FOLDER/active.sh"
[[ -f "$ACTIVE_PROFILE" ]] && source "$ACTIVE_PROFILE"

# Initialise optional profile variables to avoid unbound variable errors
INSTALL_MODE="${INSTALL_MODE:-}"
INSTALL_PROFILE="${INSTALL_PROFILE:-}"

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


# ==============================================================================
# PROFILE PERSISTENCE
# ==============================================================================

save_profile() {
    declare -p \
        INSTALL_HOSTNAME \
        USERNAME \
        USER_SHELL \
        TIMEZONE \
        USER_GROUPS \
        TARGET_DISK \
        DISK_WIPE_MODE \
        ROOT_FS \
        EFI_SIZE \
        SB_MODE \
        MIRROR_COUNTRIES \
        PACMAN_PARALLEL_CHROOT \
        DESKTOP_ENV \
        EXTRA_PACKAGES \
        INSTALL_MODE \
        INSTALL_PROFILE \
        > "$ACTIVE_PROFILE" 2>/dev/null || true
    log "[*] Profile saved to $ACTIVE_PROFILE"
}


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
    printf "  [1]  Hostname:        %s\n" "${INSTALL_HOSTNAME:-<unset>}"
    printf "  [2]  Username:        %s\n" "${USERNAME:-<unset>}"
    printf "  [3]  Shell:           %s\n" "${USER_SHELL:-<unset>}"
    printf "  [4]  Timezone:        %s\n" "${TIMEZONE:-<unset>}"
    printf "  [5]  SecureBoot:      %s\n" "${SB_MODE:-<unset>}"
    printf "  [6]  Target Disk:     %s\n" "${TARGET_DISK:-<unset>}"
    printf "  [7]  Filesystem:      %s\n" "${ROOT_FS:-<unset>}"
    printf "  [8]  Desktop:         %s\n" "${DESKTOP_ENV:-<unset>}"
    printf "  [9]  Extra Packages:  %s\n" "${EXTRA_PACKAGES:-<none>}"
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
        echo "  Inspired by and grateful to:"
        echo "    - JaKooLit      https://github.com/JaKooLit/Arch-Hyprland"
        echo "    - Ataraxxia     https://github.com/Ataraxxia/secure-arch"
        echo
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
    echo "  Type the exact device path to continue."
    echo "  Type Q to abort."
    echo

    local input
    read -rp "> " input

    [[ "$input" == "Q" || "$input" == "q" ]] && fatal "User aborted at disk confirmation."
    [[ "$input" == "$TARGET_DISK" ]] || fatal "Disk confirmation failed — aborting."
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
# PRE-REBOOT: SAVE WIFI + CURL POST BOOTSTRAP + AUTOSTART
# ==============================================================================

prepare_postboot() {
    local mnt="/mnt"
    local home="$mnt/home/${USERNAME}"

    log "[*] Preparing post-boot bootstrap..."

    # -- WiFi credentials --
    # Live ISO uses iwd (iwctl), not NetworkManager.
    # Read active SSID and passphrase directly from iwd profile files.
    local wifi_creds="$home/.wifi_creds"
    local active_ssid="" active_pass="" iwd_adapter iwd_psk_file

    # Detect active adapter (first station in connected state)
    iwd_adapter=$(iwctl station list 2>/dev/null \
        | awk '/connected/{print $1}' | head -1) || true

    if [[ -n "$iwd_adapter" ]]; then
        active_ssid=$(iwctl station "$iwd_adapter" show 2>/dev/null \
            | awk '/Connected network/{print $NF}') || true
    fi

    if [[ -n "$active_ssid" ]]; then
        # iwd stores PSK profiles as /var/lib/iwd/<SSID>.psk
        iwd_psk_file="/var/lib/iwd/${active_ssid}.psk"
        if [[ -f "$iwd_psk_file" ]]; then
            active_pass=$(grep '^Passphrase=' "$iwd_psk_file" \
                | cut -d= -f2-) || true
        fi

        {
            echo "SSID=$active_ssid"
            echo "PASSPHRASE=${active_pass:-}"
        } > "$wifi_creds"
        chmod 600 "$wifi_creds"
        log "[*] WiFi credentials saved for: $active_ssid"
    else
        log "[!] No active iwd WiFi connection detected — skipping WiFi save."
    fi

    # -- copy arch_secure_post.sh from repo --
    # Already in the cloned repo — no curl needed
    local post_script="$home/arch_secure_post.sh"

    [[ -f "$REPO_ROOT/arch_secure_post.sh" ]] \
        || fatal "arch_secure_post.sh not found in repo — cannot prepare postboot."

    cp "$REPO_ROOT/arch_secure_post.sh" "$post_script"
    chmod 750 "$post_script"
    log "[*] arch_secure_post.sh copied to ~/arch_secure_post.sh"

    # -- autostart in .bash_profile --
    local bash_profile="$home/.bash_profile"
    cat >> "$bash_profile" << 'EOF'

# ARCH_POSTBOOT_START
if [[ -f "$HOME/arch_secure_post.sh" ]]; then
    sudo bash "$HOME/arch_secure_post.sh"
fi
# ARCH_POSTBOOT_END
EOF
    log "[*] Autostart added to .bash_profile"

    # -- generate post_default.conf --
    # Bakes current session vars into a profile so post_install_engine.sh
    # can run fully automatically without prompting on first boot.
    local post_conf="$home/post_default.conf"

    cat > "$post_conf" << EOF
# ==============================================================================
#  Arch Secure Installer — Post-Install Profile
#  Generated automatically at install time: $(date -u '+%Y-%m-%d %H:%M UTC')
# ==============================================================================

# User
USERNAME="${USERNAME:-}"
USER_SHELL="${USER_SHELL:-/bin/bash}"

# Desktop
DESKTOP_ENV="${DESKTOP_ENV:-}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-}"

# TPM — PCR 0 (firmware) + 7 (secure boot state) + 11 (UKI)
TPM_PCRS="0+7+11"

# WiFi — saved separately in .wifi_creds, not here
EOF
    chmod 600 "$post_conf"
    log "[*] post_default.conf generated."

    # Fix ownership
    arch-chroot "$mnt" chown "${USERNAME}:${USERNAME}" \
        "/home/${USERNAME}/arch_secure_post.sh" \
        "/home/${USERNAME}/.bash_profile" \
        "/home/${USERNAME}/post_default.conf"
    [[ -f "$wifi_creds" ]] && \
        arch-chroot "$mnt" chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.wifi_creds"

    log "[*] Post-boot preparation complete."
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

            save_profile
            STATE="summary"
            save_state
            ;;

        summary)
            render_profile_summary
            read -r summary_input || true

            case "${summary_input:-}" in
                E|e)
                    batch "$INSTALL_ROOT/edit_profile.sh"
                    save_profile
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

            # Save WiFi, curl post bootstrap, add autostart
            prepare_postboot

            clear
            echo "================================================="
            echo "        Pre-Boot Installation Complete"
            echo "================================================="
            echo
            echo "  !! SAVE YOUR LUKS RECOVERY KEY NOW !!"
            echo
            echo "  Key location: $LUKS_KEY_FILE"
            echo
            if [[ -f "$LUKS_KEY_FILE" ]]; then
                echo "  Key:"
                echo
                cat "$LUKS_KEY_FILE"
                echo
            else
                echo "  [!] Key file not found at: $LUKS_KEY_FILE"
                echo
            fi
            echo "================================================="
            echo
            echo "  Store this key somewhere safe."
            echo "  Without it you cannot recover your data"
            echo "  if TPM enrollment fails."
            echo

            while true; do
                read -rp "  Type YES to confirm you saved the key: " key_saved
                [[ "$key_saved" == "YES" ]] && break
                echo "  [!] Please type YES to continue."
            done

            echo

            if [[ "${SB_MODE:-}" == "custom" ]]; then
                echo "  Custom Secure Boot keys enrolled."
                echo "  Rebooting to UEFI firmware to enable Secure Boot in:"
                echo
                for i in 5 4 3 2 1; do
                    printf "      %s ..\n" "$i"
                    sleep 1
                done
                echo
                systemctl reboot --firmware-setup
            else
                echo "  Rebooting into your new system in:"
                echo
                for i in 5 4 3 2 1; do
                    printf "      %s ..\n" "$i"
                    sleep 1
                done
                echo
                reboot
            fi
            ;;

        preboot_done)
            log "[*] Waiting for reboot to continue post-boot setup."
            exit 0
            ;;

        *)
            fatal "Unknown state: $STATE"
            ;;
    esac
}


# ==============================================================================
# MAIN LOOP
# ==============================================================================

while [[ "$STATE" != "preboot_done" ]]; do
    run_installation
done