#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
#  Arch Linux Secure Install - network-setup.sh
# ==============================================================================

: "${REPO_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CREDENTIALS_FILE="$REPO_ROOT/.wifi-credentials"
LOG_FILE="/tmp/network-setup.log"
VERBOSE=true

# shellcheck source=/dev/null
source "$REPO_ROOT/install/lib/common.sh"

# CHECK ETHERNET -------------------------------------------------------

log "[*] Checking ethernet..."

FOUND_ETH=false
for path in /sys/class/net/*; do
    iface=$(basename "$path")
    [[ "$iface" == "lo" ]] && continue
    [[ -d "$path/wireless" ]] && continue
    if [[ -f "$path/carrier" ]] && [[ "$(cat "$path/carrier" 2>/dev/null)" == "1" ]]; then
        FOUND_ETH=true
        break
    fi
done

if [[ "$FOUND_ETH" == true ]] && has_internet; then
    log "[*] Ethernet working. Continuing..."
    exit 0
fi

# AUTO-RECONNECT -------------------------------------------------------

log "[*] No working ethernet — trying saved WiFi..."

if [[ -f "$CREDENTIALS_FILE" ]]; then
    SAVED_SSID=""
    SAVED_PASSWORD=""

    while IFS='=' read -r key value; do
        key="${key// /}"
        value="${value//$'\r'/}"
        case "$key" in
            SSID)     SAVED_SSID="$value" ;;
            PASSWORD) SAVED_PASSWORD="$value" ;;
        esac
    done < "$CREDENTIALS_FILE"

    if [[ -n "$SAVED_SSID" && -n "$SAVED_PASSWORD" ]]; then
        ADAPTER=$(get_wifi_adapter)

        if [[ -n "${ADAPTER:-}" ]]; then
            log "[*] Attempting auto-reconnect to: $SAVED_SSID"
            iwctl --passphrase "$SAVED_PASSWORD" station "$ADAPTER" connect "$SAVED_SSID" >/dev/null 2>&1 || true

            for i in {1..10}; do
                has_internet && break
                sleep 1
            done

            if has_internet; then
                log "[*] Auto-reconnected successfully to $SAVED_SSID."
                unset SAVED_PASSWORD
                exit 0
            fi

            log "[!] Auto-reconnect failed — falling back to manual setup."
        fi
    fi

    unset SAVED_PASSWORD || true
fi

# INTERACTIVE WIFI SETUP -----------------------------------------------

log "[*] Launching interactive WiFi setup..."

ADAPTER=$(get_wifi_adapter)

if [[ -z "${ADAPTER:-}" ]]; then
    log "[!] No WiFi adapter detected."
    log "    Plug in ethernet and re-run install.sh"
    exit 1
fi

log "  Detected adapter: $ADAPTER"
read -rp "  Use this adapter? (Y/n): " CONFIRM_ADAPTER
if [[ "${CONFIRM_ADAPTER,,}" == "n" ]]; then
    read -rp "  Enter adapter name manually: " ADAPTER
fi
echo

NETWORKS=()

scan_networks() {
    log "[*] Scanning for WiFi networks..."
    iwctl station "$ADAPTER" scan >/dev/null 2>&1 || true
    sleep 2

    mapfile -t NETWORKS < <(
        iwctl station "$ADAPTER" get-networks 2>/dev/null \
        | awk '
            NR>4 && $1 !~ /Network|--/ {
                gsub(/\x1b\[[0-9;]*m/, "")
                if ($1 != "") print $1
            }' \
        | sort -u
    )
}

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

        case "${NET_CHOICE:-}" in
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

        case "${NET_CHOICE:-}" in
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

    if [[ -z "${SSID:-}" ]]; then
        read -rp "  Enter SSID: " SSID
        [[ -z "$SSID" ]] && continue
    fi

    echo
    for attempt in 1 2 3; do
        read -rsp "  Enter password for '$SSID': " WIFI_PASSWORD && echo

        if iwctl --passphrase "$WIFI_PASSWORD" station "$ADAPTER" connect "$SSID" >/dev/null 2>&1; then
            for i in {1..10}; do
                has_internet && break
                sleep 1
            done

            if has_internet; then
                read -rp "  Save credentials for reuse after reboot? (y/N): " SAVE_CHOICE
                if [[ "${SAVE_CHOICE,,}" == "y" ]]; then
                    {
                        echo "SSID=$SSID"
                        echo "PASSWORD=$WIFI_PASSWORD"
                    } > "$CREDENTIALS_FILE"
                    chmod 600 "$CREDENTIALS_FILE"
                    log "[*] Credentials saved to: $CREDENTIALS_FILE"
                fi

                unset WIFI_PASSWORD
                log "[*] Connected to $SSID"
                WIFI_CONNECTED=true
                break 2
            fi
        fi

        unset WIFI_PASSWORD
        log "[!] Connection failed (attempt $attempt)."
        [[ $attempt -lt 3 ]] && log "    Retrying..."
    done
done

echo
log "[*] Verifying internet connectivity..."

for attempt in 1 2 3; do
    if has_internet; then
        log "[*] Network connection established."
        echo
        exit 0
    fi
    log "[!] Attempt $attempt failed, retrying in 3 seconds..."
    sleep 3
done

log "[!] No internet connection after all attempts."
log "    Plug in ethernet or re-run install.sh"
exit 1
