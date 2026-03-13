#!usr/bin/env bash
echo "Phase two postboot present."

DIR=/run/sa/arch-secure/
chmod +x "$DIR/phase_three_desktop/main.sh"
exec bash "$DIR/phase_three_desktop/main.sh"




