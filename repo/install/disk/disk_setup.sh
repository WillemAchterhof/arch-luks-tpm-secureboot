#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — disk/disk_setup.sh
#  Wipe, partition, LUKS2, ext4/btrfs, mount
# ==============================================================================

: "${TARGET_DISK:?TARGET_DISK not set}"
: "${LUKS_KEY_FILE:?LUKS_KEY_FILE not set}"

[[ -b "$TARGET_DISK" ]] || fatal "Target disk does not exist: $TARGET_DISK"

CRYPT_NAME="cryptroot"
MNT="/mnt"
ROOT_FS="${ROOT_FS:-ext4}"

# ==============================================================================
# CLEANUP
# ==============================================================================

cleanup() {
    mountpoint -q "$MNT/boot" 2>/dev/null && umount "$MNT/boot"   || true
    mountpoint -q "$MNT"      2>/dev/null && umount -R "$MNT"     || true
    cryptsetup status "$CRYPT_NAME" >/dev/null 2>&1 \
        && cryptsetup close "$CRYPT_NAME" || true
}
trap cleanup EXIT

# ==============================================================================
# PARTITION NAMING
# ==============================================================================

get_partition() {
    local disk="$1" num="$2"
    case "$disk" in
        /dev/nvme[0-9]*n[0-9]*|/dev/mmcblk[0-9]*)
            echo "${disk}p${num}" ;;
        *)
            echo "${disk}${num}" ;;
    esac
}

# ==============================================================================
# INTERACTIVE OPTIONS
# ==============================================================================

select_wipe_mode() {
    if [[ -n "${DISK_WIPE_MODE:-}" ]]; then
        log "[*] Wipe mode from profile: $DISK_WIPE_MODE"
        return
    fi

    echo
    echo "================================================="
    echo "   Disk Wipe Mode"
    echo "================================================="
    echo
    echo "  [1] Quick wipe       wipefs + sgdisk zap  (default)"
    echo "  [2] Overwrite zeros  dd if=/dev/zero"
    echo "  [3] Overwrite random dd if=/dev/urandom"
    echo

    read -rp "  Select [1]: " choice
    choice="${choice:-1}"

    case "$choice" in
        1) DISK_WIPE_MODE="quick" ;;
        2) DISK_WIPE_MODE="zeros" ;;
        3) DISK_WIPE_MODE="random" ;;
        *) fatal "Invalid wipe mode selection: $choice" ;;
    esac

    log "[*] Wipe mode selected: $DISK_WIPE_MODE"
}

select_efi_size() {
    if [[ -n "${EFI_SIZE:-}" ]]; then
        log "[*] EFI size from profile: $EFI_SIZE"
        return
    fi

    echo
    echo "================================================="
    echo "   EFI Partition Size"
    echo "================================================="
    echo
    echo "  [1] 512MiB (default)"
    echo "  [2] 1GiB"
    echo

    read -rp "  Select [1]: " choice
    choice="${choice:-1}"

    case "$choice" in
        1) EFI_SIZE="512MiB" ;;
        2) EFI_SIZE="1GiB" ;;
        *) fatal "Invalid EFI size selection: $choice" ;;
    esac

    log "[*] EFI size selected: $EFI_SIZE"
}

confirm_disk_destruction() {
    echo
    echo "================================================="
    echo "   ⚠  CONFIRM TARGET DISK"
    echo "================================================="
    echo
    echo "  Selected disk: $TARGET_DISK"
    echo
    echo "  Type the device path exactly to confirm:"
    echo

    local input
    read -rp "  > " input
    [[ "$input" == "$TARGET_DISK" ]] \
        || fatal "Disk path mismatch — aborting."

    echo
    echo "================================================="
    echo "   ⚠  LAST CHANCE — DESTRUCTIVE OPERATION"
    echo "================================================="
    echo
    echo "  ALL DATA ON $TARGET_DISK WILL BE PERMANENTLY LOST."
    echo
    echo "  Wipe mode: $DISK_WIPE_MODE"
    echo

    local confirm
    read -rp "  Type WIPE to continue: " confirm
    [[ "$confirm" == "WIPE" ]] || fatal "Disk wipe not confirmed — aborting."
}

# ==============================================================================
# PRE-FLIGHT: CLOSE STALE LUKS + FLUSH KERNEL
# ==============================================================================

preflight_disk() {
    # Close stale LUKS mapping from previous failed run
    if cryptsetup status "$CRYPT_NAME" >/dev/null 2>&1; then
        log "[*] Closing stale LUKS mapping: $CRYPT_NAME"
        cryptsetup close "$CRYPT_NAME" \
            || fatal "Failed to close stale LUKS mapping — reboot and retry."
    fi

    # Unmount stale mounts under /mnt
    if mountpoint -q "$MNT"; then
        log "[*] Unmounting stale mounts under $MNT"
        umount -R "$MNT" || fatal "Failed to unmount $MNT — reboot and retry."
    fi

    # Flush kernel partition table cache
    partprobe "$TARGET_DISK" 2>/dev/null || true
    udevadm settle

    log "[*] Pre-flight disk checks complete."
}

# ==============================================================================
# WIPE
# ==============================================================================

wipe_disk() {
    log "[*] Wiping disk: $TARGET_DISK (mode: $DISK_WIPE_MODE)"

    case "$DISK_WIPE_MODE" in
        quick)
            wipefs -af "$TARGET_DISK"
            sgdisk --zap-all "$TARGET_DISK"
            ;;
        zeros)
            log "[*] Overwriting with zeros — this may take a while..."
            dd if=/dev/zero of="$TARGET_DISK" bs=4M status=progress conv=fsync \
                || fatal "dd (zeros) failed — aborting."
            wipefs -af "$TARGET_DISK"
            sgdisk --zap-all "$TARGET_DISK"
            ;;
        random)
            log "[*] Overwriting with random data — this will take a long time..."
            dd if=/dev/urandom of="$TARGET_DISK" bs=4M status=progress conv=fsync \
                || fatal "dd (random) failed — aborting."
            wipefs -af "$TARGET_DISK"
            sgdisk --zap-all "$TARGET_DISK"
            ;;
        *)
            fatal "Unknown wipe mode: $DISK_WIPE_MODE"
            ;;
    esac

    partprobe "$TARGET_DISK"
    udevadm settle
    log "[*] Disk wiped."
}

# ==============================================================================
# PARTITION
# ==============================================================================

create_partitions() {
    log "[*] Creating GPT layout (EFI: $EFI_SIZE)"

    sgdisk --new=1:0:+"$EFI_SIZE" --typecode=1:EF00 --change-name=1:"EFI"       "$TARGET_DISK"
    sgdisk --new=2:0:0            --typecode=2:8309  --change-name=2:"cryptroot" "$TARGET_DISK"

    partprobe "$TARGET_DISK"
    udevadm settle
    sleep 1

    log "[*] Partitions created."
}

# ==============================================================================
# LUKS2
# ==============================================================================

detect_argon_memory() {
    local total_mem_kb mem
    total_mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    mem=$(( total_mem_kb / 4 ))
    mem=$(( mem > 1048576 ? 1048576 : mem ))  # cap at 1GiB
    mem=$(( mem <  131072 ?  131072 : mem ))  # floor at 128MiB
    echo "$mem"
}

setup_luks() {
    local crypt_part argon_mem luks_pass
    crypt_part="$(get_partition "$TARGET_DISK" 2)"

    log "[*] Generating alphanumeric LUKS recovery key..."
    luks_pass="$(head -c 64 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 64)"

    printf '%s\n' "$luks_pass" > "$LUKS_KEY_FILE"
    chmod 600 "$LUKS_KEY_FILE"
    log "[*] LUKS key saved to: $LUKS_KEY_FILE"

    log "[*] Formatting LUKS2 on $crypt_part..."
    argon_mem="$(detect_argon_memory)"

    printf '%s' "$luks_pass" | cryptsetup luksFormat \
        --batch-mode \
        --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha512 \
        --pbkdf argon2id \
        --pbkdf-memory "$argon_mem" \
        --iter-time 3000 \
        --key-file - \
        "$crypt_part"

    log "[*] Opening LUKS container..."
    printf '%s' "$luks_pass" | cryptsetup open \
        --key-file - \
        "$crypt_part" "$CRYPT_NAME"

    # luks_pass is a local variable — it goes out of scope on function return.
    # No unset needed; it is never exported to the environment.
    log "[*] LUKS setup complete."
}

# ==============================================================================
# FILESYSTEMS
# ==============================================================================

create_filesystems() {
    local efi_part
    efi_part="$(get_partition "$TARGET_DISK" 1)"

    log "[*] Formatting EFI: $efi_part"
    mkfs.fat -F32 -n ESP "$efi_part"

    case "$ROOT_FS" in
        btrfs)
            log "[*] Formatting root (btrfs)"
            mkfs.btrfs -L archroot "/dev/mapper/$CRYPT_NAME"
            ;;
        ext4|*)
            log "[*] Formatting root (ext4)"
            mkfs.ext4 -L archroot "/dev/mapper/$CRYPT_NAME"
            ;;
    esac

    log "[*] Filesystems created."
}

# ==============================================================================
# MOUNT
# ==============================================================================

mount_filesystems() {
    local efi_part
    efi_part="$(get_partition "$TARGET_DISK" 1)"

    log "[*] Mounting root..."
    mount -o defaults,noatime "/dev/mapper/$CRYPT_NAME" "$MNT"

    mkdir -p "$MNT/boot"
    log "[*] Mounting EFI..."
    mount "$efi_part" "$MNT/boot"

    log "[*] Filesystems mounted."
}

# ==============================================================================
# EXPORT INFO
# ==============================================================================

export_disk_info() {
    EFI_PART="$(get_partition "$TARGET_DISK" 1)"
    ROOT_PART="$(get_partition "$TARGET_DISK" 2)"

    ROOT_UUID="$(blkid -s UUID -o value "/dev/mapper/$CRYPT_NAME")" \
        || fatal "Failed to read ROOT_UUID"
    EFI_UUID="$(blkid -s UUID -o value "$EFI_PART")" \
        || fatal "Failed to read EFI_UUID"
    LUKS_UUID="$(blkid -s UUID -o value "$ROOT_PART")" \
        || fatal "Failed to read LUKS_UUID"

    export CRYPT_NAME MNT ROOT_FS EFI_SIZE
    export EFI_PART ROOT_PART ROOT_UUID EFI_UUID LUKS_UUID

    log "[*] Disk info exported."
}

# ==============================================================================
# MAIN
# ==============================================================================

preflight_disk
select_wipe_mode
select_efi_size
confirm_disk_destruction

wipe_disk
create_partitions
setup_luks
create_filesystems
mount_filesystems
export_disk_info

log "[*] disk_setup.sh complete."
