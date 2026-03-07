#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — bootloader.sh
#  mkinitcpio config, UKI preset, kernel cmdline, efibootmgr
# ==============================================================================

: "${TARGET_DISK:?TARGET_DISK not set}"
: "${ROOT_FS:?ROOT_FS not set}"
: "${LUKS_UUID:?LUKS_UUID not set}"
: "${EFI_PART:?EFI_PART not set}"

MNT="/mnt"

# ==============================================================================
# EFI PARTITION NUMBER
# ==============================================================================

get_efi_partnum() {
    local partnum
    partnum="${EFI_PART##*[^0-9]}"
    [[ -n "$partnum" ]] || fatal "Cannot detect EFI partition number from: $EFI_PART"
    echo "$partnum"
}

# ==============================================================================
# MKINITCPIO
# ==============================================================================

configure_mkinitcpio() {
    log "[*] Configuring mkinitcpio..."

    # Write installer drop-in instead of patching the base mkinitcpio.conf.
    # Drop-ins in mkinitcpio.conf.d/ are merged at build time.
    mkdir -p "$MNT/etc/mkinitcpio.conf.d"
    cat > "$MNT/etc/mkinitcpio.conf.d/installer.conf" <<'EOF'
HOOKS=(base systemd keyboard autodetect modconf kms microcode block sd-encrypt plymouth filesystems fsck)
COMPRESSION="zstd"
COMPRESSION_OPTIONS="-3"
EOF

    log "[*] mkinitcpio configured."
}

# ==============================================================================
# KERNEL CMDLINE
# ==============================================================================

configure_cmdline() {
    log "[*] Writing kernel cmdline..."

    mkdir -p "$MNT/etc/kernel"

    # NOTE: rd.luks.options=tpm2-device=auto is written now but TPM enrollment
    # happens in tpm.sh during postboot. On first boot the TPM binding does not
    # exist yet — the system will fall back to password unlock. This is expected.
    cat > "$MNT/etc/kernel/cmdline" <<EOF
rd.luks.name=$LUKS_UUID=cryptroot rd.luks.options=tpm2-device=auto,tpm2-pcrs=0+7+11 root=/dev/mapper/cryptroot rootfstype=$ROOT_FS rw lsm=lockdown,yama,apparmor,bpf apparmor=1 lockdown=confidentiality quiet splash
EOF

    log "[*] Kernel cmdline written."
    log "    $(cat "$MNT/etc/kernel/cmdline")"
}

# ==============================================================================
# UKI PRESET
# ==============================================================================

configure_uki_preset() {
    log "[*] Configuring UKI preset..."

    mkdir -p "$MNT/boot/EFI/Linux"

    cat > "$MNT/etc/mkinitcpio.d/linux.preset" <<'EOF'
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default')

default_uki="/boot/EFI/Linux/arch-linux.efi"
default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"
EOF

    log "[*] UKI preset configured."
}

# ==============================================================================
# BUILD UKI
# ==============================================================================

build_uki() {
    log "[*] Installing systemd-ukify..."
    arch-chroot "$MNT" pacman -S --noconfirm --needed systemd-ukify

    log "[*] Building UKI with mkinitcpio..."
    arch-chroot "$MNT" mkinitcpio -p linux \
        || fatal "mkinitcpio failed."

    [[ -f "$MNT/boot/EFI/Linux/arch-linux.efi" ]] \
        || fatal "UKI not found after mkinitcpio — check preset and ukify."

    log "[*] UKI built: /boot/EFI/Linux/arch-linux.efi"
}

# ==============================================================================
# EFIBOOTMGR
# ==============================================================================

configure_efibootmgr() {
    log "[*] Configuring EFI boot entries..."

    local efi_partnum
    efi_partnum="$(get_efi_partnum)"

    # NOTE: This intentionally clears ALL existing EFI boot entries,
    # including vendor firmware entries, recovery partitions, and memory tests.
    # Goal: produce a clean, minimal boot order with only Arch Linux.
    # If you need to preserve firmware entries, do so manually after install.
    log "[*] Clearing ALL existing EFI boot entries..."
    local entries
    entries=$(efibootmgr | awk '/Boot[0-9A-F]{4}\*?/ {print $1}' \
        | grep -oP '[0-9A-F]{4}') || true

    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        log "    Removing entry: Boot$entry"
        efibootmgr -b "$entry" -B || log "[!] Failed to remove entry: $entry"
    done <<< "$entries"

    # Create Arch Linux entry
    log "[*] Creating Arch Linux boot entry..."
    efibootmgr --create \
        --disk "$TARGET_DISK" \
        --part "$efi_partnum" \
        --label "Arch Linux" \
        --loader '\EFI\Linux\arch-linux.efi' \
        --unicode

    # Set boot order
    local new_entry
    new_entry=$(efibootmgr | awk '/Arch Linux/ {print $1}' \
        | grep -oP '[0-9A-F]{4}' | head -1)

    [[ -n "$new_entry" ]] || fatal "Failed to find new EFI boot entry."

    efibootmgr -o "$new_entry"
    log "[*] Boot order set to: Boot$new_entry"

    log "[*] Current EFI entries:"
    efibootmgr
}

# ==============================================================================
# MAIN
# ==============================================================================

configure_mkinitcpio
configure_cmdline
configure_uki_preset
build_uki
configure_efibootmgr

log "[*] bootloader.sh complete."
