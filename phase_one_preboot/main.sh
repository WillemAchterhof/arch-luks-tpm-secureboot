#!usr/bin/env bash
echo "Phase one preboot present."
exec bash "$(dirname "${BASH_SOUCE[0]}")/../phase_two_postboot/main.sh"
exec bash "$(dirname "${BASH_SOUCE[0]}")/../phase_three_desktop/main.sh"
exec bash "$(dirname "${BASH_SOUCE[0]}")/../phase_four_software/main.sh"
exec bash "$(dirname "${BASH_SOUCE[0]}")/../configs/main.sh"
exec bash "$(dirname "${BASH_SOUCE[0]}")/../lib/main.sh"