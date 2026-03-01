#!/usr/bin/env bash
set -euo pipefail

log() {
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
        | tee -a "$LOG_FOLDER/install.log"
}

fatal() {
    log "[FATAL] $*"
    exit 1
}
