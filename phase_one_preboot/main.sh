#!usr/bin/env bash
echo "Phase one preboot present."
exec bash "$(dirnam "${BASH_SOUCE[0]}")/../phase_two_postboot/main.sh
exec bash "$(dirnam "${BASH_SOUCE[0]}")/../phase_three_destop/main.sh
exec bash "$(dirnam "${BASH_SOUCE[0]}")/../phase__four_software/main.sh
exec bash "$(dirnam "${BASH_SOUCE[0]}")/../configs/main.sh
exec bash "$(dirnam "${BASH_SOUCE[0]}")/../lib/main.sh
