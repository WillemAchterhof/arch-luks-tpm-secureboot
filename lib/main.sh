#!/usr/bin/env bash

# ==============================================================================
#  Arch Secure Installer V2 —Lib Entry Point
# ==============================================================================
# lib/main_lib.sh
#  Standard bootstrap for every phase.
#  Sources everything a phase needs by default.
#  If a phase needs extras, source lib_*.sh files individually after this.

# ------------------------------------------------------------------------------
# Source
# ------------------------------------------------------------------------------

SA_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"

source "$SA_LIB_DIR/global_variables.sh" \
    || { printf "[FATAL] Could not source global_variables.sh\n"; exit 1; }

source "$SA_LIB_DIR/logging.sh" \
    || { printf "[FATAL] Could not source logging.sh\n"; exit 1; }
