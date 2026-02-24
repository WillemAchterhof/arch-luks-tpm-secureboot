#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Linux Secure Install - network-setup.sh
#  Called by install.sh when no internet is detected
#  Handles ethernet detection, WiFi setup and credential saving
# ==============================================================================

CREDENTIALS_FILE="$REPO_ROOT/.wifi-credentials"

# ==============================================================================
# HELPER — Check Internet Connectivity
# ==============================================================================

has_internet() {
    curl -s --head --fail --max-time 3 https://archlinux.org >/dev/null
}

# ==============================================================================
# CHECK FOR ACTIVE ETHERNET FIRST
# Uses carrier file — more reliable than ip link state
# ==============================================================================

echo "[*] Checking for ethernet connection..."

for path in /sys/class/net/*; do
    iface=$(basename "$path")

    [[ "$iface" == "lo" ]] && continue
    [[ -d "$path/wireless" ]] && continue

    if [[ -f "$path/carrier" ]] && [[ "$(cat "$path/carrier" 2>/dev/null)" == "1" ]]; then
        echo "  Ethernet link detected on: $iface"

        if has_internet; then
            echo "  Internet working via ethernet."
            echo
            exit 0
        else
            echo "  Cable connected but no internet — check DHCP/router."
            echo
        fi
    fi
done

echo "  No working ethernet connection detected."
echo

# ==============================================================================
# AUTO-RECONNECT — Try saved WiFi credentials first
# ==============================================================================

if [[ -f "$CREDENTIALS_FILE" ]]; then
    echo "[*] Found saved WiFi credentials — attempting auto-reconnect..."

    SAVED_SSID=""
    SAVED_PASSWORD=""

    # Read saved credentials safely
    while IFS='=' read -r key value; do
        case "$key" in
            SSID)     SAVED_SSID="$value" ;;
            PASSWORD) SAVED_PASSWORD="$value" ;;
        esac
    done < "$CREDENTIALS_FILE"

    if [[ -n "$SAVED_SSID" && -n "$SAVED_PASSWORD" ]]; then
        ADAPTER=$(iwctl device list | awk '/station/ {print $2; exit}')

        if [[ -n "$ADAPTER" ]]; then
            echo "  Connecting to: $SAVED_SSID"
            if iwctl --passphrase "$SAVED_PASSWORD" station "$ADAPTER" connect "$SAVED_SSID" >/dev/null 2>&1; then
                sleep 2
                if has_internet; then
                    echo "  [*] Auto-reconnected successfully."
                    echo
                    exit 0
                fi
            fi
            echo "  [!] Auto-reconnect failed — falling back to manual setup."
            echo
        fi
    fi

    unset SAVED_PASSWORD
fi

# ==============================================================================
# WIFI SETUP
# ==============================================================================

echo "[*] Starting WiFi setup..."
echo

# ------------------------------------------------------------------------------
# FIND WIFI ADAPTER
# ------------------------------------------------------------------------------

ADAPTER=$(iwctl device list | awk '/station/ {print $2; exit}')

if [[ -z "$ADAPTER" ]]; then
    echo "[!] No WiFi adapter detected."
    echo "    Plug in ethernet and re-run install.sh"
    exit 1
fi

echo "  Detected adapter: $ADAPTER"
read -rp "  Use this adapter? (Y/n): " CONFIRM_ADAPTER
if [[ "${CONFIRM_ADAPTER,,}" == "n" ]]; then
    read -rp "  Enter adapter name manually: " ADAPTER
fi
echo

# ------------------------------------------------------------------------------
# SCAN NETWORKS
# ------------------------------------------------------------------------------

NETWORKS=()

scan_networks() {
    echo "[*] Scanning for WiFi networks..."
    iwctl station "$ADAPTER" scan >/dev/null 2>&1
    sleep 2

    mapfile -t NETWORKS < <(
        iwctl station "$ADAPTER" get-networks 2>/dev/null \
        | awk 'NR>4 && $1 !~ /Network|--/ {
            gsub(/\x1b\[[0-9;]*m/, "")
            if ($1 != "") print $1
        }'
    )
}

# ------------------------------------------------------------------------------
# NETWORK SELECTION + CONNECT LOOP
# ------------------------------------------------------------------------------

WIFI_CONNECTED=false

while true; do
    scan_networks

    clear
    echo "================================================="
    echo "   Available WiFi Networks"
    echo "================================================="
    echo

    if [[ ${#NETWORKS[@]} -eq 0 ]]; then
        echo "  No networks found."
        echo
        echo "  [r] Rescan"
        echo "  [m] Manual SSID"
        echo "  [a] Abort WiFi setup"
        echo
        read -rp "  Select: " NET_CHOICE

        case "$NET_CHOICE" in
            r|R) continue ;;
            m|M) SSID="" ;;
            a|A) break ;;
            *)   continue ;;
        esac
    else
        for i in "${!NETWORKS[@]}"; do
            printf "  [%s] %s\n" "$((i+1))" "${NETWORKS[$i]}"
        done

        echo
        echo "  [r] Rescan"
        echo "  [m] Manual SSID"
        echo "  [a] Abort WiFi setup"
        echo
        read -rp "  Select network: " NET_CHOICE

        case "$NET_CHOICE" in
            r|R) continue ;;
            m|M) SSID="" ;;
            a|A) break ;;
            *)
                if [[ "$NET_CHOICE" =~ ^[0-9]+$ ]] &&
                   (( NET_CHOICE >= 1 && NET_CHOICE <= ${#NETWORKS[@]} )); then
                    SSID="${NETWORKS[$((NET_CHOICE-1))]}"
                else
                    echo "  [!] Invalid selection."
                    sleep 1
                    continue
                fi
                ;;
        esac
    fi

    # Manual SSID entry
    if [[ -z "${SSID:-}" ]]; then
        read -rp "  Enter SSID: " SSID
        [[ -z "$SSID" ]] && continue
    fi

    # --------------------------------------------------------------------------
    # PASSWORD + CONNECT
    # 3 attempts then back to network selection
    # --------------------------------------------------------------------------

    echo
    for attempt in 1 2 3; do
        read -rsp "  Enter password for '$SSID': " WIFI_PASSWORD && echo

        if iwctl --passphrase "$WIFI_PASSWORD" station "$ADAPTER" connect "$SSID" >/dev/null 2>&1; then
            # Save credentials to USB for reuse after BIOS reboot
            {
                echo "SSID=$SSID"
                echo "PASSWORD=$WIFI_PASSWORD"
            } > "$CREDENTIALS_FILE"
            chmod 600 "$CREDENTIALS_FILE"

            unset WIFI_PASSWORD
            echo
            echo "  [*] Connected to $SSID"
            echo "  [*] Credentials saved to USB for reuse after reboot."
            WIFI_CONNECTED=true
            break 2
        fi

        unset WIFI_PASSWORD
        echo "  [!] Connection failed (attempt $attempt)."
        [[ $attempt -lt 3 ]] && echo "      Retrying..."
    done

    # 3 failures — back to network selection automatically
done

# ==============================================================================
# FINAL CONNECTIVITY CHECK
# ==============================================================================

echo
echo "[*] Verifying internet connectivity..."

for attempt in 1 2 3; do
    if has_internet; then
        echo "[*] Network connection established."
        echo
        exit 0
    fi
    echo "  [!] Attempt $attempt failed, retrying in 3 seconds..."
    sleep 3
done

echo
echo "[!] No internet connection."
echo "    Plug in ethernet or re-run install.sh"
exit 1