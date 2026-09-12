"""Check channel selection using adapter fixtures, without changing a real radio."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/hotspot-helper.sh').read_text()
SELECTION = SOURCE[SOURCE.index("STA=''\n"):SOURCE.index('SSID=$(')]


class BandTests(unittest.TestCase):
    def select(self, band, connected=False, blocked=False):
        fixture = '''
iw() {
    if [[ $* == dev ]]; then printf 'Interface wlan0\\n';
    elif [[ $* == 'dev wlan0 link' ]]; then
        if [[ $CONNECTED == yes ]]; then echo 'Connected to router'; else echo 'Not connected.'; fi
    elif [[ $* == 'dev wlan0 info' ]]; then printf 'type managed\\nwiphy 0\\nchannel 48 (5240 MHz)\\n';
    elif [[ $* == 'phy phy0 info' ]]; then
        printf '* 2412 MHz [1] (20 dBm)\\n'
        printf '* 5180 MHz [36] (20 dBm) %s\\n' "$BLOCKED"
        printf '* 5260 MHz [52] (20 dBm) radar detection\\n'
    else return 1; fi
}
'''
        script = 'set -euo pipefail\nAP=deckhot0\nDIR=/nonexistent-hotspot-test\n' + fixture + SELECTION + '\nprintf "RESULT:%s:%s:%s\\n" "$BAND" "$CHANNEL" "$STA"\n'
        import os
        return subprocess.run(['bash', '-c', script], text=True, capture_output=True, env={**os.environ, 'REQUESTED_BAND': band, 'CONNECTED': 'yes' if connected else 'no', 'BLOCKED': 'no IR' if blocked else ''})

    def test_standalone_24(self):
        result = self.select('2.4')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('RESULT:g:1:', result.stdout)

    def test_standalone_5(self):
        result = self.select('5')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('RESULT:a:36:', result.stdout)

    def test_connected_uses_router_channel(self):
        result = self.select('2.4', connected=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('RESULT:a:48:wlan0', result.stdout)

    def test_restricted_channels_rejected(self):
        result = self.select('5', blocked=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No permitted', result.stdout)

    def test_offline_needs_band(self):
        result = self.select('auto')
        self.assertEqual(result.returncode, 2)


if __name__ == '__main__':
    unittest.main()
