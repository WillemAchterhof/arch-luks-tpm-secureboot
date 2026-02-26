
#!/usr/bin/env bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$LIB_DIR/logging.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/common.sh"
