#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# File Path Definitions (Pure Configuration)
# ------------------------------------------------------------------------------

: "${LIB_DIR:?LIB_DIR not set before sourcing file_paths.sh}"

INSTALL_DIR="$(cd "$LIB_DIR/.." && pwd)"
REPO_ROOT="$(cd "$INSTALL_DIR/.." && pwd)"
USB_ROOT="$(cd "$REPO_ROOT/.." && pwd)"

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

# ------------------------------------------------------------------------------
# Export Everything Explicitly
# ------------------------------------------------------------------------------

export INSTALL_DIR
export REPO_ROOT
export USB_ROOT
export OUTPUT_FOLDER
export LOG_FOLDER
export STATE_FOLDER
export PROFILE_FOLDER
export SB_ROOT

export SB_CHOICE_FILE