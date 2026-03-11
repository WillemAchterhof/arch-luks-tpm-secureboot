# Arch Secure Installer — V1

> **Note:** TPM, Secure Boot, and LUKS encryption are mandatory in V1.

An automated Arch Linux installer with LUKS full-disk encryption, Secure Boot, and TPM auto-unlock.

---

## Why I Built This

Two reasons:

1. **Disaster recovery** — reinstalling a fully hardened Arch system from scratch takes hours. This gets me back to a working, secured system as automatically as possible.
2. **Learning** — building this taught me how Arch, LUKS, TPM, and Secure Boot actually work together, rather than just following a wiki.

---

## What It Does

- Prepares the target disk — wipe, partition, and LUKS encryption
- Installs a base Arch system via `pacstrap`
- Builds a Unified Kernel Image (UKI) with `mkinitcpio`
- Creates Secure Boot keys, signs the UKI, and enrolls to Secure Boot via `sbctl`
- On first boot: enrolls TPM for automatic LUKS unlock (PCRs 0+7)
- Installs and configures a desktop environment
- Applies system hardening (firewall, sysctl, module blacklist, AppArmor)

---

## Supported Desktop Environments

- KDE Plasma
- Hyprland (with Waybar, Rofi, TokyoNight theme)
- JaKooLit Hyprland (community rice) — [github.com/JaKooLit](https://github.com/JaKooLit/Arch-Hyprland)

---

## Preparation

### 1. Download the Arch Linux ISO
Get the latest ISO from [archlinux.org](https://archlinux.org/download/).

### 2. Write the ISO to a USB drive
```bash
dd bs=4M if=path/to/archlinux-version-x86_64.iso \
   of=/dev/disk/by-id/usb-My_flash_drive \
   conv=fsync oflag=direct status=progress
```

### 3. Create an installer partition on the same USB
After `dd`, create an additional `ext4` partition in the remaining free space on the USB and copy `arch_secure_install.sh` and the `repo/` folder to it.

---

## Installation

### Phase One — Pre-boot

Boot from the Arch Linux ISO, then:

```bash
# Create a mountpoint and mount the installer partition
mkdir -p /run/sa
mount /dev/sdb3 /run/sa
cd /run/sa

# Run the installer
bash arch_secure_install.sh
```

The installer will:
- Check internet connectivity
- Verify required tools are present
- Check TPM availability
- Load your install profile
- Walk through disk setup, encryption, base install, bootloader, and Secure Boot enrollment

You will be prompted for:
- **LUKS passphrase** — choose a strong one. You will need it until TPM enrollment completes on first boot
- **User password** — your login password

### Phase Two — Post-boot

On first boot the system will automatically:
- Enroll the TPM (binds LUKS unlock to PCRs 0+7)
- Connect to WiFi using saved credentials
- Install the desktop environment
- Apply system hardening

> **Important:** Keep your LUKS passphrase stored safely. You will need it if the TPM seal breaks — for example after a firmware update or Secure Boot key change.

---

## Status

**V1** — functional, tested on physical hardware and KVM VM.
**V2** in development — Python orchestration, YAML profiles, cleaner phase separation.

---

## Disclaimer

This installer wipes the target disk. Always verify the correct disk is selected before running. **Use at your own risk.**

---

## Acknowledgements

- [Ataraxxia](https://github.com/Ataraxxia) — inspiration and reference configs
- [JaKooLit](https://github.com/JaKooLit/Arch-Hyprland) — Hyprland rice and dotfiles
- The Arch Wiki — for making all of this possible
