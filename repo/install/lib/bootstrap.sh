#!/usr/bin/env bash
set -euo pipefail

LIB_DIR="$REPO_ROOT/install/lib"

safe_source() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "[FATAL] Required library missing: $file"
        exit 1
    fi

    source "$file"
}

safe_source "$LIB_DIR/file_paths.sh"
safe_source "$LIB_DIR/logging.sh"
safe_source "$LIB_DIR/state.sh"
safe_source "$LIB_DIR/common.sh"