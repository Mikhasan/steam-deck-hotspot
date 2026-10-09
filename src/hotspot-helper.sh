#!/bin/bash
set -Eeuo pipefail
export LC_ALL=C
umask 077
export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
AP=deckhot0
BR=deckbr0
PROFILE=Deck-Hotspot-Bridge
UNIT=deck-hotspot-ap
CONF=/run/NetworkManager/conf.d/90-deck-hotspot.conf
STATE=/run/deck-hotspot
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ACTION=${1:-toggle}
REQUESTED_BAND=${2:-auto}
case "$REQUESTED_BAND" in auto|2.4|5) ;; *) echo "Invalid band: use 2.4 or 5."; exit 2 ;; esac
case "$ACTION" in toggle|off|uninstall) ;; *) echo 'Unknown action.'; exit 2 ;; esac
[[ $EUID == 0 ]] || { echo 'Run toggle.sh.'; exit 1; }
exec 9>/run/lock/deck-hotspot-toggle.lock
flock -n 9 || { echo 'Another hotspot operation is already running.'; exit 1; }
# Persist opt-in in the user's installation, not in the replaceable SteamOS image.
enable_sunshine_access() {
    [[ -f $DIR/sunshine-access.txt ]] || return 0
    [[ $(cat "$DIR/sunshine-access.txt") == enabled ]] || return 0
    command -v firewall-cmd >/dev/null || return 0
    firewall-cmd --state >/dev/null 2>&1 || return 0
    local zone port query_status
    zone=$(firewall-cmd --get-zone-of-interface="$BR") || return
    [[ $zone == nm-shared ]] || { echo "Cannot configure Sunshine for unexpected firewall zone: $zone" >&2; return 1; }
    for port in 47984/tcp 47989/tcp 48010/tcp 47998-48000/udp; do
        if firewall-cmd --zone=nm-shared --query-port="$port" >/dev/null; then
            continue
        else
            query_status=$?
            (( query_status == 1 )) || return "$query_status"
        fi
        firewall-cmd --zone=nm-shared --add-port="$port" >/dev/null || return
        printf '%s\n' "$port" >>"$STATE/firewall-ports"
    done
}
clear_sunshine_access() {
    [[ -f $STATE/firewall-ports ]] || return 0
    local port
    while read -r port; do
        case $port in
            47984/tcp|47989/tcp|48010/tcp|47998-48000/udp)
                firewall-cmd --zone=nm-shared --remove-port="$port" >/dev/null 2>&1 || true ;;
        esac
    done <"$STATE/firewall-ports"
    rm -f "$STATE/firewall-ports"
}
stop_hotspot() {
    clear_sunshine_access
    systemctl stop "$UNIT.service" 2>/dev/null || true
    nmcli connection down "$PROFILE" >/dev/null 2>&1 || true
    iw dev "$AP" del 2>/dev/null || true
    ip link delete "$BR" 2>/dev/null || true
    if [[ -f $STATE/autoconnect ]]; then
        read -r restore_device restore_value <"$STATE/autoconnect"
        nmcli device set "$restore_device" autoconnect "$restore_value"
        rm -f "$STATE/autoconnect"
    fi
    rm -f "$CONF" "$STATE/hostapd.conf"
    nmcli general reload conf >/dev/null 2>&1 || true
}
if [[ $ACTION == uninstall ]]; then
    stop_hotspot
    if nmcli connection show "$PROFILE" >/dev/null 2>&1; then nmcli connection delete "$PROFILE"; fi
    echo 'Hotspot network configuration removed.'
    exit 0
fi
if [[ $ACTION == off ]] || iw dev "$AP" info >/dev/null 2>&1 || systemctl is-active --quiet "$UNIT.service"; then
    stop_hotspot
    echo 'Hotspot is off.'
    exit 0
fi
COUNTRY=''
STA=''
RADIO=''
while read -r device; do
    [[ $device == "$AP" ]] && continue
    iw dev "$device" info | grep -q 'type managed' || continue
    [[ -n $RADIO ]] || RADIO=$device
    if iw dev "$device" link | grep -q '^Connected to '; then STA=$device; RADIO=$device; break; fi
done < <(iw dev | awk '$1 == "Interface" {print $2}')
[[ -n $RADIO ]] || { echo 'No Wi-Fi adapter found. Enable Wi-Fi first.'; exit 1; }
if [[ -n $STA ]]; then
    read -r CHANNEL FREQ < <(iw dev "$STA" info | awk '$1 == "channel" {gsub(/\(/,"",$3); print $2, $3}')
    [[ ${CHANNEL:-} =~ ^[0-9]+$ && ${FREQ:-} =~ ^[0-9]+$ ]] || { echo 'Could not determine the current Wi-Fi channel.'; exit 1; }
    if (( FREQ < 2500 )); then BAND=g; elif (( FREQ < 5900 )); then BAND=a; else exit 1; fi
    MODE='Wi-Fi sharing (using the upstream channel)'
else
    [[ $REQUESTED_BAND != auto ]] || { echo 'Choose a band: toggle.sh --band 2.4 or --band 5'; exit 2; }
    PHY=$(iw dev "$RADIO" info | awk '$1 == "wiphy" {print "phy" $2}')
    if [[ $REQUESTED_BAND == 2.4 ]]; then BAND=g; else BAND=a; fi
    # Apply only a country explicitly configured by the user for their location.
    if [[ -f $DIR/country.txt ]]; then
        COUNTRY=$(tr -d '\r\n' <"$DIR/country.txt")
        [[ $COUNTRY =~ ^[A-Z]{2}$ ]] || { echo 'country.txt must contain your two-letter country code.'; exit 2; }
        iw reg set "$COUNTRY"
        # Regulatory updates are asynchronous; wait for the configured domain.
        for attempt in {1..20}; do
            iw reg get | grep -q "country $COUNTRY:" && break
            sleep 0.1
        done
    fi
    # Select only a permitted non-DFS channel; never ignore no-IR restrictions.
    CHANNEL=$(iw phy "$PHY" info | awk -v band="$BAND" '
        /MHz \[/ && !/disabled|no IR|radar/ {
            freq=$2; channel=$4; gsub(/\[|\]/,"",channel)
            if ((band == "g" && freq >= 2412 && freq <= 2462) ||
                (band == "a" && freq >= 5180 && freq <= 5240)) { if (!found) print channel; found=1 }
        }')
    [[ $CHANNEL =~ ^[0-9]+$ ]] || { echo "No permitted non-DFS channel for $REQUESTED_BAND GHz. Set your actual country in country.txt, or try 2.4 GHz."; exit 1; }
    MODE='Standalone hotspot (internet requires another upstream connection)'
fi
SSID=$(sed -n '1p' "$DIR/settings.txt")
PASSWORD=$(sed -n '2p' "$DIR/settings.txt")
[[ -n $SSID && ${#SSID} -le 32 && ${#PASSWORD} -ge 8 && ${#PASSWORD} -le 63 ]] || { echo 'Check the network name and password in settings.txt.'; exit 1; }
readonly_changed=0
started=0
cleanup() {
    result=$?
    if (( result != 0 && started )); then
        journalctl -u "$UNIT.service" --no-pager -n 25 || true
        stop_hotspot
    fi
    if (( readonly_changed )); then
        if ! steamos-readonly enable; then
            echo 'ERROR: Could not restore SteamOS read-only protection. Run sudo steamos-readonly enable.' >&2
            result=1
        fi
    fi
    return "$result"
}
trap cleanup EXIT
source "$DIR/dependencies.sh"
ensure_hotspot_dependencies
started=1
install -d -m 700 "$STATE"
if [[ -z $STA ]]; then
    old_autoconnect=$(nmcli -g GENERAL.AUTOCONNECT device show "$RADIO")
    [[ $old_autoconnect == yes || $old_autoconnect == no ]] || { echo 'Cannot read Wi-Fi autoconnect state.'; exit 1; }
    printf '%s %s\n' "$RADIO" "$old_autoconnect" >"$STATE/autoconnect"
    nmcli device set "$RADIO" autoconnect no
    if iw dev "$RADIO" link | grep -q '^Connected to '; then
        echo 'Wi-Fi connected while starting. Run the launcher again.'
        exit 1
    fi
fi
mkdir -p /run/NetworkManager/conf.d
cat >"$CONF" <<'CONFIG'
[device-deck-hotspot]
match-device=interface-name:deckhot0
managed=0
CONFIG
nmcli general reload conf
if ! nmcli connection show "$PROFILE" >/dev/null 2>&1; then
    nmcli connection add type bridge ifname "$BR" con-name "$PROFILE" connection.autoconnect no bridge.stp no ipv4.method shared ipv6.method disabled >/dev/null
fi
nmcli connection modify "$PROFILE" connection.autoconnect no ipv4.never-default yes
nmcli --wait 20 connection up "$PROFILE"
printf -v AP_MAC '02:%02x:%02x:%02x:%02x:%02x' "$((RANDOM % 256))" "$((RANDOM % 256))" "$((RANDOM % 256))" "$((RANDOM % 256))" "$((RANDOM % 256))"
iw dev "$RADIO" interface add "$AP" type __ap addr "$AP_MAC"
udevadm settle --timeout=10
nmcli device set "$AP" managed no
# Hex encoding keeps arbitrary SSID/password text out of hostapd configuration syntax.
SSID_HEX=$(printf '%s' "$SSID" | od -An -v -tx1 | tr -d ' \n')
PSK=$(wpa_passphrase "$SSID" "$PASSWORD" | sed -n 's/^[[:space:]]*psk=//p')
[[ $PSK =~ ^[0-9a-f]{64}$ ]] || { echo 'Could not generate the WPA2 key.'; exit 1; }
cat >"$STATE/hostapd.conf" <<CONFIG
interface=$AP
bridge=$BR
driver=nl80211
ctrl_interface=$STATE/ctrl
ssid2=$SSID_HEX
hw_mode=$BAND
channel=$CHANNEL
wmm_enabled=1
ieee80211n=1
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_psk=$PSK
CONFIG
if [[ -n $COUNTRY ]]; then
    printf 'country_code=%s\nieee80211d=1\n' "$COUNTRY" >>"$STATE/hostapd.conf"
fi
systemctl reset-failed "$UNIT.service" 2>/dev/null || true
systemd-run --unit="$UNIT" --collect --property=Type=exec /usr/bin/hostapd "$STATE/hostapd.conf"
ready=0
for attempt in {1..40}; do
    if hostapd_cli -p "$STATE/ctrl" -i "$AP" status 2>/dev/null | grep -qx state=ENABLED; then ready=1; break; fi
    systemctl is-active --quiet "$UNIT.service" || break
    sleep 0.25
done
(( ready )) || { echo 'Could not start the access point.'; exit 1; }
for attempt in {1..40}; do
    if nmcli -g GENERAL.STATE device show "$BR" | grep -q '^100 '; then break; fi
    sleep 0.25
done
nmcli -g GENERAL.STATE device show "$BR" | grep -q '^100 ' || { echo 'The shared connection did not become ready.'; exit 1; }
if [[ -n $STA ]]; then
    iw dev "$STA" link | grep -q '^Connected to ' || { echo 'The upstream Wi-Fi connection was lost.'; exit 1; }
fi
enable_sunshine_access
echo "Hotspot is on.
Network: $SSID
Password: $PASSWORD
Mode: $MODE
Band: $([[ $BAND == g ]] && echo 2.4 || echo 5) GHz
Channel: $CHANNEL

Run the launcher again to turn it off."
