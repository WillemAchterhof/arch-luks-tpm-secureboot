# ------------------------------------------------------------------------------
# COPYING INSTALL SCRIPTS
# ------------------------------------------------------------------------------

echo "[*] Copying install scripts..."
mkdir -p /mnt/install/configs/system
mkdir -p /mnt/install/configs/shell
mkdir -p /mnt/install/configs/editor
mkdir -p /mnt/install/configs/themes/waybar
mkdir -p /mnt/install/configs/themes/rofi
mkdir -p /mnt/install/configs/themes/alacritty
mkdir -p /mnt/install/configs/themes/hyprland

if [[ "$SCRIPT_BASE" == /* ]]; then
    cp "$SCRIPT_BASE"/part*.sh /mnt/install/
    cp "$SCRIPT_BASE"/configs/system/*          /mnt/install/configs/system/
    cp "$SCRIPT_BASE"/configs/shell/*           /mnt/install/configs/shell/
    cp "$SCRIPT_BASE"/configs/editor/*          /mnt/install/configs/editor/
    cp "$SCRIPT_BASE"/configs/themes/waybar/*   /mnt/install/configs/themes/waybar/
    cp "$SCRIPT_BASE"/configs/themes/rofi/*     /mnt/install/configs/themes/rofi/
    cp "$SCRIPT_BASE"/configs/themes/alacritty/* /mnt/install/configs/themes/alacritty/
    cp "$SCRIPT_BASE"/configs/themes/hyprland/* /mnt/install/configs/themes/hyprland/
else
    # Scripts
    curl -fsSL "$SCRIPT_BASE/part2-chroot.sh"          -o /mnt/install/part2-chroot.sh
    curl -fsSL "$SCRIPT_BASE/part3-secureboot.sh"       -o /mnt/install/part3-secureboot.sh
    curl -fsSL "$SCRIPT_BASE/part4-post-reboot.sh"      -o /mnt/install/part4-post-reboot.sh
    curl -fsSL "$SCRIPT_BASE/part5-user-setup.sh"       -o /mnt/install/part5-user-setup.sh
    curl -fsSL "$SCRIPT_BASE/part6-hyprland.sh"         -o /mnt/install/part6-hyprland.sh

    # System configs
    curl -fsSL "$SCRIPT_BASE/configs/system/99-hardening.conf"   -o /mnt/install/configs/system/99-hardening.conf
    curl -fsSL "$SCRIPT_BASE/configs/system/blacklist.conf"       -o /mnt/install/configs/system/blacklist.conf
    curl -fsSL "$SCRIPT_BASE/configs/system/nftables.conf"        -o /mnt/install/configs/system/nftables.conf
    curl -fsSL "$SCRIPT_BASE/configs/system/NetworkManager.conf"  -o /mnt/install/configs/system/NetworkManager.conf
    curl -fsSL "$SCRIPT_BASE/configs/system/zz-sbctl-uki.hook"    -o /mnt/install/configs/system/zz-sbctl-uki.hook

    # Shell
    curl -fsSL "$SCRIPT_BASE/configs/shell/.zshrc"                -o /mnt/install/configs/shell/.zshrc

    # Editor
    curl -fsSL "$SCRIPT_BASE/configs/editor/init.lua"             -o /mnt/install/configs/editor/init.lua

    # Themes - Waybar
    curl -fsSL "$SCRIPT_BASE/configs/themes/waybar/config.jsonc"  -o /mnt/install/configs/themes/waybar/config.jsonc
    curl -fsSL "$SCRIPT_BASE/configs/themes/waybar/style.css"     -o /mnt/install/configs/themes/waybar/style.css

    # Themes - Rofi
    curl -fsSL "$SCRIPT_BASE/configs/themes/rofi/config.rasi"     -o /mnt/install/configs/themes/rofi/config.rasi
    curl -fsSL "$SCRIPT_BASE/configs/themes/rofi/tokyonight.rasi" -o /mnt/install/configs/themes/rofi/tokyonight.rasi

    # Themes - Alacritty
    curl -fsSL "$SCRIPT_BASE/configs/themes/alacritty/alacritty.toml" -o /mnt/install/configs/themes/alacritty/alacritty.toml

    # Themes - Hyprland
    curl -fsSL "$SCRIPT_BASE/configs/themes/hyprland/hyprland.conf"   -o /mnt/install/configs/themes/hyprland/hyprland.conf
fi

chmod +x /mnt/install/part*.sh
