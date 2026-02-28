#!/usr/bin/env bash
# ==============================================================================
#  Arch Secure Installer — file_paths.sh
#  Pure configuration — no side effects, no logic
# ==============================================================================

: "${LIB_DIR:?LIB_DIR not set before sourcing file_paths.sh}"

# ------------------------------------------------------------------------------
# Directory Tree
# ------------------------------------------------------------------------------

INSTALL_ROOT="$(cd "$LIB_DIR/.." && pwd)"
REPO_ROOT="$(cd "$INSTALL_ROOT/.." && pwd)"
USB_ROOT="$(cd "$REPO_ROOT/.." && pwd)"

# ------------------------------------------------------------------------------
# Install Subfolders
# ------------------------------------------------------------------------------

DISK_FOLDER="$INSTALL_ROOT/disk"
PROFILES_DIR="$INSTALL_ROOT/profiles"
CONFIGS_DIR="$INSTALL_ROOT/configs"

# ------------------------------------------------------------------------------
# Output Folders
# ------------------------------------------------------------------------------

OUTPUT_FOLDER="$USB_ROOT/output"
LOG_FOLDER="$OUTPUT_FOLDER/log"
STATE_FOLDER="$OUTPUT_FOLDER/state"
PROFILE_FOLDER="$OUTPUT_FOLDER/profile"
SB_ROOT="$OUTPUT_FOLDER/secureboot"

# ------------------------------------------------------------------------------
# File Paths
# ------------------------------------------------------------------------------

SB_CHOICE_FILE="$SB_ROOT/choice"
LUKS_KEY_FILE="$OUTPUT_FOLDER/luks.key"

# ------------------------------------------------------------------------------
# Export Everything Explicitly
# ------------------------------------------------------------------------------

export INSTALL_ROOT
export REPO_ROOT
export USB_ROOT
export DISK_FOLDER
export PROFILES_DIR
export CONFIGS_DIR
export OUTPUT_FOLDER
export LOG_FOLDER
export STATE_FOLDER
export PROFILE_FOLDER
export SB_ROOT
export SB_CHOICE_FILE
export LUKS_KEY_FILE