#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#  file_paths.sh — Central path definitions for the Arch Secure Installer
#  Requires: REPO_ROOT exported by install.sh before sourcing
# ==============================================================================

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing file_paths.sh}"

# ==============================================================================
# CORE FOLDERS
# ==============================================================================

INSTALL_FOLDER="$REPO_ROOT/install"
LIB_FOLDER="$INSTALL_FOLDER/lib"
OUTPUT_FOLDER="$REPO_ROOT/output"

# ==============================================================================
# OUTPUT SUBFOLDERS
# ==============================================================================

LOG_FOLDER="$OUTPUT_FOLDER/logs"
STATE_FOLDER="$OUTPUT_FOLDER/state"

# ==============================================================================
# CREATE OUTPUT DIRECTORIES
# ==============================================================================

mkdir -p \
    "$LOG_FOLDER" \
    "$STATE_FOLDER"
