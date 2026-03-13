#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  Arch Secure Installer V2
# ==============================================================================
# arch_secure_install.sh
#  Entry point for the installer. All functions below are local to this script.
#  Responsibilities:
#  - Verify root access
#  - Initialize logging
#  - Verify internet connectivity
#  - Ensure required packages are available
#  - Clone a clean copy of the installer repository
#  - Verify repository structure before handoff

# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

# GitHub 
SA_REPO_URL="https://github.com/WillemAchterhof/arch-luks-tpm-secureboot.git"
SA_REPO_BRANCH="v2"

# Local
SA_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SA_INTSALL_DIR="$SA_BASE_DIR/arch-secure"

# Logging
SA_LOG_FILE="$SA_INSTALL_DIR/output/arch-secure-install.log"
mkdir -p "$(dirname "$SA_LOG_FILE")"
: > "$SA_LOG_FILE"

# ------------------------------------------------------------------------------
# Helper functions (local to this script)
# ------------------------------------------------------------------------------

# Writes a section header with timestamp to the log file.
log_header() {
    printf "================================================================================\n" >> "$SA_LOG_FILE"
    printf " %s\n" "$1"                                                                         >> "$SA_LOG_FILE"
    printf " %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"                                               >> "$SA_LOG_FILE"
    printf "================================================================================\n" >> "$SA_LOG_FILE"
}

# Writes all SA_ variables to the log file. Skips SAS_ (sensitive) variables.
log_variables () {
    printf "VARIABLES\n" >> "$SA_LOG_FILE"
    while IFS='=' read -r name value; do
        [[ "$name" == SAS_* ]] && continue
        printf " %-20s = %s\n" "$name" "$value" >> "$SA_LOG_FILE"
    done < <(declare -p | grep "^declare -- SA_" | sed 's/declare -- //' | sed 's/"//g')
    printf "================================================================================\n" >> "$SA_LOG_FILE"
}

# Prints a message to terminal and log file.
msg()   { 
    printf "\n[*] %s\n\n" "$1"
    printf "[*] %s\n" "$1" >> "$SA_LOG_FILE"
}

# Prints a fatal error to terminal and log file, then exits.
fatal() { 
    printf "\n[FATAL] %s\n\n" "$1"
    printf "[FATAL] %s\n" "$1" >> "$SA_LOG_FILE"
    exit 1
}

# Ensures the script is running as root.
check_root() {
    if [[ $EUID -ne 0 ]]; then
        fatal "Must be run as root. Use: sudo bash arch_secure_install.sh"
    fi
}

# Verifies internet connectivity. Prints iwctl instructions if not connected.
check_internet() {
    if ! curl -s --fail --max-time 5 https://archlinux.org -o /dev/null; then
        printf "\n[FATAL] No internet connection detected.\n" 
        printf "[FATAL] No internet connection detected.\n" >> "$SA_LOG_FILE"
        printf "        Connect via WiFi using iwctl\n"
        printf "        -----------------------------\n"
        printf "        iwctl device list\n"
        printf "        iwctl station <adapter> scan\n"
        printf "        iwctl station <adapter> get-networks\n"
        printf "        iwctl station <adapter> connect <SSID>\n"
        printf "        ---------------------------------------------\n"
        printf "        Then re-run: bash arch_secure_install.sh\n\n"
        exit 1
    fi
    msg "Internet connection verified."
}

# Verifies required packages are installed. Installs missing ones via pacman.
check_packages() {
    local required=(
        git
        curl
    )

    for pkg in "${required[@]}"; do
        if command -v "$pkg" >/dev/null 2>&1; then
            printf " [installed] %s\n" "$pkg"
        else
            printf " [installing] %s\n" "$pkg"
            pacman -Sy --noconfirm "$pkg" \
                || fatal "Failed to install: $pkg"
            printf " [installed] %s\n" "$pkg"
        fi
    done
}

# Removes any previous clone and pulls a clean copy from GitHub.
sync_repo() {
    if [[ -d "$SA_INTSALL_DIR" ]]; then
        msg "Previous repo found - removing."
        rm -rf "$SA_INTSALL_DIR" \
            || fatal "Failed to remove previous repo: $SA_INTSALL_DIR"
    fi

    msg "Cloning repository..."
    git clone --branch "$SA_REPO_BRANCH" "$SA_REPO_URL" "$SA_INTSALL_DIR" \
        || fatal "Failed to clone repository."

    msg "Repository synced."
}

# Verifies the expected folder structure exists after cloning.
verify_repo() {
    local required=(
        "phase_one_preboot"
        "phase_two_postboot"
        "phase_three_desktop"
        "phase_four_software"
        "lib"
        "configs"
    )

    for item in "${required[@]}"; do
        if [[ ! -d "$SA_INTSALL_DIR/$item" ]]; then
            fatal "Repository structure invalid - missing:  $item"
        fi
    done

    msg "Repository structure verified."
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
# Execution order matters — each step depends on the previous one succeeding.
log_header "BOOTSTRAP"
log_variables
check_root
check_internet
check_packages
sync_repo
verify_repo

# Hand off to phase one.
exec bash "$SA_INTSALL_DIR/phase_one_preboot/main.sh"
