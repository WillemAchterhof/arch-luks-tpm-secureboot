#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — desktop.sh
#  Post-boot desktop environment installation and configuration
#  Supports: kde, hyprland, jakoolit
# ==============================================================================

: "${USERNAME:?USERNAME not set}"
: "${DESKTOP_ENV:?DESKTOP_ENV not set}"
: "${CONFIGS_DIR:?CONFIGS_DIR not set}"

USER_HOME="/home/$USERNAME"

# ==============================================================================
# HELPERS
# ==============================================================================

install_pkgs() {
    pacman -S --noconfirm --needed "$@"
}

install_aur_pkgs() {
    sudo -u "$USERNAME" yay -S --noconfirm --needed "$@"
}

deploy_config() {
    local src="$1" dst="$2"
    if [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
    else
        log "[!] Config not found, skipping: $src"
    fi
}

# ==============================================================================
# YAY — AUR HELPER
# ==============================================================================

install_yay() {
    if command -v yay &>/dev/null; then
        log "[*] yay already installed — skipping."
        return 0
    fi

    log "[*] Installing yay AUR helper..."
    pacman -S --noconfirm --needed base-devel git

    local build_dir
    build_dir="$(mktemp -d /tmp/yay-build-XXXXXX)"
    chown "$USERNAME:$USERNAME" "$build_dir"

    sudo -u "$USERNAME" git clone \
        https://aur.archlinux.org/yay.git "$build_dir/yay" \
        || fatal "Failed to clone yay from AUR."

    sudo -u "$USERNAME" bash -c \
        "cd '$build_dir/yay' && makepkg -si --noconfirm" \
        || fatal "Failed to build yay."

    rm -rf "$build_dir"
    log "[*] yay installed."
}

# ==============================================================================
# LAYER 1 — WAYLAND BASE
# ==============================================================================

install_wayland_base() {
    log "[*] Installing Wayland base..."
    install_pkgs \
        qt5-wayland \
        qt6-wayland \
        xdg-desktop-portal-gtk \
        xdg-user-dirs \
        xdg-utils

    sudo -u "$USERNAME" xdg-user-dirs-update
    log "[*] Wayland base installed."
}

# ==============================================================================
# LAYER 2 — AUDIO (pipewire stack)
# ==============================================================================

install_audio() {
    log "[*] Installing audio stack..."
    install_pkgs \
        pipewire \
        pipewire-alsa \
        pipewire-pulse \
        pipewire-jack \
        wireplumber \
        pamixer \
        pavucontrol

    # Enable linger so user services start without an active login session
    loginctl enable-linger "$USERNAME"

    # Must use --machine — no user session exists at post-boot stage so
    # $DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR are not set.
    systemctl --machine="${USERNAME}@.host" --user enable \
        pipewire pipewire-pulse wireplumber \
        || log "[!] Could not enable audio services via --machine. Run manually after login: systemctl --user enable pipewire pipewire-pulse wireplumber"

    log "[*] Audio stack installed."
}

# ==============================================================================
# LAYER 3 — SHELL
# ==============================================================================

install_shell() {
    log "[*] Installing zsh..."
    install_pkgs \
        zsh \
        zsh-completions \
        zsh-autosuggestions

    local current_shell
    current_shell="$(getent passwd "$USERNAME" | cut -d: -f7)"
    if [[ "$current_shell" != "/usr/bin/zsh" ]]; then
        chsh -s /usr/bin/zsh "$USERNAME"
        log "[*] zsh set as default shell."
    else
        log "[*] zsh already set as default shell — skipping."
    fi
}

# ==============================================================================
# LAYER 4 — FONTS
# ==============================================================================

install_fonts() {
    log "[*] Installing fonts..."
    install_pkgs \
        ttf-jetbrains-mono-nerd \
        ttf-dejavu \
        ttf-liberation \
        otf-font-awesome \
        noto-fonts \
        noto-fonts-cjk \
        noto-fonts-emoji

    log "[*] Fonts installed."
}

# ==============================================================================
# LAYER 5 — THEMING
# ==============================================================================

install_theming() {
    log "[*] Installing theming tools..."
    install_pkgs \
        nwg-look \
        qt5ct \
        qt6ct \
        papirus-icon-theme

    log "[*] Theming tools installed."
}

# ==============================================================================
# LAYER 6 — TERMINAL + TOOLS
# ==============================================================================

install_tools() {
    log "[*] Installing terminal and tools..."
    install_pkgs \
        alacritty \
        neovim \
        btop \
        fastfetch \
        man-db \
        reflector \
        git \
        jq \
        python-requests \
        unzip \
        p7zip \
        hunspell \
        hunspell-en_us \
        hunspell-nl

    log "[*] Tools installed."
}

# ==============================================================================
# LAYER 7 — FILE MANAGEMENT
# ==============================================================================

install_filemanager() {
    log "[*] Installing file manager..."
    install_pkgs \
        thunar \
        thunar-volman \
        tumbler \
        gvfs \
        gvfs-mtp \
        ffmpegthumbs

    log "[*] File manager installed."
}

# ==============================================================================
# LAYER 8 — NETWORK TOOLS
# ==============================================================================

install_network_tools() {
    log "[*] Installing network tools..."
    install_pkgs network-manager-applet
    install_aur_pkgs networkmanager-dmenu-git
    log "[*] Network tools installed."
}

# ==============================================================================
# LAYER 9 — EXTRA PACKAGES (from profile)
# ==============================================================================

install_extra_packages() {
    [[ -z "${EXTRA_PACKAGES:-}" ]] && return 0
    log "[*] Installing extra packages..."
    # Use yay — handles both official repos and AUR packages transparently
    # shellcheck disable=SC2086
    sudo -u "$USERNAME" yay -S --noconfirm --needed $EXTRA_PACKAGES
    log "[*] Extra packages installed."
}

# ==============================================================================
# SHARED — ENVIRONMENT
# ==============================================================================

configure_environment() {
    log "[*] Writing /etc/environment..."

    cat > /etc/environment <<EOF
EDITOR=nvim
VISUAL=nvim
TERMINAL=alacritty
EOF

    if [[ "${DESKTOP_ENV,,}" == "hyprland" ]]; then
        cat >> /etc/environment <<'EOF'
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
SDL_VIDEODRIVER=wayland
EOF
    fi

    log "[*] Environment configured."
}

# ==============================================================================
# SHARED — ALACRITTY CONFIG
# ==============================================================================

deploy_alacritty_config() {
    log "[*] Deploying alacritty config..."

    local cfg_dir="$USER_HOME/.config/alacritty"
    mkdir -p "$cfg_dir"

    deploy_config \
        "$CONFIGS_DIR/alacritty/alacritty.toml" \
        "$cfg_dir/alacritty.toml"

    chown -R "$USERNAME:$USERNAME" "$cfg_dir"
    log "[*] Alacritty config deployed."
}

# ==============================================================================
# SHARED — POST-INSTALL GROUP ADDITIONS
# ==============================================================================

configure_user_groups() {
    if pacman -Q libvirt &>/dev/null; then
        usermod -aG libvirt "$USERNAME"
        log "[*] Added $USERNAME to libvirt group."
    fi
}

# ==============================================================================
# KDE
# ==============================================================================

install_kde() {
    log "[*] Installing KDE Plasma..."
    install_pkgs \
        plasma-meta \
        kde-applications-meta \
        sddm \
        xdg-desktop-portal-kde

    systemctl enable sddm
    configure_user_groups
    log "[*] KDE installed."
}

# ==============================================================================
# HYPRLAND
# ==============================================================================

install_hyprland() {
    log "[*] Installing Hyprland compositor stack..."

    install_pkgs \
        hyprland hyprlock hypridle hyprpaper \
        xdg-desktop-portal-hyprland \
        polkit-kde-agent

    install_pkgs \
        waybar rofi-wayland dunst wlogout

    install_pkgs \
        grim slurp swappy wl-clipboard cliphist

    install_pkgs \
        brightnessctl playerctl wlsunset

    install_pkgs sddm
    systemctl enable sddm

    configure_user_groups
    deploy_hyprland_configs
    log "[*] Hyprland installed."
}

deploy_hyprland_configs() {
    local hypr_cfg="$USER_HOME/.config/hypr"
    local waybar_cfg="$USER_HOME/.config/waybar"
    local rofi_cfg="$USER_HOME/.config/rofi"

    mkdir -p "$hypr_cfg/themes" "$waybar_cfg" "$rofi_cfg"

    deploy_config "$CONFIGS_DIR/hyprland/hyprland.conf"           "$hypr_cfg/hyprland.conf"
    deploy_config "$CONFIGS_DIR/hyprland/hyprlock.conf"           "$hypr_cfg/hyprlock.conf"
    deploy_config "$CONFIGS_DIR/hyprland/themes/tokyonight.conf"  "$hypr_cfg/themes/tokyonight.conf"
    deploy_config "$CONFIGS_DIR/waybar/config.jsonc"              "$waybar_cfg/config.jsonc"
    deploy_config "$CONFIGS_DIR/waybar/style.css"                 "$waybar_cfg/style.css"
    deploy_config "$CONFIGS_DIR/rofi/config.rasi"                 "$rofi_cfg/config.rasi"
    deploy_config "$CONFIGS_DIR/rofi/tokyonight.rasi"             "$rofi_cfg/tokyonight.rasi"

    chown -R "$USERNAME:$USERNAME" "$hypr_cfg" "$waybar_cfg" "$rofi_cfg"
    log "[*] Hyprland configs deployed."
}

# ==============================================================================
# JAKOOLIT
# ==============================================================================

install_jakoolit() {
    log "[*] Launching JaKooLit Arch-Hyprland installer..."
    log "  Thank you JaKooLit — https://github.com/JaKooLit/Arch-Hyprland"
    log "  Note: interactive — please follow the prompts."

    pacman -S --noconfirm --needed git

    local build_dir
    build_dir="$(mktemp -d /tmp/jakoolit-XXXXXX)"

    git clone --depth 1 \
        https://github.com/JaKooLit/Arch-Hyprland.git "$build_dir" \
        || fatal "Failed to clone JaKooLit Arch-Hyprland installer."

    chown -R "$USERNAME:$USERNAME" "$build_dir"

    # JaKooLit explicitly rejects root — must run as user
    sudo -u "$USERNAME" bash -c "cd '$build_dir' && bash install.sh" \
        || fatal "JaKooLit installer failed."

    rm -rf "$build_dir"
    log "[*] JaKooLit installer complete."
}

# ==============================================================================
# SERVICE HARDENING
# Moved from system.sh — safer to run after all packages are installed
# ==============================================================================

configure_services_hardening() {
    log "[*] Masking unused network services..."
    systemctl mask         systemd-networkd         wpa_supplicant         2>/dev/null || true

    log "[*] Disabling unnecessary services..."
    systemctl disable         machines.target         NetworkManager-dispatcher.service         NetworkManager-wait-online.service         remote-integritysetup.target         remote-veritysetup.target         systemd-mountfsd.socket         systemd-network-generator.service         systemd-networkd-wait-online.service         systemd-nsresourced.socket         systemd-pstore.service         2>/dev/null || true

    log "[*] Service hardening complete."
}

# ==============================================================================
# CLEANUP
# ==============================================================================

cleanup() {
    log "[*] Running post-install cleanup..."
    rm -rf /tmp/yay-build-* 2>/dev/null || true
    yay -Sc --noconfirm 2>/dev/null || true
    pacman -Sc --noconfirm
    log "[*] Cleanup complete."
}

# ==============================================================================
# MAIN
# ==============================================================================

log "[*] Desktop install starting — environment: $DESKTOP_ENV"
log ""
log "  Hyprland setup inspired by and grateful to:"
log "    - JaKooLit (Arch-Hyprland)    https://github.com/JaKooLit/Arch-Hyprland"
log ""

sed -i \
    -e 's/^#Color/Color/' \
    -e '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' \
    /etc/pacman.conf
pacman -Sy --noconfirm

install_yay
install_wayland_base
install_audio
install_shell
install_fonts
install_theming
install_tools
install_filemanager
install_network_tools
install_extra_packages
configure_environment
deploy_alacritty_config

case "${DESKTOP_ENV,,}" in
    kde)       install_kde      ;;
    hyprland)  install_hyprland ;;
    jakoolit)  install_jakoolit ;;
    *)         fatal "Unknown DESKTOP_ENV: $DESKTOP_ENV — supported: kde, hyprland, jakoolit" ;;
esac

configure_services_hardening
cleanup

log "[*] desktop.sh complete — reboot to start $DESKTOP_ENV."