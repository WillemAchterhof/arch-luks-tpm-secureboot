#!/usr/bin/env bash

# ==============================================================================
#  Arch Secure Installer V2 — Logging
# ==============================================================================
# lib/logging.sh
#  Defines all logging functions used across phases.
#  Requires global_variables.sh to be sourced before this file.
#
#  Functions:
#  - log()           — writes a line to terminal and log file
#  - msg()           — info message
#  - fatal()         — logs fatal error and exits
#  - log_header()    — writes a section header with timestamp
#  - log_variables() — dumps all SA_ variables, skips SAS_

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

log() {
    printf " %s\n" "$1"
    printf " %s\n" "$1" >> "$SA_LOG_FILE"
}

log_silent() {
    printf " %s\n" "$1" >> "$SA_LOG_FILE"
}

msg()   { log "[*] $1"; }

fatal() {
    log "[FATAL] $1"
    exit 1
}

log_header() {
    log_silent "================================================================================"
    log_silent "$1"
    log_silent " $(date '+%Y-%m-%d %H:%M:%S')"
    log_silent "================================================================================"
}

log_variables() {
    log_silent "VARIABLES"
    for var in $(compgen -A variable SA_); do
        [[ "$var" == SAS_* ]] && continue
        log_silent "$(printf " %-20s = %s" "$var" "${!var}")"
    done
    log_silent "================================================================================"
}
