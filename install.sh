#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Linux Secure Install - install-questions.sh
#  Interactive settings menu — writes /tmp/install-settings.conf
#
#  Usage:
#    bash install-questions.sh          # interactive menu
#    bash install-questions.sh default  # silent, accept all defaults
# ==============================================================================

MODE="${1:-interactive}"

# ==============================================================================
# DEFAULTS
# ==============================================================================

USERNAME="willem"
HOSTNAME="WA-Arch"
INSTALL_SHELL="zsh"
MIRROR_COUNTRIES="Netherlands,Germany"
TERMINAL_EMU="alacritty"
FILE_MANAGER="thunar"
MEDIA_PLAYER="mpv"
IMAGE_VIEWER="loupe"
VIRTUALIZATION="qemu-full libvirt virt-manager"
EXTRA_PACKAGES=""
DE="hyprland"

DEFAULT_MIRROR_COUNTRIES="Netherlands,Germany"

# Toggle state — 1 = enabled, 0 = disabled
PART5_ENABLED=1
PART6_ENABLED=1
PART7_ENABLED=1

# ==============================================================================
# HELPERS
# ==============================================================================

toggle_label() {
    [[ "$1" -eq 1 ]] && echo "[✓]" || echo "[ ]"
}

press_enter_to_continue() {
    echo
    read -rp "  Press ENTER to go back..." _
}

# ==============================================================================
# COUNTRY VALIDATION
# ==============================================================================

validate_countries() {
    local input="$1"
    local valid_countries
    valid_countries=$(reflector --list-countries 2>/dev/null | awk 'NR>2 {print $1}')

    local cleaned=""
    IFS=',' read -ra COUNTRY_LIST <<< "$input"

    for country in "${COUNTRY_LIST[@]}"; do
        country=$(echo "$country" | xargs)  # trim whitespace
        if [[ -z "$country" ]]; then
            continue
        fi
        if echo "$valid_countries" | grep -qi "^${country}$"; then
            cleaned+="$country,"
        else
            echo "  [!] Unknown country '$country' — removed." >&2
        fi
    done

    # Strip trailing comma
    cleaned="${cleaned%,}"

    # If nothing valid remains, revert to default
    if [[ -z "$cleaned" ]]; then
        echo "  [!] No valid countries remaining — reverting to default: $DEFAULT_MIRROR_COUNTRIES" >&2
        echo "$DEFAULT_MIRROR_COUNTRIES"
    else
        echo "$cleaned"
    fi
}

show_country_list() {
    clear
    echo "================================================="
    echo "   Valid Mirror Countries"
    echo "================================================="
    echo
    reflector --list-countries 2>/dev/null | awk 'NR>2 {printf "  %-30s %s\n", $1, $2}' | less -F
    echo
}

prompt_mirrors() {
    while true; do
        echo
        echo "  Current: $MIRROR_COUNTRIES"
        echo "  Type new value (comma separated), L to list countries, ENTER to keep current:"
        read -rp "  > " input

        case "$input" in
            l|L)
                show_country_list
                ;;
            "")
                # Keep current
                break
                ;;
            *)
                MIRROR_COUNTRIES=$(validate_countries "$input")
                echo "  [*] Set to: $MIRROR_COUNTRIES"
                sleep 1
                break
                ;;
        esac
    done
}

prompt_value() {
    local prompt="$1"
    local current="$2"
    local result
    read -rp "  $prompt [$current]: " result
    echo "${result:-$current}"
}

# ==============================================================================
# OVERVIEW DISPLAY
# ==============================================================================

show_overview() {
    clear
    echo "================================================="
    echo "   Arch Linux Secure Installation"
    echo "   Settings Overview"
    echo "================================================="
    echo
    echo "  PART 1 — Live (always runs)"
    echo "    Mirrors: $MIRROR_COUNTRIES"
    echo
    echo "  PART 2 — Chroot (always runs)"
    echo "    Username: $USERNAME"
    echo "    Hostname: $HOSTNAME"
    echo "    Shell:    $INSTALL_SHELL"
    echo
    echo "  PART 3 — Secure Boot (always runs)"
    echo "    Enrolls Secure Boot keys with sbctl"
    echo "    Signs the UKI (Unified Kernel Image)"
    echo
    echo "  PART 4 — Post Reboot (always runs)"
    echo "    Enrolls LUKS key into TPM2"
    echo "    Verifies TPM auto-unlock works"
    echo

    if [[ "$PART5_ENABLED" -eq 1 ]]; then
        echo "  PART 5 — User Environment          $(toggle_label $PART5_ENABLED)"
        echo "    Terminal: $TERMINAL_EMU"
    else
        echo "  PART 5 — User Environment          $(toggle_label $PART5_ENABLED)"
    fi
    echo

    if [[ "$PART6_ENABLED" -eq 1 ]]; then
        echo "  PART 6 — Software                  $(toggle_label $PART6_ENABLED)"
        echo "    File manager:   $FILE_MANAGER"
        echo "    Media player:   $MEDIA_PLAYER"
        echo "    Image viewer:   $IMAGE_VIEWER"
        echo "    Virtualization: $VIRTUALIZATION"
        echo "    Extra packages: ${EXTRA_PACKAGES:-none}"
    else
        echo "  PART 6 — Software                  $(toggle_label $PART6_ENABLED)"
    fi
    echo

    if [[ "$PART7_ENABLED" -eq 1 ]]; then
        echo "  PART 7 — Desktop Environment       $(toggle_label $PART7_ENABLED)"
        echo "    DE: $DE"
    else
        echo "  PART 7 — Desktop Environment       $(toggle_label $PART7_ENABLED)"
    fi
    echo

    echo "================================================="
    echo "  1,2 to edit  |  3,4 to view info  |  5,6,7 to enter section"
    echo "  ENTER to confirm and continue"
    echo "================================================="
    echo
}

# ==============================================================================
# SECTION MENUS
# ==============================================================================

# ------------------------------------------------------------------------------
# PART 1
# ------------------------------------------------------------------------------

menu_part1() {
    while true; do
        clear
        echo "================================================="
        echo "   Part 1 — Live"
        echo "================================================="
        echo
        echo "  [1] Mirror countries: $MIRROR_COUNTRIES"
        echo
        echo "  Press number to edit, ENTER to go back"
        echo
        read -rp "  Select: " choice

        case "$choice" in
            1) prompt_mirrors ;;
            "") break ;;
            *)
                echo "  [!] Invalid option."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# PART 2
# ------------------------------------------------------------------------------

menu_part2() {
    while true; do
        clear
        echo "================================================="
        echo "   Part 2 — Chroot"
        echo "================================================="
        echo
        echo "  [1] Username: $USERNAME"
        echo "  [2] Hostname: $HOSTNAME"
        echo "  [3] Shell:    $INSTALL_SHELL"
        echo
        echo "  Press number to edit, ENTER to go back"
        echo
        read -rp "  Select: " choice

        case "$choice" in
            1) USERNAME=$(prompt_value "Username" "$USERNAME") ;;
            2) HOSTNAME=$(prompt_value "Hostname" "$HOSTNAME") ;;
            3)
                echo
                echo "  Options: zsh, bash"
                INSTALL_SHELL=$(prompt_value "Shell" "$INSTALL_SHELL")
                ;;
            "") break ;;
            *)
                echo "  [!] Invalid option."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# PART 3 — info only
# ------------------------------------------------------------------------------

menu_part3() {
    clear
    echo "================================================="
    echo "   Part 3 — Secure Boot (always runs)"
    echo "================================================="
    echo
    echo "  This part sets up Secure Boot using sbctl."
    echo
    echo "  What it does:"
    echo "    - Puts firmware in Secure Boot setup mode"
    echo "    - Generates and enrolls your own Secure Boot keys"
    echo "    - Signs the Unified Kernel Image (UKI)"
    echo "    - From this point only signed kernels will boot"
    echo
    echo "  No configurable settings."
    echo
    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# PART 4 — info only
# ------------------------------------------------------------------------------

menu_part4() {
    clear
    echo "================================================="
    echo "   Part 4 — Post Reboot (always runs)"
    echo "================================================="
    echo
    echo "  This part runs after the first reboot into your"
    echo "  new system."
    echo
    echo "  What it does:"
    echo "    - Enrolls the LUKS decryption key into TPM2"
    echo "    - Binds the key to PCRs 0 and 7 (firmware + Secure Boot state)"
    echo "    - After this the disk unlocks automatically on boot"
    echo "    - Verifies the TPM auto-unlock works correctly"
    echo
    echo "  No configurable settings."
    echo
    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# PART 5
# ------------------------------------------------------------------------------

menu_part5() {
    while true; do
        clear
        echo "================================================="
        echo "   Part 5 — User Environment       $(toggle_label $PART5_ENABLED)"
        echo "================================================="
        echo
        echo "  [t] Toggle this part $([ $PART5_ENABLED -eq 1 ] && echo OFF || echo ON)"
        echo
        echo "  [1] Terminal: $TERMINAL_EMU"
        echo
        echo "  Press number to edit, ENTER to go back"
        echo
        read -rp "  Select: " choice

        case "$choice" in
            t|T)
                if [[ "$PART5_ENABLED" -eq 1 ]]; then
                    PART5_ENABLED=0
                    PART6_ENABLED=0
                    PART7_ENABLED=0
                    echo "  [*] Parts 5, 6 and 7 disabled."
                else
                    PART5_ENABLED=1
                    echo "  [*] Part 5 enabled."
                fi
                sleep 1
                ;;
            1)
                if [[ "$PART5_ENABLED" -eq 0 ]]; then
                    echo "  [!] Part 5 is disabled. Toggle it on first."
                    sleep 1
                else
                    echo
                    echo "  Options: alacritty, kitty, foot"
                    TERMINAL_EMU=$(prompt_value "Terminal" "$TERMINAL_EMU")
                fi
                ;;
            "") break ;;
            *)
                echo "  [!] Invalid option."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# PART 6
# ------------------------------------------------------------------------------

menu_part6() {
    while true; do
        clear
        echo "================================================="
        echo "   Part 6 — Software                $(toggle_label $PART6_ENABLED)"
        echo "================================================="
        echo
        echo "  [t] Toggle this part $([ $PART6_ENABLED -eq 1 ] && echo OFF || echo ON)"
        echo
        echo "  [1] File manager:   $FILE_MANAGER"
        echo "  [2] Media player:   $MEDIA_PLAYER"
        echo "  [3] Image viewer:   $IMAGE_VIEWER"
        echo "  [4] Virtualization: $VIRTUALIZATION"
        echo "  [5] Extra packages: ${EXTRA_PACKAGES:-none}"
        echo
        echo "  Press number to edit, ENTER to go back"
        echo
        read -rp "  Select: " choice

        case "$choice" in
            t|T)
                if [[ "$PART6_ENABLED" -eq 1 ]]; then
                    PART6_ENABLED=0
                    PART7_ENABLED=0
                    echo "  [*] Parts 6 and 7 disabled."
                else
                    if [[ "$PART5_ENABLED" -eq 0 ]]; then
                        echo "  [!] Part 5 is disabled. Enable Part 5 first."
                        sleep 2
                    else
                        PART6_ENABLED=1
                        echo "  [*] Part 6 enabled."
                    fi
                fi
                sleep 1
                ;;
            1)
                [[ "$PART6_ENABLED" -eq 0 ]] && { echo "  [!] Part 6 is disabled."; sleep 1; continue; }
                echo; echo "  Options: thunar, dolphin, nautilus"
                FILE_MANAGER=$(prompt_value "File manager" "$FILE_MANAGER")
                ;;
            2)
                [[ "$PART6_ENABLED" -eq 0 ]] && { echo "  [!] Part 6 is disabled."; sleep 1; continue; }
                echo; echo "  Options: mpv, vlc, haruna"
                MEDIA_PLAYER=$(prompt_value "Media player" "$MEDIA_PLAYER")
                ;;
            3)
                [[ "$PART6_ENABLED" -eq 0 ]] && { echo "  [!] Part 6 is disabled."; sleep 1; continue; }
                echo; echo "  Options: loupe, imv, eog"
                IMAGE_VIEWER=$(prompt_value "Image viewer" "$IMAGE_VIEWER")
                ;;
            4)
                [[ "$PART6_ENABLED" -eq 0 ]] && { echo "  [!] Part 6 is disabled."; sleep 1; continue; }
                echo; echo "  Options: 'qemu-full libvirt virt-manager', virtualbox, skip"
                VIRTUALIZATION=$(prompt_value "Virtualization" "$VIRTUALIZATION")
                ;;
            5)
                [[ "$PART6_ENABLED" -eq 0 ]] && { echo "  [!] Part 6 is disabled."; sleep 1; continue; }
                EXTRA_PACKAGES=$(prompt_value "Extra packages (space separated)" "${EXTRA_PACKAGES:-}")
                ;;
            "") break ;;
            *)
                echo "  [!] Invalid option."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# PART 7
# ------------------------------------------------------------------------------

menu_part7() {
    while true; do
        clear
        echo "================================================="
        echo "   Part 7 — Desktop Environment     $(toggle_label $PART7_ENABLED)"
        echo "================================================="
        echo
        echo "  [t] Toggle this part $([ $PART7_ENABLED -eq 1 ] && echo OFF || echo ON)"
        echo
        echo "  [1] DE: $DE"
        echo
        echo "  Press number to edit, ENTER to go back"
        echo
        read -rp "  Select: " choice

        case "$choice" in
            t|T)
                if [[ "$PART7_ENABLED" -eq 1 ]]; then
                    PART7_ENABLED=0
                    echo "  [*] Part 7 disabled."
                else
                    if [[ "$PART5_ENABLED" -eq 0 || "$PART6_ENABLED" -eq 0 ]]; then
                        echo "  [!] Parts 5 and 6 must be enabled first."
                        sleep 2
                    else
                        PART7_ENABLED=1
                        echo "  [*] Part 7 enabled."
                    fi
                fi
                sleep 1
                ;;
            1)
                [[ "$PART7_ENABLED" -eq 0 ]] && { echo "  [!] Part 7 is disabled."; sleep 1; continue; }
                echo
                echo "  Options:"
                echo "  [1] hyprland"
                echo "  [2] kde        (not yet implemented)"
                echo "  [3] gnome      (not yet implemented)"
                echo
                read -rp "  Select [1]: " DE_CHOICE
                case "${DE_CHOICE:-1}" in
                    2) DE="kde";   echo "  [!] KDE not yet implemented, but saved for future use." ;;
                    3) DE="gnome"; echo "  [!] Gnome not yet implemented, but saved for future use." ;;
                    *) DE="hyprland" ;;
                esac
                sleep 1
                ;;
            "") break ;;
            *)
                echo "  [!] Invalid option."
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# DEFAULT MODE — show summary and write conf silently
# ==============================================================================

if [[ "$MODE" == "default" ]]; then
    clear
    echo "================================================="
    echo "   Arch Linux Secure Installation"
    echo "   Default Settings"
    echo "================================================="
    echo
    echo "  PART 1 — Live"
    echo "    Mirrors:  $MIRROR_COUNTRIES"
    echo
    echo "  PART 2 — Chroot"
    echo "    Username: $USERNAME"
    echo "    Hostname: $HOSTNAME"
    echo "    Shell:    $INSTALL_SHELL"
    echo
    echo "  PART 3 — Secure Boot (no configurable settings)"
    echo
    echo "  PART 4 — Post Reboot (no configurable settings)"
    echo
    echo "  PART 5 — User Environment          [✓]"
    echo "    Terminal: $TERMINAL_EMU"
    echo
    echo "  PART 6 — Software                  [✓]"
    echo "    File manager:   $FILE_MANAGER"
    echo "    Media player:   $MEDIA_PLAYER"
    echo "    Image viewer:   $IMAGE_VIEWER"
    echo "    Virtualization: $VIRTUALIZATION"
    echo "    Extra packages: ${EXTRA_PACKAGES:-none}"
    echo
    echo "  PART 7 — Desktop Environment       [✓]"
    echo "    DE: $DE"
    echo
    echo "================================================="
    echo
    read -rp "  Press ENTER to continue..." _
fi

# ==============================================================================
# INTERACTIVE MODE — full menu loop
# ==============================================================================

if [[ "$MODE" == "interactive" ]]; then
    while true; do
        show_overview
        read -rp "  Select: " choice

        case "$choice" in
            1) menu_part1 ;;
            2) menu_part2 ;;
            3) menu_part3 ;;
            4) menu_part4 ;;
            5) menu_part5 ;;
            6) menu_part6 ;;
            7) menu_part7 ;;
            "")
                break
                ;;
            *)
                echo "  [!] Invalid option."
                sleep 1
                ;;
        esac
    done
fi

# ==============================================================================
# WRITE /tmp/install-settings.conf
# ==============================================================================

cat > /tmp/install-settings.conf <<EOF
# ==============================================================================
#  Arch Linux Secure Install - Settings
#  Generated by install-questions.sh
# ==============================================================================

USERNAME="$USERNAME"
HOSTNAME="$HOSTNAME"
INSTALL_SHELL="$INSTALL_SHELL"
MIRROR_COUNTRIES="$MIRROR_COUNTRIES"
DE="$DE"
TERMINAL_EMU="$TERMINAL_EMU"
FILE_MANAGER="$FILE_MANAGER"
MEDIA_PLAYER="$MEDIA_PLAYER"
IMAGE_VIEWER="$IMAGE_VIEWER"
VIRTUALIZATION="$VIRTUALIZATION"
EXTRA_PACKAGES="$EXTRA_PACKAGES"
PART5_ENABLED=$PART5_ENABLED
PART6_ENABLED=$PART6_ENABLED
PART7_ENABLED=$PART7_ENABLED
EOF

echo "[*] Settings saved to /tmp/install-settings.conf"