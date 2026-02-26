#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/home/willem/tmp/installer.log"

log() {
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
        | tee -a "$LOG_FILE"
}
