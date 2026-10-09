#!/bin/bash
# Sourced by the privileged helper; no changes are made merely by sourcing it.
# The caller's EXIT trap restores read-only protection if any step fails.
ensure_hotspot_dependencies() {
    local package readonly_state
    local -a missing=()
    if ! command -v dnsmasq >/dev/null; then missing+=(dnsmasq); fi
    if ! command -v hostapd >/dev/null || ! command -v hostapd_cli >/dev/null; then missing+=(hostapd); fi
    if ! command -v wpa_passphrase >/dev/null; then missing+=(wpa_supplicant); fi
    (( ${#missing[@]} )) || return 0

    echo "Restoring hotspot components after SteamOS update: ${missing[*]}"
    for package in pacman pacman-key steamos-readonly; do
        command -v "$package" >/dev/null || { echo "Required system tool is missing: $package" >&2; return 1; }
    done
    # Only import the distro keyrings shipped with this SteamOS installation.
    [[ -f /usr/share/pacman/keyrings/archlinux.gpg && -f /usr/share/pacman/keyrings/holo.gpg ]] || {
        echo 'SteamOS package-signing keyrings are missing. No packages were installed.' >&2
        return 1
    }
    readonly_state=$(steamos-readonly status) || return
    case "$readonly_state" in
        enabled)
            steamos-readonly disable || return
            readonly_changed=1
            ;;
        disabled) ;;
        *) echo "Cannot determine SteamOS read-only state: $readonly_state" >&2; return 1 ;;
    esac

    echo 'Preparing the SteamOS package-signing keyring...'
    if ! pacman-key --init; then
        echo 'Could not initialize the package keyring. See last-run.log.' >&2
        return 1
    fi
    if ! pacman-key --populate archlinux holo; then
        echo 'Could not import the installed SteamOS signing keys. See last-run.log.' >&2
        return 1
    fi
    # Use SteamOS repository versions, its normal cache and signature checks.
    # Never perform a system upgrade or disable verification.
    if ! pacman -S --needed --noconfirm "${missing[@]}"; then
        echo 'Could not restore hotspot packages. Check the package error above and internet access, then launch the same shortcut again.' >&2
        return 1
    fi
    for package in dnsmasq hostapd hostapd_cli wpa_passphrase; do
        command -v "$package" >/dev/null || { echo "Package installation did not provide $package." >&2; return 1; }
    done
    if (( readonly_changed )); then
        steamos-readonly enable || return
        readonly_changed=0
    fi
    echo 'Hotspot components restored. Continuing startup...'
}
