#!usr/bin/env bash
echo "Phase two postboot present."
exec bash "$(dirname "${BASH_SOUCE[0]}")/../phase_three_desktop/main.sh