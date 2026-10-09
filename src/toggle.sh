#!/bin/bash
set -u
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f /.flatpak-info ]]; then
    exec flatpak-spawn --host /bin/bash "$DIR/toggle.sh" "$@"
fi
terminal=0
band=auto
while (( $# )); do
    case $1 in
        --terminal) terminal=1; shift ;;
        --band) [[ $# -ge 2 ]] || { echo 'Missing band.'; exit 2; }; band=$2; shift 2 ;;
        *) echo 'Usage: toggle.sh [--terminal] [--band 2.4|5]'; exit 2 ;;
    esac
done
case $band in auto|2.4|5) ;; *) echo 'Band must be 2.4 or 5.'; exit 2 ;; esac
umask 077
# Serialize GUI launches before opening/truncating the shared log.
exec 8>"$DIR/.launcher.lock"
flock -n 8 || { echo 'Another hotspot operation is already running.' >&2; exit 1; }
# Ask only when starting without an upstream Wi-Fi connection.
if ! iw dev deckhot0 info >/dev/null 2>&1 && ! systemctl is-active --quiet deck-hotspot-ap.service; then
    connected=0
    while read -r device; do
        if iw dev "$device" link | grep -q '^Connected to '; then connected=1; break; fi
    done < <(iw dev | awk '$1 == "Interface" {print $2}')
    if (( ! connected )) && [[ $band == auto ]]; then
        if (( ! terminal )) && command -v kdialog >/dev/null; then
            band=$(kdialog --title 'Wi-Fi Hotspot' --radiolist 'Standalone hotspot / Автономная точка: выберите диапазон' 5 '5 GHz — Moonlight' on 2.4 '2.4 GHz — compatibility / совместимость' off) || exit 0
        elif [[ -t 0 ]]; then
            read -r -p 'Hotspot band (2.4 or 5): ' band
        else
            echo 'Use --band 2.4 or --band 5 for a standalone hotspot.' >&2
            exit 2
        fi
        case $band in 2.4|5) ;; *) echo 'Invalid band.'; exit 2 ;; esac
    fi
    if (( ! connected )) && [[ $band == 5 && ! -f $DIR/country.txt ]]; then
        if (( ! terminal )) && command -v kdialog >/dev/null; then
            country=$(kdialog --title 'Wi-Fi country / Страна Wi-Fi' --inputbox 'Actual country code / Код страны, где вы находитесь (RU, DE, US…):') || exit 0
        elif [[ -t 0 ]]; then
            read -r -p 'Your actual two-letter country code (RU, DE, US...): ' country
        else
            echo 'Save your actual two-letter country code in country.txt first.' >&2
            exit 2
        fi
        country=$(printf '%s' "$country" | tr '[:lower:]' '[:upper:]')
        [[ $country =~ ^[A-Z]{2}$ ]] || { echo 'Invalid country code.'; exit 2; }
        printf '%s\n' "$country" >"$DIR/country.txt"
    fi
fi
log="$DIR/last-run.log"
if pkexec /bin/bash "$DIR/hotspot-helper.sh" toggle "$band" >"$log" 2>&1; then
    result=0
else
    result=$?
fi
if (( terminal )); then cat "$log"; fi
if (( ! terminal )) && command -v kdialog >/dev/null; then
    if (( result == 0 )); then
        message=$(sed -n '/^Hotspot is on\./,$p' "$log")
        [[ -n $message ]] || message=$(tail -n 5 "$log")
        kdialog --title 'Steam Deck Hotspot' --msgbox "$message" || true
    else
        kdialog --title 'Steam Deck Hotspot — error' --error "$(tail -n 25 "$log")

Full log saved to: $log" || true
    fi
fi
exit "$result"
