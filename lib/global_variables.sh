#!/usr/bin/env bash

# ==============================================================================
#  Arch Secure Installer V2 — Global Variables
# ==============================================================================
# lib/global_variables.sh
#  Single source of truth for all shared variables across phases.
#  Sourced by every phase entry point before lib/logging.sh.
#  Variables are added here as phases are designed — never speculatively.
#
#  Conventions:
#  - SA_  prefix — standard variables (logged)
#  - SAS_ prefix — sensitive variables (never logged)

# ------------------------------------------------------------------------------
# Directories
# ------------------------------------------------------------------------------

SA_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
SA_INSTALL_DIR="$SA_BASE_DIR/sa_install"
SA_STATE_DIR="$SA_BASE_DIR/sa_state"
SA_LIB_DIR="$SA_INSTALL_DIR/lib"

# ------------------------------------------------------------------------------
# Files
# ------------------------------------------------------------------------------

SA_LOG_FILE="$SA_STATE_DIR/arch_secure_install.log"
