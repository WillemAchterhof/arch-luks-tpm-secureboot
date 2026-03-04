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

deploy_config() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
}

# ==============================================================================
# SHARED — AUDIO
# ==============================================================================

install_audio() {
    log "[*] Installing audio stack..."
    install_pkgs \
        pipewire \
        pipewire-alsa \
        pipewire-pulse \
        pipewire-jack \
        wireplumber

    systemctl --user enable pipewire pipewire-pulse wireplumber
    log "[*] Audio stack installed."
}

# ==============================================================================
# SHARED — SHELL
# ==============================================================================

install_shell() {
    log "[*] Installing zsh..."
    install_pkgs \
        zsh \
        zsh-completions \
        zsh-autosuggestions

    # Set zsh as default shell
    sudo chsh -s /usr/bin/zsh "$USERNAME"
    log "[*] zsh set as default shell."
}

# ==============================================================================
# SHARED — FONTS
# ==============================================================================

install_fonts() {
    log "[*] Installing fonts..."
    install_pkgs \
        ttf-dejavu \
        ttf-liberation \
        noto-fonts \
        noto-fonts-cjk \
        noto-fonts-emoji \
        ttf-jetbrains-mono-nerd

    log "[*] Fonts installed."
}

# ==============================================================================
# SHARED — TOOLS
# ==============================================================================

install_tools() {
    log "[*] Installing common tools..."
    install_pkgs \
        alacritty \
        neovim \
        btop \
        fastfetch \
        git \
        reflector \
        man-db \
        xdg-user-dirs \
        xdg-utils \
        unzip \
        p7zip \
        hunspell \
        hunspell-en_us \
        hunspell-nl

    xdg-user-dirs-update
    log "[*] Common tools installed."
}

# ==============================================================================
# SHARED — EXTRA PACKAGES
# ==============================================================================

install_extra_packages() {
    [[ -z "${EXTRA_PACKAGES:-}" ]] && return 0

    log "[*] Installing extra packages..."
    # shellcheck disable=SC2086
    install_pkgs $EXTRA_PACKAGES
    log "[*] Extra packages installed."
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
# SHARED — ENVIRONMENT
# ==============================================================================

configure_environment() {
    log "[*] Writing /etc/environment..."

    cat > /etc/environment <<EOF
EDITOR=nvim
VISUAL=nvim
TERMINAL=alacritty
EOF

    # Wayland vars — added for both KDE and Hyprland
    if [[ "$DESKTOP_ENV" == "hyprland" ]]; then
        cat >> /etc/environment <<'EOF'
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
SDL_VIDEODRIVER=wayland
EOF
    fi

    log "[*] Environment configured."
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

    log "[*] Enabling SDDM..."
    sudo systemctl enable sddm

    # Add libvirt group if package installed
    if pacman -Q libvirt &>/dev/null; then
        sudo usermod -aG libvirt "$USERNAME"
        log "[*] Added $USERNAME to libvirt group."
    fi

    log "[*] KDE installed."
}

# ==============================================================================
# HYPRLAND
# ==============================================================================

install_hyprland() {
    log "[*] Installing Hyprland..."

    install_pkgs \
        hyprland \
        hyprlock \
        hypridle \
        hyprpaper \
        xdg-desktop-portal-hyprland \
        waybar \
        rofi-wayland \
        dunst \
        polkit-kde-agent \
        qt5-wayland \
        qt6-wayland \
        grim \
        slurp \
        wl-clipboard \
        brightnessctl \
        playerctl \
        nwg-look \
        sddm

    log "[*] Enabling SDDM..."
    sudo systemctl enable sddm

    # Add libvirt group if package installed
    if pacman -Q libvirt &>/dev/null; then
        sudo usermod -aG libvirt "$USERNAME"
        log "[*] Added $USERNAME to libvirt group."
    fi

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
        && deploy_config "$CONFIGS_DIR/hyprland/hyprland.conf" "$hypr_cfg/hyprland.conf"

    [[ -f "$CONFIGS_DIR/hyprland/hyprlock.conf" ]] \
        && deploy_config "$CONFIGS_DIR/hyprland/hyprlock.conf" "$hypr_cfg/hyprlock.conf"

    [[ -f "$CONFIGS_DIR/hyprland/themes/tokyonight.conf" ]] \
        && deploy_config "$CONFIGS_DIR/hyprland/themes/tokyonight.conf" \
                         "$hypr_cfg/themes/tokyonight.conf"

    # Waybar
    [[ -f "$CONFIGS_DIR/waybar/config.jsonc" ]] \
        && deploy_config "$CONFIGS_DIR/waybar/config.jsonc" "$waybar_cfg/config.jsonc"

    [[ -f "$CONFIGS_DIR/waybar/style.css" ]] \
        && deploy_config "$CONFIGS_DIR/waybar/style.css" "$waybar_cfg/style.css"

    # Rofi
    [[ -f "$CONFIGS_DIR/rofi/config.rasi" ]] \
        && deploy_config "$CONFIGS_DIR/rofi/config.rasi" "$rofi_cfg/config.rasi"

    [[ -f "$CONFIGS_DIR/rofi/tokyonight.rasi" ]] \
        && deploy_config "$CONFIGS_DIR/rofi/tokyonight.rasi" "$rofi_cfg/tokyonight.rasi"

    # Fix ownership
    chown -R "$USERNAME:$USERNAME" \
        "$hypr_cfg" \
        "$waybar_cfg" \
        "$rofi_cfg"

    log "[*] Hyprland configs deployed."
}

# ==============================================================================
# MAIN
# ==============================================================================

log "[*] Desktop install starting — environment: $DESKTOP_ENV"

# Enable multilib in case it isn't already
sudo sed -i \
    -e 's/^#Color/Color/' \
    -e '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' \
    /etc/pacman.conf
sudo pacman -Sy --noconfirm

install_audio
install_shell
install_fonts
install_tools
install_extra_packages
configure_environment
deploy_alacritty_config

case "${DESKTOP_ENV,,}" in
    kde)
        install_kde
        ;;
    hyprland)
        install_hyprland
        ;;
    *)
        fatal "Unknown DESKTOP_ENV: $DESKTOP_ENV — supported: kde, hyprland"
        ;;
esac

log "[*] desktop.sh complete — reboot to start $DESKTOP_ENV."
