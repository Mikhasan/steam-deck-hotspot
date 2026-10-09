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

The first launch installs `hostapd` and `dnsmasq` from the configured SteamOS repositories if missing. It temporarily disables SteamOS read-only protection and restores its previous state afterward. An internet connection and working package repositories/keyring are required. SteamOS updates may remove these packages and reset pacman's signing keyring.
On the next launch, the same shortcut initializes the keyring with `pacman-key
--init`, imports the **installed** `archlinux` and `holo` keyrings, reinstalls missing
components, restores read-only protection and continues starting the hotspot.
Existing installations with all required commands available skip package/keyring
operations. It uses the normal package cache when available; otherwise an internet
connection is required. Package signature verification stays enabled, and it does
not run a system upgrade or fetch signing keys from a keyserver. Do not run the installer with sudo.

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

On the first standalone 5 GHz start, enter the two-letter code of the country
where you are physically using the Deck. It is saved in `country.txt` beside
`settings.txt`. Update it when travelling. SteamOS can reset the domain to `00`
when disconnecting from a router; in that domain all 5 GHz channels may be marked
`no IR`, preventing AP startup. The helper applies your configured country using
`iw reg set` and supplies it to hostapd, then still checks permitted channels.
This changes the radio's regulatory domain; it is not restored on hotspot shutdown.
For terminal use, create `country.txt` with your actual country code first if
running without an interactive terminal. No country is hardcoded in the repository.

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

With firewalld, NetworkManager's `nm-shared` zone normally blocks connections to
host services, even when shared internet works. To opt in to Sunshine access:

```bash
printf 'enabled\n' > ~/.local/share/steam-deck-hotspot/sunshine-access.txt
```

Restart the hotspot. Each start restores the default Sunshine streaming ports
(TCP 47984, 47989, 48010; UDP 47998–48000) in the hotspot's `nm-shared` zone.
The preference lives with your settings and survives SteamOS updates. No rules
are added unless you opt in. Newly added runtime rules are removed on shutdown;
preexisting rules are preserved. This does not open the administration page.
Custom Sunshine ports require separate rules. To disable automatic access, stop
the hotspot, then write `disabled` to `sunshine-access.txt`.

If you previously added permanent rules manually, those remain independent of
this preference. For each port above, remove them using `sudo firewall-cmd
--zone=nm-shared --remove-port=PORT` and the same command with `--permanent`.

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

If clients connect but have no internet, check whether the Deck itself has internet, and check VPN/firewall settings. An uninitialized/reset signing keyring is repaired automatically when components
need restoring. Other repository, DNS or signature errors stop startup and restore
read-only protection; the full error is saved in `last-run.log`. Resolve the reported
issue and launch the same shortcut again. The tool does not disable signature checks.
The success dialog shows the hotspot details; verbose recovery output stays in the log.

## Uninstall

```bash
bash ~/.local/share/steam-deck-hotspot/uninstall.sh
```

This stops the hotspot, removes its NetworkManager profile, runtime configuration, installed scripts, settings, log, and desktop shortcut. `hostapd` and `dnsmasq` packages remain installed. If you use `XDG_DATA_HOME` or a custom installation path, adjust the command accordingly.

The recovery path was also tested on **SteamOS 3.8.28** after an update removed
`hostapd`/`dnsmasq` and reset the signing keyring: a single launch restored the
components and started the hotspot. Shutdown and restart were checked on the Deck.

## Development and validation

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh
for script in src/*.sh; do bash -n "$script"; done
```

Automated tests exercise installation, updates, password generation, path handling, uninstallation, recovery of missing dependencies and reset signing keys, and restoration of read-only protection on failures, with privileged actions stubbed out. Channel-selection tests also cover both standalone bands, restricted channels and upstream precedence. They do not validate radio operation; standalone 5 GHz startup and shutdown have also been tested on the LCD with the confirmed RU domain, channel 36; client streaming in that standalone test was not checked. The original hotspot implementation was tested for startup, shutdown, restart, DHCP and client internet access on the LCD configuration above; the packaged installer is checked separately.

Contributions and hardware reports are welcome. Include SteamOS version, Deck model, driver, band/channel and a redacted log. Never attach your `settings.txt` or an unredacted hostapd configuration.

## License

[MIT](LICENSE). Community project; not affiliated with Valve.
