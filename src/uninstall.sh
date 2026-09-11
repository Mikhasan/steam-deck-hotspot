#!/bin/bash
set -euo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f /.flatpak-info ]]; then
    exec flatpak-spawn --host /bin/bash "$DIR/uninstall.sh"
fi
[[ -f $DIR/.steam-deck-hotspot-install ]] || { echo 'This is not an installed copy.' >&2; exit 1; }
pkexec /bin/bash "$DIR/hotspot-helper.sh" uninstall
IFS= read -r desktop_file <"$DIR/.desktop-path"
# Only remove a launcher that still points at this installation.
if [[ -f $desktop_file ]] && grep -Fq "Exec=/bin/bash \"$DIR/toggle.sh\"" "$desktop_file"; then
    rm -- "$desktop_file"
fi
rm -f -- "$DIR/toggle.sh" "$DIR/hotspot-helper.sh" "$DIR/uninstall.sh"     "$DIR/settings.txt" "$DIR/last-run.log" "$DIR/.desktop-path"     "$DIR/.steam-deck-hotspot-install" "$DIR/.launcher.lock"
rmdir -- "$DIR" || echo 'Additional files remain in the installation directory.'
echo 'Uninstalled. hostapd and dnsmasq packages were left installed.'
