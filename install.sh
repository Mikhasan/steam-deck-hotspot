#!/bin/bash
# Installs user files only. Network setup happens on the first launch.
set -euo pipefail
umask 077
SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/steam-deck-hotspot"
DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || printf '%s/Desktop' "$HOME")
if [[ ${1:-} == --target && $# == 3 ]]; then
    APP_DIR=$2
    DESKTOP_DIR=$3
elif (( $# )); then
    echo 'Usage: bash install.sh [--target ABSOLUTE_APP_DIR ABSOLUTE_DESKTOP_DIR]' >&2
    exit 2
fi
# Desktop Exec has its own quoting rules. Reject unusual paths rather than
# generating an ambiguous shell command. Spaces are supported.
for path in "$APP_DIR" "$DESKTOP_DIR"; do
    case "$path" in /*) ;; *) echo 'Installation paths must be absolute.' >&2; exit 2 ;; esac
    case "$path" in *'"'*|*'\'*|*'`'*|*'$'*|*'%'*|*$'\n'*|*$'\r'*) echo 'Unsupported character in installation path.' >&2; exit 2 ;; esac
done
if [[ -e $APP_DIR && ! -f $APP_DIR/.steam-deck-hotspot-install ]]; then
    echo "Refusing to overwrite an existing unrecognized directory: $APP_DIR" >&2
    exit 1
fi
mkdir -p "$APP_DIR" "$DESKTOP_DIR"
chmod 700 "$APP_DIR"
install -m 700 "$SOURCE/src/toggle.sh" "$SOURCE/src/hotspot-helper.sh" "$SOURCE/src/uninstall.sh" "$APP_DIR/"
if [[ ! -e $APP_DIR/settings.txt ]]; then
    password=$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')
    printf 'Deck-Hotspot\n%s\n' "$password" >"$APP_DIR/settings.txt"
fi
chmod 600 "$APP_DIR/settings.txt"
touch "$APP_DIR/.steam-deck-hotspot-install"
printf '%s\n' "$DESKTOP_DIR/Steam-Deck-Hotspot.desktop" >"$APP_DIR/.desktop-path"
cat >"$DESKTOP_DIR/Steam-Deck-Hotspot.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=Wi-Fi Hotspot
Name[ru]=Раздача Wi-Fi
Comment=Toggle simultaneous Wi-Fi sharing on Steam Deck
Exec=/bin/bash "$APP_DIR/toggle.sh"
Icon=network-wireless
Terminal=false
Categories=Network;
ENTRY
chmod 755 "$DESKTOP_DIR/Steam-Deck-Hotspot.desktop"
printf 'Installed: %s\nLauncher: %s/Steam-Deck-Hotspot.desktop\nSettings: %s/settings.txt\n' "$APP_DIR" "$DESKTOP_DIR" "$APP_DIR"
echo 'First launch asks for the system password and installs missing hostapd/dnsmasq packages.'
