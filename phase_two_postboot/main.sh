#!usr/bin/env bash
echo "Phase two postboot present."


chmod +x "$DIR/phase_three_desktop/main.sh"
exec bash "$DIR/phase_three_desktop/main.sh"




