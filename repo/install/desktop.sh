#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — desktop.sh
#  Post-boot desktop environment installation and configuration
#  Supports: kde, hyprland
# ==============================================================================

: "${USERNAME:?USERNAME not set}"
: "${DESKTOP_ENV:?DESKTOP_ENV not set}"
: "${CONFIGS_DIR:?CONFIGS_DIR not set}"

USER_HOME="/home/$USERNAME"

# ==============================================================================
# HELPERS
# ==============================================================================

install_pkgs() {
    sudo pacman -S --noconfirm --needed "$@"
}

install_aur_pkgs() {
    yay -S --noconfirm --needed "$@"
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

    # base-devel required to build AUR packages
    sudo pacman -S --noconfirm --needed base-devel

    local build_dir
    build_dir="$(mktemp -d /tmp/yay-build-XXXXXX)"

    git clone https://aur.archlinux.org/yay.git "$build_dir/yay" \
        || fatal "Failed to clone yay from AUR."

    (cd "$build_dir/yay" && makepkg -si --noconfirm) \
        || fatal "Failed to build yay."

    rm -rf "$build_dir"
    log "[*] yay installed and build directory cleaned up."
}

deploy_config() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
}

# ==============================================================================
# LAYER 1 — WAYLAND BASE
# Required by both KDE (wayland session) and Hyprland
# ==============================================================================

install_wayland_base() {
    log "[*] Installing Wayland base..."
    install_pkgs \
        qt5-wayland \
        qt6-wayland \
        xdg-desktop-portal-gtk \
        xdg-user-dirs \
        xdg-utils

    xdg-user-dirs-update
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

    systemctl --user enable pipewire pipewire-pulse wireplumber
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

    sudo chsh -s /usr/bin/zsh "$USERNAME"
    log "[*] zsh set as default shell."
}

# ==============================================================================
# LAYER 4 — FONTS
# Nerd fonts required for waybar/rofi icons
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
# LAYER 5 — THEMING (GTK + Qt consistency)
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
    install_pkgs \
        network-manager-applet

    install_aur_pkgs \
        networkmanager-dmenu-git

    log "[*] Network tools installed."
}

# ==============================================================================
# LAYER 9 — EXTRA PACKAGES (from profile)
# ==============================================================================

install_extra_packages() {
    [[ -z "${EXTRA_PACKAGES:-}" ]] && return 0

    log "[*] Installing extra packages..."
    # shellcheck disable=SC2086
    install_pkgs $EXTRA_PACKAGES
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

    [[ -f "$CONFIGS_DIR/alacritty/alacritty.toml" ]] \
        && deploy_config "$CONFIGS_DIR/alacritty/alacritty.toml" "$cfg_dir/alacritty.toml"

    chown -R "$USERNAME:$USERNAME" "$cfg_dir"
    log "[*] Alacritty config deployed."
}

# ==============================================================================
# SHARED — POST-INSTALL GROUP ADDITIONS
# ==============================================================================

configure_user_groups() {
    # libvirt — only if package is installed
    if pacman -Q libvirt &>/dev/null; then
        sudo usermod -aG libvirt "$USERNAME"
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

    sudo systemctl enable sddm
    log "[*] SDDM enabled."

    configure_user_groups
    log "[*] KDE installed."
}

# ==============================================================================
# HYPRLAND — COMPOSITOR STACK
# ==============================================================================

install_hyprland() {
    log "[*] Installing Hyprland compositor stack..."

    # Core compositor
    install_pkgs \
        hyprland \
        hyprlock \
        hypridle \
        hyprpaper \
        xdg-desktop-portal-hyprland \
        polkit-kde-agent

    # Bar + launcher + notifications
    install_pkgs \
        waybar \
        rofi-wayland \
        dunst \
        wlogout

    # Screenshot + clipboard
    install_pkgs \
        grim \
        slurp \
        swappy \
        wl-clipboard \
        cliphist

    # Hardware controls
    install_pkgs \
        brightnessctl \
        playerctl \
        wlsunset

    # Display manager
    install_pkgs sddm
    sudo systemctl enable sddm
    log "[*] SDDM enabled."

    configure_user_groups

    log "[*] Deploying Hyprland configs..."
    deploy_hyprland_configs

    log "[*] Hyprland installed."
}

deploy_hyprland_configs() {
    local hypr_cfg="$USER_HOME/.config/hypr"
    local waybar_cfg="$USER_HOME/.config/waybar"
    local rofi_cfg="$USER_HOME/.config/rofi"

    mkdir -p "$hypr_cfg/themes" "$waybar_cfg" "$rofi_cfg"

    # Hyprland
    [[ -f "$CONFIGS_DIR/hyprland/hyprland.conf" ]] \
        && deploy_config "$CONFIGS_DIR/hyprland/hyprland.conf" \
                         "$hypr_cfg/hyprland.conf"

    [[ -f "$CONFIGS_DIR/hyprland/hyprlock.conf" ]] \
        && deploy_config "$CONFIGS_DIR/hyprland/hyprlock.conf" \
                         "$hypr_cfg/hyprlock.conf"

    [[ -f "$CONFIGS_DIR/hyprland/themes/tokyonight.conf" ]] \
        && deploy_config "$CONFIGS_DIR/hyprland/themes/tokyonight.conf" \
                         "$hypr_cfg/themes/tokyonight.conf"

    # Waybar
    [[ -f "$CONFIGS_DIR/waybar/config.jsonc" ]] \
        && deploy_config "$CONFIGS_DIR/waybar/config.jsonc" \
                         "$waybar_cfg/config.jsonc"

    [[ -f "$CONFIGS_DIR/waybar/style.css" ]] \
        && deploy_config "$CONFIGS_DIR/waybar/style.css" \
                         "$waybar_cfg/style.css"

    # Rofi
    [[ -f "$CONFIGS_DIR/rofi/config.rasi" ]] \
        && deploy_config "$CONFIGS_DIR/rofi/config.rasi" \
                         "$rofi_cfg/config.rasi"

    [[ -f "$CONFIGS_DIR/rofi/tokyonight.rasi" ]] \
        && deploy_config "$CONFIGS_DIR/rofi/tokyonight.rasi" \
                         "$rofi_cfg/tokyonight.rasi"

    # Fix ownership
    chown -R "$USERNAME:$USERNAME" \
        "$hypr_cfg" \
        "$waybar_cfg" \
        "$rofi_cfg"

    log "[*] Hyprland configs deployed."
}

# ==============================================================================
# JAKOOLIT — Arch-Hyprland Installer
# ==============================================================================

install_jakoolit() {
    log "[*] Launching JaKooLit Arch-Hyprland installer..."
    log ""
    log "  Thank you JaKooLit — https://github.com/JaKooLit/Arch-Hyprland"
    log ""
    log "  Note: JaKooLit installer is interactive — please follow the prompts."
    log "  Any overlapping packages will be safely reinstalled."
    log ""

    sudo pacman -S --noconfirm --needed git

    local build_dir
    build_dir="$(mktemp -d /tmp/jakoolit-XXXXXX)"

    git clone --depth 1 https://github.com/JaKooLit/Arch-Hyprland.git         "$build_dir" || fatal "Failed to clone JaKooLit Arch-Hyprland installer."

    cd "$build_dir"
    bash install.sh

    rm -rf "$build_dir"
    log "[*] JaKooLit installer complete."
}

# ==============================================================================
# CLEANUP
# ==============================================================================

cleanup() {
    log "[*] Running post-install cleanup..."

    # Remove any leftover yay build dirs in /tmp
    rm -rf /tmp/yay-build-* 2>/dev/null || true

    # Remove yay package cache
    yay -Sc --noconfirm 2>/dev/null || true

    # Remove pacman package cache
    sudo pacman -Sc --noconfirm

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

# Ensure multilib and fresh db
sudo sed -i \
    -e 's/^#Color/Color/' \
    -e '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' \
    /etc/pacman.conf
sudo pacman -Sy --noconfirm

# Shared layers — installed for all desktop environments
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

# Desktop-specific
case "${DESKTOP_ENV,,}" in
    kde)
        install_kde
        ;;
    hyprland)
        install_hyprland
        ;;
    jakoolit)
        install_jakoolit
        ;;
    *)
        fatal "Unknown DESKTOP_ENV: $DESKTOP_ENV — supported: kde, hyprland, jakoolit"
        ;;
esac

cleanup

log "[*] desktop.sh complete — reboot to start $DESKTOP_ENV."
