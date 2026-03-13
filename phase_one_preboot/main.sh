#!usr/bin/env bash
echo "Phase one preboot present."
DIR=/run/sa/arch-secure/
exec bash "$DIR/phase_two_postboot/main.sh"
exec bash "$DIR/phase_three_desktop/main.sh"
exec bash "$DIR/phase_four_software/main.sh"
exec bash "$DIR/configs/main.sh"
exec bash "$DIR/lib/main.sh"