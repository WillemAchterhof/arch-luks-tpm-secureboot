#!usr/bin/env bash
echo "Phase one preboot present."
DIR=/run/sa/arch-secure/

chmod +x "$DIR/phase_two_postboot/main.sh"
exec bash "$DIR/phase_two_postboot/main.sh"