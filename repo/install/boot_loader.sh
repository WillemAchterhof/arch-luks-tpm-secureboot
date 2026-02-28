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
    lsblk -no PARTNUM "$EFI_PART" \
        || fatal "Cannot detect EFI partition number from: $EFI_PART"
}

# ==============================================================================
# MKINITCPIO
# ==============================================================================

configure_mkinitcpio() {
    log "[*] Configuring mkinitcpio..."

    arch-chroot "$MNT" sed -i \
        's/^BINARIES=.*/BINARIES=()/' \
        /etc/mkinitcpio.conf

    arch-chroot "$MNT" sed -i \
        's|^HOOKS=.*|HOOKS=(base systemd keyboard autodetect modconf kms microcode block sd-encrypt filesystems fsck)|' \
        /etc/mkinitcpio.conf

    arch-chroot "$MNT" sed -i \
        's|^#*COMPRESSION=.*|COMPRESSION="zstd"|' \
        /etc/mkinitcpio.conf

    arch-chroot "$MNT" sed -i \
        's|^#*COMPRESSION_OPTIONS=.*|COMPRESSION_OPTIONS="-3"|' \
        /etc/mkinitcpio.conf

    log "[*] mkinitcpio configured."
}

# ==============================================================================
# KERNEL CMDLINE
# ==============================================================================

configure_cmdline() {
    log "[*] Writing kernel cmdline..."

    mkdir -p "$MNT/etc/kernel"

    cat > "$MNT/etc/kernel/cmdline" <<EOF
rd.luks.name=$LUKS_UUID=cryptroot rd.luks.options=tpm2-device=auto,tpm2-pcrs=0+7 root=/dev/mapper/cryptroot rootfstype=$ROOT_FS rw lsm=lockdown,yama,apparmor,bpf apparmor=1 lockdown=confidentiality quiet
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
PRESETS=('default')
ALL_kver="/boot/vmlinuz-linux"
default_uki="/boot/EFI/Linux/arch-linux.efi"
EOF

    log "[*] UKI preset configured."
}

# ==============================================================================
# BUILD UKI
# ==============================================================================

build_uki() {
    log "[*] Building UKI with mkinitcpio..."
    arch-chroot "$MNT" mkinitcpio -P
    log "[*] UKI built."
}

# ==============================================================================
# EFIBOOTMGR
# ==============================================================================

configure_efibootmgr() {
    log "[*] Configuring EFI boot entries..."

    local efi_partnum
    efi_partnum="$(get_efi_partnum)"

    # Clear all existing boot entries
    log "[*] Clearing existing EFI boot entries..."
    efibootmgr | awk '/Boot[0-9A-F]{4}\*?/ {print $1}' \
        | grep -oP '[0-9A-F]{4}' \
        | while read -r entry; do
            log "    Removing entry: $entry"
            efibootmgr -b "$entry" -B
        done

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
    log "[*] Boot order set to: $new_entry"

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