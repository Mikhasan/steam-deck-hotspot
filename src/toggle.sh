#!/bin/bash
set -u
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f /.flatpak-info ]]; then
    exec flatpak-spawn --host /bin/bash "$DIR/toggle.sh" "$@"
fi
case ${1:-} in ''|--terminal) ;; *) echo 'Usage: toggle.sh [--terminal]' >&2; exit 2 ;; esac
umask 077
# Serialize GUI launches before opening/truncating the shared log.
exec 8>"$DIR/.launcher.lock"
flock -n 8 || { echo 'Another hotspot operation is already running.' >&2; exit 1; }
log="$DIR/last-run.log"
if pkexec /bin/bash "$DIR/hotspot-helper.sh" >"$log" 2>&1; then
    result=0
else
    result=$?
fi
cat "$log"
if [[ ${1:-} != --terminal ]] && command -v kdialog >/dev/null; then
    if (( result == 0 )); then
        kdialog --title 'Steam Deck Hotspot' --msgbox "$(cat "$log")" || true
    else
        kdialog --title 'Steam Deck Hotspot — error' --error "$(cat "$log")

Log saved to: $log" || true
    fi
fi
exit "$result"
