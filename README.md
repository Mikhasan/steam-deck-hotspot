# Steam Deck Hotspot

Share your Steam Deck's Wi-Fi connection, or create a standalone 2.4/5 GHz hotspot for local Moonlight streaming. Start and stop it with a desktop shortcut.

[Инструкция на русском](docs/README.ru.md)

Tested on **Steam Deck LCD, SteamOS 3.8.16**, with the RTL8822CE adapter and `rtw88_8822ce` driver. A phone successfully used the shared internet connection, including the owner's VPN connection. OLED and other hardware have not been tested.

## Install

In **Desktop Mode**, download this repository using **Code → Download ZIP**, extract it, open Konsole in the extracted directory, and run:

```bash
bash install.sh
```

Or clone it:

```bash
git clone https://github.com/Mikhasan/steam-deck-hotspot.git
cd steam-deck-hotspot
bash install.sh
```

The installer creates a **Wi-Fi Hotspot** desktop shortcut and installs user files in `~/.local/share/steam-deck-hotspot` (or under `XDG_DATA_HOME` when set). It generates a unique random Wi-Fi password. Installing again preserves your settings.

Keep Wi-Fi enabled and launch the shortcut, and enter your **Linux user password**, not your Steam password. If you have never set one, run `passwd` in Konsole first. KDE may ask you to trust the desktop shortcut.

The first launch installs `hostapd` and `dnsmasq` from the configured SteamOS repositories if missing. It temporarily disables SteamOS read-only protection and restores its previous state afterward. An internet connection and working package repositories/keyring are required. SteamOS updates may remove these packages; the next launch installs them again. Do not run the installer with sudo.

## Use

- Launch once to enable the hotspot; launch again to disable it.
- The success dialog displays the network name, password, and channel.
- Edit `~/.local/share/steam-deck-hotspot/settings.txt`: first line is the SSID, second line is the password. Use an 8–63 character ASCII password. Changes take effect on the next start.
- The hotspot does not start automatically after reboot.
- After changing the upstream Wi-Fi network or channel, turn the hotspot off and on again.

## Standalone hotspot (no router)

Leave Wi-Fi enabled but disconnect from the router, then launch the shortcut.
Choose **5 GHz** or **2.4 GHz** in the dialog. The hotspot uses a permitted
non-DFS channel (normally 36 on 5 GHz or 1 on 2.4 GHz). If that band has no
eligible channel, startup stops with an error; regulatory limits are respected.

For terminal use:

```bash
bash ~/.local/share/steam-deck-hotspot/toggle.sh --terminal --band 5
# Or: --band 2.4
```

When already connected to Wi-Fi, the router's channel and band take precedence.
To switch an active hotspot's band, stop it and start it again.
During standalone operation, adapter autoconnect is disabled and restored on
shutdown. Keep Wi-Fi enabled; turning off the radio also disables the hotspot.

Moonlight/Sunshine works locally without internet. Other clients only get internet
if the Deck has an upstream connection, for example Ethernet or USB tethering.
Missing packages still require an internet connection to install the first time.

## Limits

The adapter must support concurrent station + AP operation. Check `iw list`, under **valid interface combinations**. The tested LCD reports one `managed` interface plus one `AP`, with `#channels <= 1`.

Both connections must use the **same channel and band**. Receiving on 2.4 GHz and sharing on 5 GHz requires a second adapter. This setup enables 802.11n on a 20 MHz channel; it does not configure an 80 MHz 802.11ac hotspot. The same radio handles both traffic directions, so throughput can be lower than a direct connection.

Some channels, especially DFS/restricted 5 GHz channels, may not allow a hotspot. This tool does not override regulatory restrictions. If startup fails, try connecting the Deck to a router using a locally permitted non-DFS channel.

VPN sharing worked in the tested setup, but depends on VPN routing, firewall and kill-switch settings. It is not guaranteed for every VPN. IPv4 is shared; IPv6 is disabled on the hotspot bridge. Sleep/resume behavior has not been validated.

## How it works

```text
Router Wi-Fi → wlan0 (existing connection, managed by IWD)
                    ↓ NetworkManager shared IPv4 / NAT / DHCP
                 deckbr0 bridge
                    ↓
                 deckhot0 AP (hostapd, WPA2-PSK/CCMP) → phone/laptop
```

`hostapd` manages the additional AP interface. A runtime NetworkManager rule excludes only that interface from management. NetworkManager manages the bridge and runs `dnsmasq` for client addresses and DNS. No global Wi-Fi backend switch or NetworkManager restart is needed.

The shortcut uses `pkexec` for privileged operations. No passwordless sudo rule or boot service is installed. Runtime files live under `/run/deck-hotspot` and `/run/NetworkManager/conf.d/90-deck-hotspot.conf`; a transient `deck-hotspot-ap.service` runs hostapd. The `Deck-Hotspot-Bridge` profile persists with autoconnect disabled. The names `deckhot0` and `deckbr0` are reserved for this tool.

## Moonlight through the hotspot

Add the hotspot address in Moonlight (normally `10.42.0.1`; check with
`ip -4 addr show deckbr0`). Enter the pairing PIN in Sunshine on the Deck.

With firewalld, `nm-shared` normally blocks services on the Deck even when shared
internet works. To allow Sunshine's default streaming ports for hotspot clients:

```bash
for port in 47984/tcp 47989/tcp 48010/tcp 47998-48000/udp; do
    sudo firewall-cmd --zone=nm-shared --add-port="$port"
    sudo firewall-cmd --permanent --zone=nm-shared --add-port="$port"
done
```

These optional rules persist and apply to interfaces in `nm-shared`. They do not
open the Sunshine administration page. Adjust the list for custom Sunshine ports.
The installer does not add them automatically, and uninstall leaves them in place.
To undo them, repeat the commands with `--remove-port` instead of `--add-port`.

## Troubleshooting

Run from Konsole to see output directly:

```bash
bash ~/.local/share/steam-deck-hotspot/toggle.sh --terminal
```

The last run is saved to `~/.local/share/steam-deck-hotspot/last-run.log`. **It contains the hotspot password after a successful start; redact it before sharing.** Logs and settings are ignored by Git.

For hostapd messages:

```bash
journalctl -b -u deck-hotspot-ap.service --no-pager
```

If clients connect but have no internet, check whether the Deck itself has internet, and check VPN/firewall settings. A repository DNS or package-signature error during first launch is an installation failure; resolve that before retrying. The tool does not disable package signature checks.

## Uninstall

```bash
bash ~/.local/share/steam-deck-hotspot/uninstall.sh
```

This stops the hotspot, removes its NetworkManager profile, runtime configuration, installed scripts, settings, log, and desktop shortcut. `hostapd` and `dnsmasq` packages remain installed. If you use `XDG_DATA_HOME` or a custom installation path, adjust the command accordingly.

## Development and validation

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh
for script in src/*.sh; do bash -n "$script"; done
```

Automated tests exercise installation, updates, password generation, path handling, and uninstallation with privileged actions stubbed out. Channel-selection tests also cover both standalone bands, restricted channels and upstream precedence. They do not validate radio operation; standalone operation has not yet been tested on hardware. The original hotspot implementation was tested for startup, shutdown, restart, DHCP and client internet access on the LCD configuration above; the packaged installer is checked separately.

Contributions and hardware reports are welcome. Include SteamOS version, Deck model, driver, band/channel and a redacted log. Never attach your `settings.txt` or an unredacted hostapd configuration.

## License

[MIT](LICENSE). Community project; not affiliated with Valve.
