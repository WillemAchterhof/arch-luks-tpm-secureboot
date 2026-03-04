#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — system.sh
#  Base system install, configuration, hardening, services
# ==============================================================================

: "${PACMAN_PARALLEL_CHROOT:?PACMAN_PARALLEL_CHROOT not set}"
: "${TIMEZONE:?TIMEZONE not set}"
: "${INSTALL_HOSTNAME:?INSTALL_HOSTNAME not set}"
: "${USERNAME:?USERNAME not set}"
: "${CONFIGS_DIR:?CONFIGS_DIR not set}"

MNT="/mnt"

# ==============================================================================
# CPU MICROCODE
# ==============================================================================

detect_ucode() {
    local vendor
    vendor=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}' | tr '[:upper:]' '[:lower:]')
    case "$vendor" in
        genuineintel) echo "intel-ucode" ;;
        authenticamd) echo "amd-ucode"   ;;
        *)
            log "[!] Unknown CPU vendor: $vendor — skipping microcode"
            echo ""
            ;;
    esac
}

# ==============================================================================
# INSTALL BASE SYSTEM
# ==============================================================================

install_base() {
    local ucode
    ucode="$(detect_ucode)"

    log "[*] CPU microcode: ${ucode:-none}"
    log "[*] Installing base system via pacstrap..."
    pacstrap -K "$MNT" \
        base base-devel \
        linux linux-headers linux-firmware \
        ${ucode:+"$ucode"} \
        cryptsetup mkinitcpio \
        sbctl efibootmgr \
        tpm2-tools \
        apparmor nftables \
        networkmanager iwd \
        sudo \
        man-db \
        git \
        binutils \
        iproute2 iputils \
        reflector \
        libpwquality \
        polkit \
        tar gzip unzip p7zip

    log "[*] Base system installed."
}

# ==============================================================================
# FSTAB
# ==============================================================================

generate_fstab() {
    log "[*] Generating fstab..."
    genfstab -U "$MNT" >> "$MNT/etc/fstab"
    log "[*] fstab generated."
}

# ==============================================================================
# PACMAN
# ==============================================================================

configure_pacman() {
    log "[*] Configuring pacman in chroot..."

    arch-chroot "$MNT" sed -i \
        -e "s/^#\?ParallelDownloads.*/ParallelDownloads = $PACMAN_PARALLEL_CHROOT/" \
        -e 's/^#Color/Color/' \
        -e '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' \
        /etc/pacman.conf

    log "[*] Updating system in chroot..."
    arch-chroot "$MNT" pacman -Syu --noconfirm
}

# ==============================================================================
# TIMEZONE
# ==============================================================================

configure_timezone() {
    log "[*] Setting timezone: $TIMEZONE"
    arch-chroot "$MNT" ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    arch-chroot "$MNT" hwclock --systohc
}

# ==============================================================================
# LOCALE
# ==============================================================================

configure_locale() {
    log "[*] Configuring locale: en_US.UTF-8"

    arch-chroot "$MNT" sed -i \
        's/^#\(en_US\.UTF-8\)/\1/' \
        /etc/locale.gen

    arch-chroot "$MNT" locale-gen

    printf 'LANG=en_US.UTF-8\n'  > "$MNT/etc/locale.conf"
    printf 'KEYMAP=us\n'         > "$MNT/etc/vconsole.conf"

    log "[*] Locale configured."
}

# ==============================================================================
# HOSTNAME
# ==============================================================================

configure_hostname() {
    log "[*] Setting hostname: $INSTALL_HOSTNAME"

    printf '%s\n' "$INSTALL_HOSTNAME" > "$MNT/etc/hostname"

    cat > "$MNT/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $INSTALL_HOSTNAME.localdomain $INSTALL_HOSTNAME
EOF

    log "[*] Hostname configured."
}

# ==============================================================================
# USER
# ==============================================================================

configure_user() {
    log "[*] Creating user: $USERNAME"

    arch-chroot "$MNT" useradd \
        -m \
        -G wheel \
        -s /bin/bash \
        "$USERNAME"

    echo
    echo "  Set password for user: $USERNAME"
    arch-chroot "$MNT" passwd "$USERNAME"

    # sudo — wheel requires password
    printf '%%wheel ALL=(ALL:ALL) ALL\n' \
        > "$MNT/etc/sudoers.d/wheel"
    chmod 440 "$MNT/etc/sudoers.d/wheel"

    # sudo hardening
    printf 'Defaults use_pty\n' \
        > "$MNT/etc/sudoers.d/hardening"
    chmod 440 "$MNT/etc/sudoers.d/hardening"

    # Lock root
    arch-chroot "$MNT" passwd -l root
    log "[*] Root account locked."

    log "[*] User $USERNAME created."
}

# ==============================================================================
# DEPLOY CONFIG FILES
# ==============================================================================

deploy_configs() {
    log "[*] Deploying system config files..."

    local sys_cfg="$CONFIGS_DIR/system"

    # NetworkManager
    [[ -f "$sys_cfg/NetworkManager.conf" ]] \
        || fatal "Missing config: $sys_cfg/NetworkManager.conf"
    cp "$sys_cfg/NetworkManager.conf" \
        "$MNT/etc/NetworkManager/NetworkManager.conf"

    mkdir -p "$MNT/etc/NetworkManager/conf.d"
    cat > "$MNT/etc/NetworkManager/conf.d/20-mac-randomize.conf" <<'EOF'
[connection]
wifi.cloned-mac-address=random
ethernet.cloned-mac-address=random
EOF

    # Firewall
    [[ -f "$sys_cfg/nftables.conf" ]] \
        || fatal "Missing config: $sys_cfg/nftables.conf"
    cp "$sys_cfg/nftables.conf"     "$MNT/etc/nftables.conf"

    # Sysctl hardening
    [[ -f "$sys_cfg/99-hardening.conf" ]] \
        || fatal "Missing config: $sys_cfg/99-hardening.conf"
    cp "$sys_cfg/99-hardening.conf" "$MNT/etc/sysctl.d/99-hardening.conf"

    # Kernel module blacklist
    [[ -f "$sys_cfg/blacklist.conf" ]] \
        || fatal "Missing config: $sys_cfg/blacklist.conf"
    cp "$sys_cfg/blacklist.conf"    "$MNT/etc/modprobe.d/blacklist.conf"

    # UKI auto-signing pacman hook
    [[ -f "$sys_cfg/zz-sbctl-uki.hook" ]] \
        || fatal "Missing config: $sys_cfg/zz-sbctl-uki.hook"
    mkdir -p "$MNT/etc/pacman.d/hooks"
    cp "$sys_cfg/zz-sbctl-uki.hook" "$MNT/etc/pacman.d/hooks/zz-sbctl-uki.hook"

    log "[*] Config files deployed."
}

# ==============================================================================
# WIFI CONFIG
# ==============================================================================

copy_wifi_config() {
    local wifi_src="$USB_ROOT/wifi.conf"

    [[ -f "$wifi_src" ]] || return 0

    log "[*] WiFi config found — copying to installed system..."

    mkdir -p "$MNT/etc/NetworkManager/system-connections"
    cp "$wifi_src" "$MNT/etc/NetworkManager/system-connections/wifi.conf"
    chmod 600 "$MNT/etc/NetworkManager/system-connections/wifi.conf"

    log "[*] WiFi config deployed."
}

# ==============================================================================
# POSTBOOT AUTOSTART
# ==============================================================================

deploy_postboot_autostart() {
    log "[*] Deploying post-boot autostart..."

    local user_home="$MNT/home/$USERNAME"
    local docs_dir="$user_home/Documents"
    local profile="$user_home/.bash_profile"
    local script_src="$USB_ROOT/arch_secure_install.sh"

    mkdir -p "$docs_dir"

    [[ -f "$script_src" ]] \
        || fatal "arch_secure_install.sh not found at: $script_src"
    cp "$script_src" "$docs_dir/arch_secure_install.sh"
    chmod 750 "$docs_dir/arch_secure_install.sh"

    arch-chroot "$MNT" chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/Documents"

    cat >> "$profile" <<'BASHEOF'

# ARCH_POSTBOOT_START
if [[ -f "$HOME/Documents/arch_secure_install.sh" ]]; then
log "=== Arch Secure Installer Engine Starting ==="
log ""
log "  Inspired by and grateful to:"
log "    - JaKooLit (Arch-Hyprland)    https://github.com/JaKooLit/Arch-Hyprland"
log "    - Ataraxxia (Secure Arch)     https://github.com/Ataraxxia/secure-arch"
log ""
    echo
    echo "================================================="
    echo "   Post-Boot Setup Pending"
    echo "================================================="
    echo
    echo "  Enter your sudo password to continue installation."
    echo "  Press Ctrl+C to abort."
    echo
    echo "  To run manually later:"
    echo "      sudo bash ~/Documents/arch_secure_install.sh"
    echo
    sudo bash "$HOME/Documents/arch_secure_install.sh"
fi
# ARCH_POSTBOOT_END
BASHEOF

    arch-chroot "$MNT" chown "$USERNAME:$USERNAME" "/home/$USERNAME/.bash_profile"

    log "[*] Post-boot autostart deployed."
}

# ==============================================================================
# SERVICES
# ==============================================================================

configure_services() {
    log "[*] Enabling services..."

    arch-chroot "$MNT" systemctl enable \
        apparmor \
        NetworkManager \
        nftables \
        fstrim.timer \
        reflector.timer \
        systemd-resolved \
        systemd-timesyncd

    # resolv.conf — use systemd-resolved stub
    ln -sf /run/systemd/resolve/stub-resolv.conf \
        "$MNT/etc/resolv.conf"

    log "[*] Masking unused network services..."
    arch-chroot "$MNT" systemctl mask \
        systemd-networkd \
        wpa_supplicant

    log "[*] Disabling unnecessary services..."
    arch-chroot "$MNT" systemctl disable \
        machines.target \
        NetworkManager-dispatcher.service \
        NetworkManager-wait-online.service \
        remote-integritysetup.target \
        remote-veritysetup.target \
        systemd-mountfsd.socket \
        systemd-network-generator.service \
        systemd-networkd-wait-online.service \
        systemd-nsresourced.socket \
        systemd-pstore.service

    log "[*] Services configured."
}

# ==============================================================================
# MAIN
# ==============================================================================

install_base
generate_fstab
configure_pacman
configure_timezone
configure_locale
configure_hostname
configure_user
deploy_configs
copy_wifi_config
configure_services
deploy_postboot_autostart

log "[*] system.sh complete."
