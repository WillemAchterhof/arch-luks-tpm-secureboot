echo "Phase three desktop present."

DIR=/run/sa/arch-secure/
chmod +x "$DIR/phase_four_software/main.sh"
exec bash "$DIR/phase_four_software/main.sh"