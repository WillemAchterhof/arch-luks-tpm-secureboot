Acknowledgements:
-----------------
- The Arch Wiki — for making all of this possible
- Ataraxxia — inspiration and reference configs — github.com/Ataraxxia
- JaKooLit — Hyprland rice and dotfiles — github.com/JaKooLit

Arch Secure Installer — V1 (TPM, Secure Boot, Luks, are mandatory)
--------------------------
An automated Arch Linux installer with LUKS encryption, Secure Boot, and TPM auto-unlock.
Why I Built This, two reasons:

Disaster recovery — reinstalling a fully hardened Arch system from scratch takes hours. This gets me back to a working, secured system as automatically as possible.
Learning — building this taught me how Arch, LUKS, TPM, and Secure Boot actually work together, rather than just following a wiki.

What It Does

- Preparing the target disk, for install. (Clean, Format, Luks)
- Installs a base Arch system via pacstrap
- Builds a Unified Kernel Image (UKI) with mkinitcpio
- Creating Secure boot keys, signing the UKI and enrolling to Secure Boot (sbctl)
- On first boot: enroll TPM for auto-unlock (pin unlock)
- Installs and configures a desktop environment
- Applies system hardening (firewall, sysctl, module blacklist, AppArmor)


Supported Desktop Environments

- KDE Plasma
- Hyprland (with Waybar, Rofi, TokyoNight theme)
- JaKooLit Hyprland (community rice) — github.com/JaKooLit


Preperation
 - Download the Arch Linux ISO
 - Create an isntallation USB: dd bs=4M if=path/to/archlinux-version-x86_64.iso of=/dev/disk/by-id/usb-My_flash_drive conv=fsync oflag=direct status=progress
 - Create an extra partition (ext4) on the USB, and copy arch_secure_isntall.sh to there. 


Boot from the Arch Linux ISO

# Mount and copy installer files
mount /dev/sdX3 /mnt/installer
cp -r repo/ arch_secure_install.sh /mnt/installer/
umount /mnt/installer
Installation
Phase One — Pre-boot (runs from Arch ISO)
Boot the Arch ISO, then:
bash# Mount the installer USB partition
mount /dev/sdb3 /mnt/sa
cd /mnt/sa

# Run the installer
sudo bash arch_secure_install.sh
The installer will:

Check internet connectivity
Verify required tools
Check TPM availability
Load your install profile
Walk through disk setup, encryption, base install, bootloader, and Secure Boot

You will be prompted for:

LUKS passphrase — choose a strong one, you will need it until TPM enrollment completes
User password — your login password

Phase Two — Post-boot (runs automatically on first boot)
On first boot the system will automatically:

Enroll the TPM (binds LUKS unlock to PCRs 0+7)
Connect to WiFi using saved credentials
Install the desktop environment
Apply system hardening

After this you will not need the LUKS passphrase for normal boots — TPM handles it automatically.

Keep your LUKS passphrase stored safely. You will need it if the TPM seal breaks (firmware update, Secure Boot key change, etc.)

Install Profile
Create a profile file before running the installer:
bashcp repo/install/configs/install_profile.conf.example output/profile/install_profile.conf
nano output/profile/install_profile.conf
Key settings:
bashINSTALL_HOSTNAME="my-arch"
INSTALL_USERNAME="willem"
INSTALL_DISK="/dev/nvme0n1"
INSTALL_ROOT_FS="ext4"
DESKTOP_ENV="hyprland"       # kde | hyprland | jakoolit
INSTALL_LOCALE="en_US.UTF-8"
INSTALL_TIMEZONE="Europe/Amsterdam"
INSTALL_KEYMAP="us"
Security Features
FeatureDetailsLUKS2 encryptionFull disk encryption, argon2id key derivationSecure BootCustom keys enrolled via sbctlTPM auto-unlockPCRs 0+7 (firmware + Secure Boot state)UKIKernel, initramfs, cmdline signed as single imageAppArmorMAC enforcementnftablesDefault-deny firewall with bogon filteringSysctl hardeningASLR, ptrace restrictions, BPF lockdownModule blacklistThunderbolt, FireWire, legacy hardware


Status
V1 — functional, tested on physical hardware and KVM VM.
V2 in development — Python orchestration, YAML profiles, cleaner phase separation.
Disclaimer
This installer wipes the target disk. Always verify the target disk before running. Use at your own risk.
