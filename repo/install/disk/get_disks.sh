#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Secure Installer — disk/get_disks.sh
#  Presents available disks, warns about USB, exports TARGET_DISK
# ==============================================================================

: "${USB_ROOT:?USB_ROOT not set}"

# ==============================================================================
# IDENTIFY USB DEVICE
# ==============================================================================

get_usb_device() {
    local usb_dev=""
    usb_dev=$(df "$USB_ROOT" 2>/dev/null | awk 'NR==2 {print $1}') || true

    if [[ -z "$usb_dev" ]]; then
        log "[!] Could not detect USB installer device."
        echo ""
        return
    fi

    # NVMe: /dev/nvme0n1p1 → /dev/nvme0n1
    if [[ "$usb_dev" =~ ^(/dev/nvme[0-9]+n[0-9]+)p[0-9]+$ ]]; then
        echo "${BASH_REMATCH[1]}"

    # MMC: /dev/mmcblk0p1 → /dev/mmcblk0
    elif [[ "$usb_dev" =~ ^(/dev/mmcblk[0-9]+)p[0-9]+$ ]]; then
        echo "${BASH_REMATCH[1]}"

    # SATA/USB: /dev/sda1 → /dev/sda
    elif [[ "$usb_dev" =~ ^(/dev/[a-z]+)[0-9]+$ ]]; then
        echo "${BASH_REMATCH[1]}"

    else
        echo "$usb_dev"
    fi
}

# ==============================================================================
# VALIDATE DISK
# ==============================================================================

validate_disk() {
    local disk="$1"

    # Must be a block device
    [[ -b "$disk" ]] \
        || fatal "Not a valid block device: $disk"

    # Must not be a loop device
    [[ "$disk" == /dev/loop* ]] \
        && fatal "Loop devices cannot be selected as target: $disk"

    # Must be a whole disk, not a partition
    local type
    type=$(lsblk -d -no TYPE "$disk" 2>/dev/null) \
        || fatal "Cannot inspect disk: $disk"

    [[ "$type" == "disk" ]] \
        || fatal "Not a whole disk (partition selected?): $disk"

    # Must not have any mounted partitions
    # grep -q '[^[:space:]]' avoids false positives from blank lsblk output lines
    if lsblk -nr -o MOUNTPOINT "$disk" | grep -q '[^[:space:]]'; then
        fatal "Disk or one of its partitions is mounted: $disk"
    fi
}

# ==============================================================================
# PRESENT DISKS
# ==============================================================================

present_disks() {
    local usb_device="$1"

    echo
    echo "================================================="
    echo "   Available Disks"
    echo "================================================="
    echo

    # Parse lsblk JSON to avoid MODEL column splitting on spaces
    while IFS= read -r line; do
        local name size model dev marker

        name=$(  echo "$line" | awk -F'"' '/\"name\"/  {print $4}')
        size=$(  echo "$line" | awk -F'"' '/\"size\"/  {print $4}')
        model=$( echo "$line" | awk -F'"' '/\"model\"/ {print $4}')

        [[ -z "$name" ]] && continue

        dev="/dev/$name"

        # Skip loop devices
        [[ "$dev" == /dev/loop* ]] && continue

        marker=""
        [[ -n "$usb_device" && "$dev" == "$usb_device" ]] && \
            marker="  ⚠  USB installer — do not select"

        printf "  %-12s  %-8s  %s%s\n" "$dev" "$size" "${model:--}" "$marker"

    done < <(lsblk -d -o NAME,SIZE,MODEL --json 2>/dev/null \
             | awk '/\{/{p=1} p{print}')

    echo
}

# ==============================================================================
# SELECT DISK
# ==============================================================================

select_disk() {
    local usb_device="$1"

    while true; do
        read -rp "  Enter target disk (e.g. /dev/nvme0n1): " TARGET_DISK

        # Trim whitespace
        TARGET_DISK="${TARGET_DISK//[[:space:]]/}"

        # Basic check
        [[ -b "$TARGET_DISK" ]] || {
            log "[!] Not a valid block device: $TARGET_DISK"
            continue
        }

        # USB self-destruction warning
        if [[ -n "$usb_device" && "$TARGET_DISK" == "$usb_device" ]]; then
            echo
            echo "  ⚠  WARNING: This is the USB installer disk."
            echo "     Selecting it will destroy the installer."
            echo
            read -rp "  Are you sure? Type YES to continue: " confirm
            [[ "$confirm" == "YES" ]] || continue
        fi

        validate_disk "$TARGET_DISK" && break
    done

    export TARGET_DISK
    log "[*] Target disk selected: $TARGET_DISK"
}

# ==============================================================================
# MAIN
# ==============================================================================

usb_device="$(get_usb_device)"
log "[*] USB installer device detected as: ${usb_device:-unknown}"

if [[ -n "${TARGET_DISK:-}" ]]; then
    TARGET_DISK="${TARGET_DISK//[[:space:]]/}"
    validate_disk "$TARGET_DISK"

    # Profile-supplied disk is used without interactive confirmation.
    # USB match is logged as a warning but not fatal — intentional for automation.
    if [[ -n "$usb_device" && "$TARGET_DISK" == "$usb_device" ]]; then
        log "[!] WARNING: Profile TARGET_DISK matches USB installer device."
    fi

    log "[*] Using profile disk: $TARGET_DISK"
    export TARGET_DISK
else
    present_disks "$usb_device"
    select_disk "$usb_device"
fi
